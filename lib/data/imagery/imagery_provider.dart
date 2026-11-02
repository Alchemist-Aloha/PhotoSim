import '../../core/terrain_geo.dart';

abstract interface class ImageryProvider {
  String get name;
  String get cacheKey;
  String get attribution;
  bool covers(TileId tile);

  /// Cached source tiles in row-major order: one preview tile, or 4×4 detail tiles.
  List<Uri> requests(TileId tile, int pixels);
}

enum ImageryTileKind { usgs, ign, eox }

/// Public cached tile endpoints; the repository stitches 1024px details from 4×4 z+2 tiles.
class TileImageryProvider implements ImageryProvider {
  const TileImageryProvider({
    required this.name,
    required this.cacheKey,
    required this.attribution,
    required this.kind,
    this.extents = const [(-180, -85.06, 180, 85.06)],
  });
  @override
  final String name, cacheKey, attribution;
  final ImageryTileKind kind;
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
  List<Uri> requests(TileId tile, int pixels) {
    if (pixels != 256 && pixels != 1024) {
      throw ArgumentError('Unsupported imagery resolution');
    }
    final grid = pixels == 256 ? 1 : 4;
    final zoom = tile.z + (grid == 4 ? 2 : 0);
    return [
      for (var dy = 0; dy < grid; dy++)
        for (var dx = 0; dx < grid; dx++)
          _uri(zoom, tile.x * grid + dx, tile.y * grid + dy),
    ];
  }

  Uri _uri(int z, int x, int y) => switch (kind) {
    ImageryTileKind.usgs => Uri.parse(
      'https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly'
      '/MapServer/tile/$z/$y/$x',
    ),
    ImageryTileKind.ign => Uri.parse('https://data.geopf.fr/wmts').replace(
      queryParameters: {
        'SERVICE': 'WMTS',
        'REQUEST': 'GetTile',
        'VERSION': '1.0.0',
        'LAYER': 'ORTHOIMAGERY.ORTHOPHOTOS',
        'STYLE': 'normal',
        'FORMAT': 'image/jpeg',
        'TILEMATRIXSET': 'PM',
        'TILEMATRIX': '$z',
        'TILEROW': '$y',
        'TILECOL': '$x',
      },
    ),
    ImageryTileKind.eox => Uri.parse(
      'https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless_3857/default'
      '/GoogleMapsCompatible/$z/$y/$x.jpg',
    ),
  };
}

/// A single WMS export, kept where PNG transparency distinguishes uncovered borders.
class WmsImageryProvider implements ImageryProvider {
  const WmsImageryProvider({
    required this.name,
    required this.cacheKey,
    required this.attribution,
    required this.endpoint,
    required this.layer,
    this.style = '',
    this.time,
    this.extents = const [(-180, -85.06, 180, 85.06)],
  });
  @override
  final String name, cacheKey, attribution;
  final String endpoint, layer, style;
  final String? time;
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
  List<Uri> requests(TileId tile, int pixels) {
    if (pixels != 256 && pixels != 1024) {
      throw ArgumentError('Unsupported imagery resolution');
    }
    final b = tile.mercatorBounds;
    return [
      Uri.parse(endpoint).replace(
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
          'TIME': ?time,
        },
      ),
    ];
  }
}

const naipImageryProvider = TileImageryProvider(
  name: 'USGS NAIP',
  cacheKey: 'naip-natural',
  attribution: 'USGS, USDA, The National Map: Orthoimagery',
  kind: ImageryTileKind.usgs,
  // Published conterminous-US service extent; intersection is not a coverage guarantee.
  extents: [(-124.85, 24.2, -66.85, 49.6)],
);

const nasaImageryProvider = WmsImageryProvider(
  name: 'NASA GIBS Landsat WELD 2000',
  cacheKey: 'nasa-weld-truecolor-2000',
  attribution: 'NASA EOSDIS GIBS · USGS/NASA Landsat WELD · annual mosaic 2000',
  endpoint: 'https://gibs.earthdata.nasa.gov/wms/epsg3857/best/wms.cgi',
  layer: 'Landsat_WELD_CorrectedReflectance_TrueColor_Global_Annual',
  time: '2000-12-01',
);

const imageryProviders = <ImageryProvider>[
  naipImageryProvider,
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
  TileImageryProvider(
    name: 'IGN BD ORTHO',
    cacheKey: 'ign-ortho',
    attribution: '© IGN · BD ORTHO · Licence Ouverte 2.0',
    kind: ImageryTileKind.ign,
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
  TileImageryProvider(
    name: 'EOX Sentinel-2 cloudless 2016',
    cacheKey: 'eox-s2-2016',
    attribution:
        'EOxCloudless https://cloudless.eox.at by EOX IT Services GmbH '
        '(Contains modified Copernicus Sentinel data 2016) · CC BY 4.0',
    kind: ImageryTileKind.eox,
  ),
];
