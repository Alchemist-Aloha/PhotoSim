import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:latlong2/latlong.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../core/terrain_geo.dart';

double terrariumHeight(int red, int green, int blue) =>
    red * 256 + green + blue / 256 - 32768;

class HeightField {
  HeightField(this.heights, this.size);
  final Float32List heights;
  final int size;

  double sample(double u, double v) {
    // The raster samples are pixel centers, not tile boundaries.
    final x = (u * size - 0.5).clamp(0.0, size - 1.0);
    final y = (v * size - 0.5).clamp(0.0, size - 1.0);
    final x0 = x.floor(), y0 = y.floor();
    final x1 = math.min(x0 + 1, size - 1), y1 = math.min(y0 + 1, size - 1);
    final a =
        heights[y0 * size + x0] * (1 - (x - x0)) +
        heights[y0 * size + x1] * (x - x0);
    final b =
        heights[y1 * size + x0] * (1 - (x - x0)) +
        heights[y1 * size + x1] * (x - x0);
    return a * (1 - (y - y0)) + b * (y - y0);
  }
}

HeightField decodeTerrarium(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 33 ||
      bytes.length > 1024 * 1024 ||
      !List.generate(8, (i) => bytes[i] == signature[i]).every((v) => v)) {
    throw const FormatException('Invalid Terrarium PNG');
  }
  final header = ByteData.sublistView(bytes);
  // Bound decompression before handing untrusted PNG bytes to the decoder.
  if (header.getUint32(8) != 13 ||
      header.getUint32(12) != 0x49484452 ||
      header.getUint32(16) != 256 ||
      header.getUint32(20) != 256 ||
      bytes[24] != 8 ||
      bytes[25] != 2) {
    throw const FormatException('Expected a 256×256 RGB8 Terrarium tile');
  }
  image.Image? decoded;
  try {
    decoded = image.decodePng(bytes, frame: 0);
  } catch (error) {
    throw FormatException('Malformed Terrarium PNG: $error');
  }
  if (decoded == null) {
    throw const FormatException('Could not decode Terrarium PNG');
  }
  final heights = Float32List(256 * 256);
  for (var y = 0; y < 256; y++) {
    for (var x = 0; x < 256; x++) {
      final pixel = decoded.getPixel(x, y);
      final height = terrariumHeight(
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
      );
      if (height < -12000 || height > 10000) {
        throw const FormatException(
          'Terrain contains void or out-of-range elevations',
        );
      }
      heights[y * 256 + x] = height;
    }
  }
  return HeightField(heights, 256);
}

class TerrainPatch {
  TerrainPatch({
    required this.id,
    required this.field,
    required this.positions,
    required this.normals,
    required this.uvs,
    required this.indices,
    required this.resolution,
    required this.origin,
  });
  final TileId id;
  final HeightField field;
  final Float32List positions, normals, uvs;
  final List<int> indices;
  final int resolution;
  final LatLng origin;
}

class TerrainBuildRequest {
  TerrainBuildRequest(this.bytes, this.id, this.origin, this.resolution);
  final Uint8List bytes;
  final TileId id;
  final LatLng origin;
  final int resolution;
}

TerrainPatch decodeAndBuildTerrain(TerrainBuildRequest request) =>
    buildTerrainPatch(
      decodeTerrarium(request.bytes),
      request.id,
      request.origin,
      request.resolution,
    );

TerrainPatch buildTerrainPatch(
  HeightField field,
  TileId id,
  LatLng origin,
  int resolution,
) {
  if (resolution < 2 || resolution > 256) {
    throw ArgumentError('Invalid mesh resolution');
  }
  final frame = LocalFrame(origin);
  final cameraUv = id.uv(origin);
  List<double> axis(double camera) {
    final samples = [for (var i = 0; i <= resolution; i++) i / resolution];
    // Put the camera on an actual mesh vertex, not inside a coarsened hillside.
    if (camera > 0 &&
        camera < 1 &&
        !samples.any((value) => (value - camera).abs() < 1e-10)) {
      samples.add(camera);
      samples.sort();
    }
    return samples;
  }

  final containsCamera =
      cameraUv.x >= 0 && cameraUv.x <= 1 && cameraUv.y >= 0 && cameraUv.y <= 1;
  final us = axis(containsCamera ? cameraUv.x : -1);
  final vs = axis(containsCamera ? cameraUv.y : -1);
  final positions = <double>[], uvs = <double>[], indices = <int>[];
  for (final v in vs) {
    for (final u in us) {
      // shortcut: source vertical datum is uncorrected, add geoid conversion before precise horizon astronomy.
      final point = frame.project(id.point(u, v), field.sample(u, v));
      positions.addAll([point.x, point.y, point.z]);
      uvs.addAll([u, v]);
    }
  }
  for (var y = 0; y < vs.length - 1; y++) {
    for (var x = 0; x < us.length - 1; x++) {
      final a = y * us.length + x, b = a + 1, c = a + us.length;
      indices.addAll([a, c, b, b, c, c + 1]);
    }
  }
  final normals = List<double>.filled(positions.length, 0, growable: true);
  for (var i = 0; i < indices.length; i += 3) {
    Vector3 vertex(int index) => Vector3(
      positions[index * 3],
      positions[index * 3 + 1],
      positions[index * 3 + 2],
    );
    final normal = (vertex(indices[i + 1]) - vertex(indices[i])).cross(
      vertex(indices[i + 2]) - vertex(indices[i]),
    );
    for (var k = 0; k < 3; k++) {
      final index = indices[i + k] * 3;
      normals[index] += normal.x;
      normals[index + 1] += normal.y;
      normals[index + 2] += normal.z;
    }
  }
  for (var i = 0; i < normals.length; i += 3) {
    final normal = Vector3(normals[i], normals[i + 1], normals[i + 2])
      ..normalize();
    normals[i] = normal.x;
    normals[i + 1] = normal.y;
    normals[i + 2] = normal.z;
  }
  // Downward skirts bridge adjacent tiles' different pixel-center samples and LOD.
  final perimeter = [
    for (var x = 0; x < us.length; x++) x,
    for (var y = 1; y < vs.length; y++) y * us.length + us.length - 1,
    for (var x = us.length - 2; x >= 0; x--) (vs.length - 1) * us.length + x,
    for (var y = vs.length - 2; y > 0; y--) y * us.length,
  ];
  final low = <int>[];
  for (final index in perimeter) {
    low.add(positions.length ~/ 3);
    positions.addAll([
      positions[index * 3],
      positions[index * 3 + 1] - 150,
      positions[index * 3 + 2],
    ]);
    normals.addAll(normals.sublist(index * 3, index * 3 + 3));
    uvs.addAll(uvs.sublist(index * 2, index * 2 + 2));
  }
  for (var i = 0; i < perimeter.length; i++) {
    final next = (i + 1) % perimeter.length;
    final a = perimeter[i], b = perimeter[next], c = low[i], d = low[next];
    indices.addAll([a, b, c, b, d, c, a, c, b, b, c, d]);
  }
  return TerrainPatch(
    id: id,
    field: field,
    positions: Float32List.fromList(positions),
    normals: Float32List.fromList(normals),
    uvs: Float32List.fromList(uvs),
    indices: indices,
    resolution: resolution,
    origin: origin,
  );
}
