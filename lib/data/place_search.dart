import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class PlaceSearchResult {
  const PlaceSearchResult({
    required this.name,
    required this.description,
    required this.location,
  });

  final String name;
  final String description;
  final LatLng location;
}

class PlaceSearchRepository {
  PlaceSearchRepository(this.client);

  final http.Client client;

  Future<List<PlaceSearchResult>> search(String query) async {
    if (query.trim().isEmpty) return [];
    // shortcut: the free Photon demo has no SLA; use a hosted instance at scale.
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': query.trim(),
      'limit': '5',
      'lang': 'en',
    });
    final response = await client
        .get(uri, headers: {'User-Agent': 'org.photosim.photosim'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Place search HTTP ${response.statusCode}',
        uri,
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, dynamic> || body['features'] is! List<dynamic>) {
      throw const FormatException('Invalid place search response');
    }
    final results = <PlaceSearchResult>[];
    for (final feature in body['features'] as List<dynamic>) {
      if (feature case {
        'properties': final Map<String, dynamic> properties,
        'geometry': {
          'type': 'Point',
          'coordinates': [final num longitude, final num latitude, ...],
        },
      }) {
        if (!latitude.isFinite ||
            !longitude.isFinite ||
            latitude.abs() > 90 ||
            longitude.abs() > 180) {
          continue;
        }
        final labels = <String>{
          for (final key in [
            'name',
            'street',
            'city',
            'county',
            'state',
            'country',
          ])
            if (properties[key] case final String value)
              if (value.trim().isNotEmpty) value.trim(),
        };
        if (labels.isEmpty) continue;
        results.add(
          PlaceSearchResult(
            name: labels.first,
            description: labels.skip(1).join(', '),
            location: LatLng(latitude.toDouble(), longitude.toDouble()),
          ),
        );
      }
      if (results.length == 5) break;
    }
    return results;
  }
}
