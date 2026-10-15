import '../../core/terrain_geo.dart';

enum TerrainProvider {
  mapterhorn(
    'Mapterhorn',
    'mapterhorn-v1',
    512,
    '© Mapterhorn · https://mapterhorn.com/attribution',
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

  Uri request(TileId tile) => this == TerrainProvider.mapterhorn
      ? Uri.parse(
          'https://tiles.mapterhorn.com/${tile.z}/${tile.x}/${tile.y}.webp',
        )
      : tile.uri;
}
