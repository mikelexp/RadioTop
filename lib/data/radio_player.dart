import 'dart:async';

import 'package:media_kit/media_kit.dart';

import '../models/station.dart';

/// Owns the native media player used for live radio streams.
class RadioPlayerService {
  RadioPlayerService() : _player = Player();

  final Player _player;
  bool _disposed = false;
  int _playRequest = 0;
  Future<void> _operationQueue = Future<void>.value();
  final StreamController<String?> _currentTrackController =
      StreamController<String?>.broadcast();
  bool _icyTitleObserved = false;
  int _bufferSeconds = 5;

  Stream<bool> get playing => _player.stream.playing;
  Stream<bool> get buffering => _player.stream.buffering;
  Stream<AudioParams> get audioParams => _player.stream.audioParams;
  Stream<double?> get audioBitrate => _player.stream.audioBitrate;
  Stream<AudioTrack> get audioTrack =>
      _player.stream.track.map((track) => track.audio);
  Stream<String> get errors => _player.stream.error;
  Stream<String?> get currentTrack => _currentTrackController.stream;

  Future<void> setBufferSeconds(int seconds) async {
    _bufferSeconds = seconds.clamp(1, 30).toInt();
    await _applyBufferSettings();
  }

  Future<void> play(Station station) {
    final request = ++_playRequest;
    final operation = _operationQueue.then((_) async {
      if (_disposed || request != _playRequest) return;
      _currentTrackController.add(null);
      await _applyBufferSettings();
      await _player.open(
        Media(
          station.streamUrl,
          httpHeaders: {
            'Icy-MetaData': '1',
            'User-Agent': 'RadioTop/1.0.0 (Linux desktop radio player)',
          },
        ),
      );
      if (_disposed || request != _playRequest) return;
      await _observeIcyTitle();
      await _player.play();
    });
    _operationQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> pause() {
    _playRequest++;
    final operation = _operationQueue.then((_) => _player.pause());
    _operationQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> stop() {
    _playRequest++;
    final operation = _operationQueue.then((_) => _player.stop());
    _operationQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _observeIcyTitle() async {
    if (_icyTitleObserved) return;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    _icyTitleObserved = true;
    try {
      await platform.observeProperty('metadata/by-key/icy-title', (
        value,
      ) async {
        if (_disposed) return;
        final title = value.trim();
        _currentTrackController.add(
          title.isEmpty || title == 'null' ? null : title,
        );
      });
    } catch (_) {
      // Radio metadata is optional; playback should continue without it.
      _icyTitleObserved = false;
    }
  }

  Future<void> _applyBufferSettings() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final seconds = '$_bufferSeconds';
    try {
      await platform.setProperty('cache', 'yes');
      await platform.setProperty('cache-secs', seconds);
      await platform.setProperty('cache-pause', 'yes');
      await platform.setProperty('cache-pause-wait', seconds);
      await platform.setProperty('cache-pause-initial', 'yes');
    } catch (_) {
      // Keep playback available if a backend rejects a cache option.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _playRequest++;
    await _operationQueue;
    await _player.dispose();
    await _currentTrackController.close();
  }
}
