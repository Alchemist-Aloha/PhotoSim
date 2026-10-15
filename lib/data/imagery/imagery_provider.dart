import 'dart:convert';

import '../../core/terrain_geo.dart';

abstract interface class ImageryProvider {
  String get name;
  String get cacheKey;
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
  String get cacheKey => 'naip-natural';
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

class WmsImageryProvider implements ImageryProvider {
  const WmsImageryProvider({
    required this.name,
    required this.cacheKey,
    required this.attribution,
    required this.endpoint,
    required this.layer,
    this.style = '',
    this.extents = const [(-180, -85.06, 180, 85.06)],
  });
  @override
  final String name, cacheKey, attribution;
  final String endpoint, layer, style;
  final List<(double, double, double, double)> extents;

  @override
  bool covers(TileId tile) {
    final nw = tile.point(0, 0), se = tile.point(1, 1);
    return extents.any(
      (b) =>
          se.longitude > b.$1 &&
          nw.latitude > b.$2 &&
          nw.longitude < b.$3 &&
          se.latitude < b.$4,
    );
  }

  @override
  Uri request(TileId tile, int pixels) {
    if (pixels != 256 && pixels != 1024) {
      throw ArgumentError('Unsupported imagery resolution');
    }
    final b = tile.mercatorBounds;
    return Uri.parse(endpoint).replace(
      queryParameters: {
        'SERVICE': 'WMS',
        'VERSION': '1.3.0',
        'REQUEST': 'GetMap',
        'LAYERS': layer,
        'STYLES': style,
        'CRS': 'EPSG:3857',
        'BBOX': '${b.west},${b.south},${b.east},${b.north}',
        'WIDTH': '$pixels',
        'HEIGHT': '$pixels',
        'FORMAT': 'image/png',
        'TRANSPARENT': 'TRUE',
      },
    );
  }
}

const imageryProviders = <ImageryProvider>[
  NaipProvider(),
  WmsImageryProvider(
    name: 'swisstopo SWISSIMAGE',
    cacheKey: 'swissimage',
    attribution: '©swisstopo',
    endpoint: 'https://wms.geo.admin.ch/',
    // Use the Swiss-only layer, not the background group containing third-party SPOT imagery.
    layer: 'ch.swisstopo.images-swissimage',
    style: 'default',
    extents: [(5.9, 45.7, 10.6, 47.9)],
  ),
  WmsImageryProvider(
    name: 'IGN BD ORTHO',
    cacheKey: 'ign-ortho',
    attribution: '© IGN · BD ORTHO · Licence Ouverte 2.0',
    endpoint: 'https://data.geopf.fr/wms-r/wms',
    layer: 'ORTHOIMAGERY.ORTHOPHOTOS',
    style: 'normal',
    // Approximate search extents, not coverage guarantees.
    extents: [
      (-5.5, 41.2, 10, 51.2),
      (-54.7, 2, -51.5, 6),
      (-61.9, 15.7, -60.9, 16.6),
      (-61.3, 14.3, -60.7, 15),
      (-63.2, 17.8, -62.7, 18.2),
      (55.1, -21.5, 55.9, -20.8),
      (44.9, -13.2, 45.4, -12.5),
      (-56.5, 46.7, -56, 47.2),
    ],
  ),
  WmsImageryProvider(
    name: 'EOX Sentinel-2 cloudless 2016',
    cacheKey: 'eox-s2-2016',
    attribution:
        'EOxCloudless https://cloudless.eox.at by EOX IT Services GmbH '
        '(Contains modified Copernicus Sentinel data 2016) · CC BY 4.0',
    endpoint: 'https://tiles.maps.eox.at/wms',
    // The unversioned layer is explicitly the CC BY 2016 mosaic in GetCapabilities.
    layer: 's2cloudless_3857',
  ),
];
