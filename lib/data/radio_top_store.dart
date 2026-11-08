import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/station.dart';

class RadioTopSettings {
  const RadioTopSettings({this.resultLimit = 100, this.favorites = const []});

  final int resultLimit;
  final List<Station> favorites;
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
    var favorites = <Station>[];
    try {
      final settings = await _readObject(_settingsFile);
      final parsedLimit = int.tryParse(
        settings?['resultLimit']?.toString() ?? '',
      );
      if (parsedLimit != null &&
          const {25, 50, 100, 200}.contains(parsedLimit)) {
        resultLimit = parsedLimit;
      }
    } on FileSystemException {
      // Missing or inaccessible settings use their safe defaults.
    } on FormatException {
      // A malformed settings file must not stop the app from opening.
    }
    try {
      final decoded = await _readJson(_favoritesFile);
      if (decoded is List) {
        favorites = decoded
            .whereType<Map<String, dynamic>>()
            .map((json) {
              try {
                return Station.fromJson(json);
              } on FormatException {
                return null;
              }
            })
            .whereType<Station>()
            .toList();
      }
    } on FileSystemException {
      // Favorites are optional; start with an empty collection if unavailable.
    } on FormatException {
      // Ignore corrupt favorites while preserving the rest of the app.
    }
    return RadioTopSettings(resultLimit: resultLimit, favorites: favorites);
  }

  Future<void> saveSettings({required int resultLimit}) => _enqueue(() async {
    await _directory.create(recursive: true);
    await _settingsFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({'resultLimit': resultLimit}),
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
}
