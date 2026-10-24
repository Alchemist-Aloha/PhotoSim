import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:latlong2/latlong.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../core/terrain_geo.dart';
import 'terrain_provider.dart';

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
  return _heightField(decoded, 256);
}

HeightField decodeMapterhorn(Uint8List bytes) {
  if (bytes.length < 25 || bytes.length > 1024 * 1024) {
    throw const FormatException('Invalid terrain WebP');
  }
  final header = ByteData.sublistView(bytes);
  if (header.getUint32(0) != 0x52494646 ||
      header.getUint32(4, Endian.little) + 8 != bytes.length ||
      header.getUint32(8) != 0x57454250 ||
      header.getUint32(12) != 0x5650384c ||
      bytes[20] != 0x2f) {
    throw const FormatException('Expected lossless VP8L terrain WebP');
  }
  final dimensions = header.getUint32(21, Endian.little);
  if ((dimensions & 0x3fff) + 1 != 512 ||
      ((dimensions >> 14) & 0x3fff) + 1 != 512 ||
      dimensions >> 29 != 0) {
    throw const FormatException('Expected a 512×512 terrain WebP');
  }
  image.Image? decoded;
  try {
    final decoder = image.WebPDecoder()..maxPixels = 512 * 512;
    final info = decoder.startDecode(bytes);
    if (info == null || info.width != 512 || info.height != 512) {
      throw const FormatException('Invalid terrain WebP dimensions');
    }
    decoded = decoder.decodeFrame(0);
  } catch (error) {
    throw FormatException('Malformed terrain WebP: $error');
  }
  if (decoded == null) {
    throw const FormatException('Could not decode terrain WebP');
  }
  return _heightField(decoded, 512);
}

HeightField _heightField(image.Image decoded, int size) {
  final heights = Float32List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final pixel = decoded.getPixel(x, y);
      final height = terrariumHeight(
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
      );
      if (pixel.a != 255 || height < -12000 || height > 10000) {
        throw const FormatException(
          'Terrain contains void or out-of-range elevations',
        );
      }
      heights[y * size + x] = height;
    }
  }
  return HeightField(heights, size);
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
    required this.us,
    required this.vs,
  });
  final TileId id;
  final HeightField field;
  final Float32List positions, normals, uvs;
  final List<int> indices;
  final int resolution;
  final LatLng origin;
  final List<double> us, vs;

  /// Conservative ground: source raster or the actual rendered surface, whichever is higher.
  /// Skirts are excluded. Missing coverage must pause navigation, not guess a height.
  double? groundElevationAt(LatLng location) {
    final uv = id.uv(location);
    if (uv.x < -1e-9 || uv.x > 1 + 1e-9 || uv.y < -1e-9 || uv.y > 1 + 1e-9) {
      return null;
    }
    int interval(List<double> axis, double value) {
      final next = axis.indexWhere((sample) => sample >= value.clamp(0.0, 1.0));
      return (next <= 0 ? 0 : next - 1).clamp(0, axis.length - 2);
    }

    final column = interval(us, uv.x), row = interval(vs, uv.y);
    final frame = LocalFrame(origin);
    final zero = frame.project(location, 0);
    final up = frame.project(location, 1) - zero;
    Vector3 vertex(int index) => Vector3(
      positions[index * 3],
      positions[index * 3 + 1],
      positions[index * 3 + 2],
    );
    double? edgeHeight;
    double grounded(double height) =>
        math.max(field.sample(uv.x, uv.y), height).clamp(-12000.0, 10000.0);
    // Adjacent cells cover float32 edge rounding and geographic-to-planar interpolation.
    for (
      var y = math.max(0, row - 1);
      y <= math.min(vs.length - 2, row + 1);
      y++
    ) {
      for (
        var x = math.max(0, column - 1);
        x <= math.min(us.length - 2, column + 1);
        x++
      ) {
        final start = (y * (us.length - 1) + x) * 6;
        for (var triangle = start; triangle < start + 6; triangle += 3) {
          final a = vertex(indices[triangle]);
          final ab = vertex(indices[triangle + 1]) - a;
          final ac = vertex(indices[triangle + 2]) - a;
          final normal = ab.cross(ac);
          final denominator = normal.dot(up);
          if (denominator.abs() < 1e-12) continue;
          final height = normal.dot(a - zero) / denominator;
          final hit = zero + up * height - a;
          final length2 = normal.length2;
          final b = hit.cross(ac).dot(normal) / length2;
          final c = ab.cross(hit).dot(normal) / length2;
          if (b >= -1e-6 && c >= -1e-6 && b + c <= 1 + 1e-6) {
            return grounded(height);
          }
          // Float32 boundary vertices can lie just inside the true geographic tile edge.
          if (b >= -0.001 && c >= -0.001 && b + c <= 1.001) {
            edgeHeight = edgeHeight == null
                ? height
                : math.max(edgeHeight, height);
          }
        }
      }
    }
    return edgeHeight == null ? null : grounded(edgeHeight);
  }
}

