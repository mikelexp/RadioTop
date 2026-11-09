import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/station.dart';

class RadioTopSettings {
  const RadioTopSettings({
    this.resultLimit = 100,
    this.retryEnabled = true,
    this.retryIntervalSeconds = 5,
    this.bufferSeconds = 5,
    this.themeMode = 'system',
    this.favorites = const [],
    this.favoritesWarning,
  });

  final int resultLimit;
  final bool retryEnabled;
  final int retryIntervalSeconds;
  final int bufferSeconds;
  final String themeMode;
  final List<Station> favorites;
  final String? favoritesWarning;
}

class RadioTopStore {
  RadioTopStore({String? homeDirectory})
    : _directory = Directory(
        '${homeDirectory ?? Platform.environment['HOME'] ?? '.'}/.config/radiotop',
      );

  final Directory _directory;
  Future<void> _writeQueue = Future<void>.value();

  File get _settingsFile => File('${_directory.path}/config.json');
  File get _favoritesFile => File('${_directory.path}/favorites.json');

  Future<RadioTopSettings> load() async {
    var resultLimit = 100;
    var retryEnabled = true;
    var retryIntervalSeconds = 5;
    var bufferSeconds = 5;
    var themeMode = 'system';
    var favorites = <Station>[];
    String? favoritesWarning;
    try {
      final settings = await _readObject(_settingsFile);
      final parsedLimit = int.tryParse(
        settings?['resultLimit']?.toString() ?? '',
      );
      if (parsedLimit != null &&
          const {25, 50, 100, 200}.contains(parsedLimit)) {
        resultLimit = parsedLimit;
      }
      if (settings?['retryEnabled'] is bool) {
        retryEnabled = settings!['retryEnabled'] as bool;
      }
      final parsedRetryInterval = int.tryParse(
        settings?['retryIntervalSeconds']?.toString() ?? '',
      );
      if (parsedRetryInterval != null &&
          const {1, 3, 5, 10, 15, 30}.contains(parsedRetryInterval)) {
        retryIntervalSeconds = parsedRetryInterval;
      }
      final parsedBufferSeconds = int.tryParse(
        settings?['bufferSeconds']?.toString() ?? '',
      );
      if (parsedBufferSeconds != null &&
          parsedBufferSeconds >= 1 &&
          parsedBufferSeconds <= 30) {
        bufferSeconds = parsedBufferSeconds;
      }
      final storedThemeMode = settings?['themeMode'];
      if (storedThemeMode is String &&
          const {'system', 'light', 'dark'}.contains(storedThemeMode)) {
        themeMode = storedThemeMode;
      }
    } on FileSystemException {
      // Missing or inaccessible settings use their safe defaults.
    } on FormatException {
      // A malformed settings file must not stop the app from opening.
    }
    try {
      final decoded = await _readJson(_favoritesFile);
      if (decoded == null) {
        favoritesWarning = 'Favorites file not found: ${_favoritesFile.path}';
      }
      final entries = switch (decoded) {
        List list => list,
        Map map => map['favorites'] is List
            ? map['favorites'] as List
            : map['stations'] is List
            ? map['stations'] as List
            : map.values.toList(),
        _ => const <dynamic>[],
      };
      var skipped = 0;
      for (final entry in entries) {
        if (entry is! Map) {
          skipped++;
          continue;
        }
        try {
          final json = Map<String, dynamic>.from(entry);
          final nested = json['station'];
          final stationData = nested is Map
              ? Map<String, dynamic>.from(nested)
              : json;
          favorites.add(Station.fromJson(_normalizeFavorite(stationData)));
        } catch (_) {
          // One malformed entry must not hide the remaining favorites.
          skipped++;
        }
      }
      if (skipped > 0) {
        favoritesWarning =
            '$skipped favorite entr${skipped == 1 ? 'y was' : 'ies were'} skipped because its station data could not be read.';
      }
      if (decoded != null && decoded is! List && decoded is! Map) {
        favoritesWarning = 'The favorites file must contain a JSON list.';
      }
    } on FileSystemException {
      favoritesWarning = 'Could not read ${_favoritesFile.path}.';
    } on FormatException {
      favoritesWarning = 'The favorites file is not valid JSON.';
    } catch (error) {
      favoritesWarning = 'Could not load favorites: $error';
    }
    return RadioTopSettings(
      resultLimit: resultLimit,
      retryEnabled: retryEnabled,
      retryIntervalSeconds: retryIntervalSeconds,
      bufferSeconds: bufferSeconds,
      themeMode: themeMode,
      favorites: favorites,
      favoritesWarning: favoritesWarning,
    );
  }

  Future<void> saveSettings({
    required int resultLimit,
    required bool retryEnabled,
    required int retryIntervalSeconds,
    required int bufferSeconds,
    required String themeMode,
  }) => _enqueue(() async {
    await _directory.create(recursive: true);
    await _settingsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'resultLimit': resultLimit,
        'retryEnabled': retryEnabled,
        'retryIntervalSeconds': retryIntervalSeconds,
        'bufferSeconds': bufferSeconds,
        'themeMode': themeMode,
      }),
      flush: true,
    );
  });

  Future<void> saveFavorites(Iterable<Station> stations) {
    final snapshot = stations.map((station) => station.toJson()).toList();
    return _enqueue(() async {
      await _directory.create(recursive: true);
      await _favoritesFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(snapshot),
        flush: true,
      );
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _writeQueue.then((_) => operation());
    _writeQueue = next.catchError((Object _) {});
    return next;
  }

  Future<Map<String, dynamic>?> _readObject(File file) async {
    final decoded = await _readJson(file);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<dynamic> _readJson(File file) async {
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString());
  }

  Map<String, dynamic> _normalizeFavorite(Map<String, dynamic> json) => {
    ...json,
    'stationuuid': json['stationuuid'] ?? json['uuid'],
    'url_resolved':
        json['url_resolved'] ?? json['streamUrl'] ?? json['stream_url'] ?? json['url'],
    'countrycode': json['countrycode'] ?? json['countryCode'],
  };
}
