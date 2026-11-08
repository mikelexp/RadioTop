import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/station.dart';
import '../models/radio_country.dart';
import '../models/radio_taxonomy_option.dart';

class RadioBrowserClient {
  RadioBrowserClient({HttpClient? httpClient})
    : _http = httpClient ?? HttpClient() {
    _http.userAgent = 'RadioTop/1.0 (Linux desktop internet radio player)';
  }

  final HttpClient _http;
  static const _base = 'https://all.api.radio-browser.info';

  Future<List<RadioCountry>> countries() async {
    final data = await _get('/json/countries', {
      'order': 'name',
      'limit': '100000',
    });
    if (data is! List) {
      throw const FormatException('Invalid countries response.');
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(RadioCountry.fromJson)
        .where((country) => country.name.isNotEmpty)
        .toList();
  }

  Future<List<Station>> search({
    String query = '',
    int limit = 100,
    String? filterType,
    String? filterValue,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'order': 'votes',
      'reverse': 'true',
    };
    if (query.trim().isNotEmpty) params['name'] = query.trim();
    if (filterType != null && filterValue != null && filterValue.isNotEmpty) {
      final key = switch (filterType) {
        'Countries' => 'country',
        'Languages' => 'language',
        'Genres' => 'tag',
        _ => '',
      };
      if (key.isNotEmpty) params[key] = filterValue;
      if (filterType == 'Countries') params['countryExact'] = 'true';
      if (filterType == 'Languages') params['languageExact'] = 'true';
      if (filterType == 'Genres') params['tagExact'] = 'true';
    }
    final data = await _get('/json/stations/search', params);
    if (data is! List) {
      throw const FormatException('Invalid catalog response.');
    }
    final stations = <Station>[];
    for (final item in data) {
      if (item is! Map<String, dynamic>) continue;
      try {
        stations.add(Station.fromJson(item));
      } on FormatException {
        // A malformed entry should not discard the rest of the catalog.
      }
    }
    return stations;
  }

  Future<List<RadioTaxonomyOption>> taxonomy(String kind) async {
    const endpoints = {'Languages': '/json/languages', 'Genres': '/json/tags'};
    final path = endpoints[kind];
    if (path == null) return const [];
    final data = await _get(path, {
      'order': 'stationcount',
      'reverse': 'true',
      'limit': '100000',
    });
    if (data is! List) {
      throw const FormatException('Invalid taxonomy response.');
    }
    return data
        .whereType<Map<String, dynamic>>()
        .map(RadioTaxonomyOption.fromJson)
        .where((option) => option.name.isNotEmpty)
        .toList();
  }

  Future<dynamic> _get(String path, Map<String, String> query) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final request = await _http
        .getUrl(uri)
        .timeout(const Duration(seconds: 12));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 18));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Radio-Browser returned ${response.statusCode}.',
        uri: uri,
      );
    }
    return jsonDecode(body);
  }

  void close() => _http.close(force: true);
}
