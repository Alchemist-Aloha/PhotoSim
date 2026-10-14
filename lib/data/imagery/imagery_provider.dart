import 'dart:convert';

import '../../core/terrain_geo.dart';

abstract interface class ImageryProvider {
  String get name;
  String get attribution;
  bool covers(TileId tile);
  Uri request(TileId tile, int pixels);
}

class NaipProvider implements ImageryProvider {
  const NaipProvider();
  static const endpoint =
      'https://imagery.nationalmap.gov/arcgis/rest/services/USGSNAIPImagery/ImageServer';
  @override
  String get name => 'USGS NAIP';
  @override
  String get attribution => 'USGS, USDA, The National Map: Orthoimagery';

  @override
  bool covers(TileId tile) {
    final b = tile.mercatorBounds;
    // Published conterminous-US service extent; intersection is not a coverage guarantee.
    return b.east > -13896162.90 &&
        b.west < -7441890.60 &&
        b.north > 2812730.70 &&
        b.south < 6372359.70;
  }

  @override
  Uri request(TileId tile, int pixels) {
    if (pixels != 256 && pixels != 1024) {
      throw ArgumentError('Unsupported imagery resolution');
    }
    final b = tile.mercatorBounds;
    return Uri.parse('$endpoint/exportImage').replace(
      queryParameters: {
        'f': 'image',
        'bbox': '${b.west},${b.south},${b.east},${b.north}',
        'bboxSR': '3857',
        'imageSR': '3857',
        'size': '$pixels,$pixels',
        'adjustAspectRatio': 'false',
        'format': 'png32',
        'interpolation': 'RSP_BilinearInterpolation',
        'renderingRule': jsonEncode({'rasterFunction': 'NaturalColor'}),
      },
    );
  }
}
