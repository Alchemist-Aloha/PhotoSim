import '../../core/terrain_geo.dart';

enum TerrainProvider {
  mapterhorn(
    'Mapterhorn',
    'mapterhorn-v1',
    512,
    '© Mapterhorn · https://mapterhorn.com/attribution',
  ),
  nasaNed(
    'NASA WorldWind USGS NED',
    'nasa-ned-10m-v1',
    256,
    'USGS NED 10 m · NASA WorldWind · https://worldwind.arc.nasa.gov/',
  ),
  nasaAster(
    'NASA/METI ASTER GDEM v2',
    'nasa-aster-v2-v1',
    256,
    'ASTER GDEM is a product of METI and NASA · NASA WorldWind',
  ),
  mapzen(
    'Mapzen Terrarium',
    'terrain-v1',
    256,
    'Mapzen Terrain Tiles · https://github.com/tilezen/joerd/blob/master/docs/attribution.md',
  );

  const TerrainProvider(
    this.label,
    this.cacheKey,
    this.pixels,
    this.attribution,
  );
  final String label, cacheKey, attribution;
  final int pixels;

  bool get isNasa => this == nasaNed || this == nasaAster;

  bool covers(TileId tile) {
    if (!isNasa) return true;
    final nw = tile.point(0, 0), se = tile.point(1, 1);
    // Restrict NED to the contiguous US; reject voids elsewhere rather than invent heights.
    return this == nasaNed
        ? nw.longitude >= -124.848974 &&
              se.longitude <= -66.885444 &&
              se.latitude >= 24.396308 &&
              nw.latitude <= 49.384358
        : se.latitude >= -83 && nw.latitude <= 83;
  }

  Uri request(TileId tile) {
    if (this == mapterhorn) {
      return Uri.parse(
        'https://tiles.mapterhorn.com/${tile.z}/${tile.x}/${tile.y}.webp',
      );
    }
    if (!isNasa) return tile.uri;
    final b = tile.mercatorBounds;
    return Uri.https('worldwind26.arc.nasa.gov', '/elev', {
      'SERVICE': 'WMS',
      'VERSION': '1.3.0',
      'REQUEST': 'GetMap',
      'LAYERS': this == nasaNed ? 'USGS-NED' : 'aster_v2',
      'STYLES': '',
      'CRS': 'EPSG:3857',
      'BBOX': '${b.west},${b.south},${b.east},${b.north}',
      'WIDTH': '$pixels',
      'HEIGHT': '$pixels',
      'FORMAT': 'application/bil16',
    });
  }
}