class TerrainBuildRequest {
  TerrainBuildRequest(
    this.bytes,
    this.id,
    this.origin,
    this.resolution, {
    this.provider = TerrainProvider.mapzen,
    TileId? rasterId,
  }) : rasterId = rasterId ?? id;
  final Uint8List bytes;
  final TileId id, rasterId;
  final TerrainProvider provider;
  final LatLng origin;
  final int resolution;
}

TerrainPatch decodeAndBuildTerrain(TerrainBuildRequest request) {
  var field = request.provider == TerrainProvider.mapterhorn
      ? decodeMapterhorn(request.bytes)
      : decodeTerrarium(request.bytes);
  final id = request.id, rasterId = request.rasterId;
  if (rasterId.key != id.key) {
    if (request.provider != TerrainProvider.mapterhorn ||
        rasterId.z != id.z - 1 ||
        rasterId.x != id.x ~/ 2 ||
        rasterId.y != id.y ~/ 2) {
      throw const FormatException(
        'Terrain raster does not cover requested tile',
      );
    }
    // The global mosaic stops at z12; crop its exact child quadrant, without inventing detail.
    final heights = Float32List(256 * 256);
    final left = id.x % 2 * 256, top = id.y % 2 * 256;
    for (var row = 0; row < 256; row++) {
      final start = (top + row) * 512 + left;
      heights.setRange(row * 256, (row + 1) * 256, field.heights, start);
    }
    field = HeightField(heights, 256);
  }
  return buildTerrainPatch(field, id, request.origin, request.resolution);
}

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
    // Full-detail meshes keep actual raster peaks instead of averaging pixel centres away.
    final samples = resolution >= field.size
        ? [
            0.0,
            for (var i = 0; i < resolution; i++) (i + 0.5) / resolution,
            1.0,
          ]
        : [for (var i = 0; i <= resolution; i++) i / resolution];
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
      positions
        ..add(point.x)
        ..add(point.y)
        ..add(point.z);
      uvs
        ..add(u)
        ..add(v);
    }
  }
  for (var y = 0; y < vs.length - 1; y++) {
    for (var x = 0; x < us.length - 1; x++) {
      final a = y * us.length + x, b = a + 1, c = a + us.length;
      indices
        ..add(a)
        ..add(c)
        ..add(b)
        ..add(b)
        ..add(c)
        ..add(c + 1);
    }
  }
  final normals = List<double>.filled(positions.length, 0, growable: true);
  // The accumulate loop runs once per triangle (132k at r256). Building a closure and
  // fresh Vector3s inside it churned ~7 objects per triangle; Vector3.cross also
  // allocates. These are the same expressions in the same order as Vector3.cross.
  for (var i = 0; i < indices.length; i += 3) {
    final i0 = indices[i] * 3, i1 = indices[i + 1] * 3, i2 = indices[i + 2] * 3;
    final ax = positions[i1] - positions[i0];
    final ay = positions[i1 + 1] - positions[i0 + 1];
    final az = positions[i1 + 2] - positions[i0 + 2];
    final bx = positions[i2] - positions[i0];
    final by = positions[i2 + 1] - positions[i0 + 1];
    final bz = positions[i2 + 2] - positions[i0 + 2];
    final nx = ay * bz - az * by;
    final ny = az * bx - ax * bz;
    final nz = ax * by - ay * bx;
    for (var k = 0; k < 3; k++) {
      final index = indices[i + k] * 3;
      normals[index] += nx;
      normals[index + 1] += ny;
      normals[index + 2] += nz;
    }
  }
  final normal = Vector3.zero();
  for (var i = 0; i < normals.length; i += 3) {
    normal.setValues(normals[i], normals[i + 1], normals[i + 2]);
    normal.normalize();
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
    positions
      ..add(positions[index * 3])
      ..add(positions[index * 3 + 1] - 150)
      ..add(positions[index * 3 + 2]);
    normals
      ..add(normals[index * 3])
      ..add(normals[index * 3 + 1])
      ..add(normals[index * 3 + 2]);
    uvs
      ..add(uvs[index * 2])
      ..add(uvs[index * 2 + 1]);
  }
  for (var i = 0; i < perimeter.length; i++) {
    final next = (i + 1) % perimeter.length;
    final a = perimeter[i], b = perimeter[next], c = low[i], d = low[next];
    indices
      ..add(a)
      ..add(b)
      ..add(c)
      ..add(b)
      ..add(d)
      ..add(c)
      ..add(a)
      ..add(c)
      ..add(b)
      ..add(b)
      ..add(c)
      ..add(d);
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
    us: us,
    vs: vs,
  );
}
