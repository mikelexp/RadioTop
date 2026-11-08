import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/station.dart';
import '../models/radio_country.dart';
import '../models/radio_taxonomy_option.dart';

class RadioBrowserClient {
  RadioBrowserClient({HttpClient? httpClient})
    : _http = httpClient ?? HttpClient() {
    _http.userAgent = 'RadioTop/1.0 (Linux desktop internet radio player)';
    _http.connectionTimeout = const Duration(seconds: 8);
  }

  final HttpClient _http;
  final Random _random = Random();
  List<Uri> _serverCache = const [];
  DateTime? _serverCacheTime;
  Future<List<Uri>>? _serverDiscovery;
  static final Uri _fallbackServer = Uri.https(
    'all.api.radio-browser.info',
    '',
  );
  static const _serverCacheDuration = Duration(minutes: 30);

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
    final servers = await _servers();
    Object? lastError;
    for (var index = 0; index < servers.length; index++) {
      final uri = servers[index].replace(path: path, queryParameters: query);
      try {
        final request = await _http.getUrl(uri);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close().timeout(
          const Duration(seconds: 12),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final status = response.statusCode;
          await response.drain<void>().timeout(const Duration(seconds: 2));
          throw _RadioBrowserStatusException(status, uri);
        }
        final body = await utf8.decoder
            .bind(response.timeout(const Duration(seconds: 20)))
            .join();
        return jsonDecode(body);
      } on Object catch (error) {
        lastError = error;
        if (!_isRetryable(error) || index == servers.length - 1) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 150 + _random.nextInt(250)),
        );
      }
    }
    throw lastError ?? const SocketException('No Radio-Browser servers found.');
  }

  bool _isRetryable(Object error) {
    if (error is _RadioBrowserStatusException) {
      return error.statusCode == 408 ||
          error.statusCode == 429 ||
          error.statusCode >= 500;
    }
    return error is SocketException ||
        error is HandshakeException ||
        error is TimeoutException ||
        error is HttpException;
  }

  Future<List<Uri>> _servers() async {
    final cachedAt = _serverCacheTime;
    if (_serverCache.isNotEmpty &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _serverCacheDuration) {
      return _serverCache;
    }
    final pending = _serverDiscovery ??= _discoverServers();
    try {
      _serverCache = await pending;
      _serverCacheTime = DateTime.now();
      return _serverCache;
    } finally {
      if (identical(_serverDiscovery, pending)) _serverDiscovery = null;
    }
  }

  Future<List<Uri>> _discoverServers() async {
    try {
      final addresses = await InternetAddress.lookup(
        'all.api.radio-browser.info',
      ).timeout(const Duration(seconds: 4));
      final uniqueAddresses = addresses
          .map((address) => address.address)
          .toSet();
      final names = await Future.wait(
        uniqueAddresses.map((address) async {
          try {
            final resolved = await InternetAddress(
              address,
              type: address.contains(':')
                  ? InternetAddressType.IPv6
                  : InternetAddressType.IPv4,
            ).reverse().timeout(const Duration(seconds: 3));
            final hostname = resolved.host.toLowerCase().replaceFirst(
              RegExp(r'\.$'),
              '',
            );
            if (hostname.endsWith('.api.radio-browser.info') &&
                hostname != 'all.api.radio-browser.info') {
              return hostname;
            }
          } catch (_) {
            // A reverse lookup can fail for one mirror; keep trying the rest.
          }
          return null;
        }),
      );
      final hosts = names.whereType<String>().toSet().toList()
        ..shuffle(_random);
      if (hosts.isNotEmpty) {
        return [...hosts.map((host) => Uri.https(host, '')), _fallbackServer];
      }
    } catch (_) {
      // Continue with Radio-Browser's DNS load-balancing endpoint.
    }
    return [_fallbackServer];
  }

  void close() => _http.close(force: true);
}

class _RadioBrowserStatusException extends HttpException {
  _RadioBrowserStatusException(this.statusCode, Uri uri)
    : super('Radio-Browser returned $statusCode.', uri: uri);

  final int statusCode;
}
