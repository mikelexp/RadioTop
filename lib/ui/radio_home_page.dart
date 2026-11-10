import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../data/radio_browser_client.dart';
import '../data/radio_player.dart';
import '../data/radio_top_store.dart';
import '../models/radio_country.dart';
import '../models/station.dart';
import '../models/radio_taxonomy_option.dart';

const _lime = Color(0xFFB7F36B);
const _muted = Color(0xFF858B86);
const _line = Color(0xFF292E2B);
const _bitrateRanges = <String, ({int? min, int? max})>{
  'Under 64 kbps': (min: null, max: 63),
  '64–127 kbps': (min: 64, max: 127),
  '128–191 kbps': (min: 128, max: 191),
  '192–319 kbps': (min: 192, max: 319),
  '320 kbps and up': (min: 320, max: null),
};

Color _accent(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
    ? const Color(0xFF42651B)
    : _lime;

Color _dividerColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
    ? const Color(0x1F000000)
    : _line;

enum _MiddleRouteKind { stations, countries, taxonomy, settings }

class _MiddleRoute {
  const _MiddleRoute.stations({
    this.section = 'Explore',
    this.filterType,
    this.filterValue,
  }) : kind = _MiddleRouteKind.stations,
       category = null;

  const _MiddleRoute.countries()
    : kind = _MiddleRouteKind.countries,
      category = null,
      section = 'Explore',
      filterType = null,
      filterValue = null;

  const _MiddleRoute.taxonomy(this.category)
    : kind = _MiddleRouteKind.taxonomy,
      section = 'Explore',
      filterType = null,
      filterValue = null;

  const _MiddleRoute.settings()
    : kind = _MiddleRouteKind.settings,
      category = null,
      section = 'Settings',
      filterType = null,
      filterValue = null;

  final _MiddleRouteKind kind;
  final String? category;
  final String section;
  final String? filterType;
  final String? filterValue;
}

class RadioHomePage extends StatefulWidget {
  const RadioHomePage({
    super.key,
    required this.client,
    required this.favorites,
    required this.store,
    required this.onThemeModeChanged,
  });

  final RadioBrowserClient client;
  final StationFavorites favorites;
  final RadioTopStore store;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<RadioHomePage> createState() => _RadioHomePageState();
}

class _RadioHomePageState extends State<RadioHomePage> {
  final _radioPlayer = RadioPlayerService();
  final _searchController = TextEditingController();
  final _countrySearchController = TextEditingController();
  final _taxonomySearchController = TextEditingController();
  final Map<String, List<RadioTaxonomyOption>> _taxonomyOptionsByCategory = {};
  final List<_MiddleRoute> _middleHistory = [];
  int _browseListGeneration = 0;
  List<Station> _stations = [];
  List<RadioCountry> _countries = [];
  Station? _selected;
  String? _activeTaxonomy;
  String? _activeValue;
  String _section = 'Explore';
  String? _error;
  String? _favoritesWarning;
  bool _loading = true;
  bool _settingsLoaded = false;
  bool _showCountryBrowser = false;
  String? _browseTaxonomy;
  bool _countriesLoading = false;
  String? _countryError;
  bool _taxonomyLoading = false;
  int _taxonomyRequestGeneration = 0;
  String? _taxonomyError;
  int _limit = 100;
  int _minimumGenreStationCount = 10;
  String? _selectedCountry;
  String? _selectedGenre;
  String? _selectedLanguage;
  String? _selectedCodec;
  String? _selectedBitrateRange;
  bool _retryEnabled = true;
  int _retryIntervalSeconds = 5;
  int _bufferSeconds = 5;
  String _themeMode = 'system';
  bool _isPlaying = false;
  bool _playbackLoading = false;
  String? _playbackError;
  String? _currentTrack;
  bool _isBuffering = false;
  double _volume = 100;
  double _lastNonZeroVolume = 100;
  AudioParams? _audioParams;
  AudioTrack? _audioTrack;
  double? _audioBitrate;
  int _stationSelectionRequest = 0;
  bool _playbackRequested = false;
  Timer? _retryTimer;
  Timer? _connectionTimer;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<String>? _playbackErrorSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<String?>? _currentTrackSubscription;
  StreamSubscription<AudioParams>? _audioParamsSubscription;
  StreamSubscription<AudioTrack>? _audioTrackSubscription;
  StreamSubscription<double?>? _audioBitrateSubscription;
  StreamSubscription<double>? _volumeSubscription;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _playingSubscription = _radioPlayer.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
          if (playing) {
            _playbackLoading = false;
            _playbackError = null;
            _retryTimer?.cancel();
            _retryTimer = null;
            _connectionTimer?.cancel();
            _connectionTimer = null;
          }
        });
      }
    });
    _playbackErrorSubscription = _radioPlayer.errors.listen(
      _handlePlaybackError,
    );
    _bufferingSubscription = _radioPlayer.buffering.listen((buffering) {
      if (mounted) {
        final wasBuffering = _isBuffering;
        setState(() {
          _isBuffering = buffering;
          if (buffering) _playbackLoading = false;
        });
        if (buffering && _playbackRequested && _connectionTimer == null) {
          _connectionTimer = Timer(const Duration(seconds: 20), () {
            if (!mounted ||
                !_playbackRequested ||
                !_isBuffering ||
                _isPlaying) {
              return;
            }
            _connectionTimer = null;
            _handlePlaybackError('Buffering timed out');
          });
        } else if (!buffering) {
          if (wasBuffering) {
            _connectionTimer?.cancel();
            _connectionTimer = null;
            if (_playbackRequested && !_isPlaying) {
              _connectionTimer = Timer(const Duration(seconds: 20), () {
                if (!mounted ||
                    !_playbackRequested ||
                    _isPlaying ||
                    _isBuffering) {
                  return;
                }
                _connectionTimer = null;
                _handlePlaybackError('Playback stalled');
              });
            }
          }
        }
      }
    });
    _currentTrackSubscription = _radioPlayer.currentTrack.listen((track) {
      if (mounted) setState(() => _currentTrack = track);
    });
    _audioParamsSubscription = _radioPlayer.audioParams.listen((params) {
      if (mounted) setState(() => _audioParams = params);
    });
    _audioTrackSubscription = _radioPlayer.audioTrack.listen((track) {
      if (mounted) setState(() => _audioTrack = track);
    });
    _audioBitrateSubscription = _radioPlayer.audioBitrate.listen((bitrate) {
      if (mounted) setState(() => _audioBitrate = bitrate);
    });
    _volume = _radioPlayer.currentVolume;
    _lastNonZeroVolume = _volume > 0 ? _volume : 100;
    _volumeSubscription = _radioPlayer.volume.listen((volume) {
      if (mounted) {
        setState(() {
          _volume = volume;
          if (volume > 0) _lastNonZeroVolume = volume;
        });
      }
    });
    _initialize();
  }

  Future<void> _selectStation(Station station) async {
    final request = ++_stationSelectionRequest;
    _playbackRequested = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _connectionTimer?.cancel();
    setState(() {
      _selected = station;
      _playbackError = null;
      _playbackLoading = true;
      _audioParams = null;
      _audioTrack = null;
      _audioBitrate = null;
      _currentTrack = null;
      _isBuffering = false;
    });
    _connectionTimer = Timer(Duration(seconds: _bufferSeconds + 15), () {
      if (!mounted ||
          request != _stationSelectionRequest ||
          !_playbackRequested ||
          _isPlaying) {
        return;
      }
      _connectionTimer = null;
      _handlePlaybackError('Connection timed out');
    });
    try {
      await _radioPlayer.play(station);
      if (mounted && request == _stationSelectionRequest) {
        setState(() => _playbackLoading = false);
      }
    } catch (error) {
      if (!mounted || request != _stationSelectionRequest) return;
      _handlePlaybackError(error.toString());
    }
  }

  void _handlePlaybackError(String _) {
    if (!mounted) return;
    _connectionTimer?.cancel();
    _connectionTimer = null;
    final station = _selected;
    final wasRequested = _playbackRequested;
    final shouldRetry = wasRequested && station != null && _retryEnabled;
    if (wasRequested && !_retryEnabled) _playbackRequested = false;
    setState(() {
      _playbackLoading = false;
      _isPlaying = false;
      _playbackError = shouldRetry
          ? 'Stream interrupted. Retrying in $_retryIntervalSeconds seconds…'
          : wasRequested && !_retryEnabled
          ? 'Stream interrupted. Automatic retry is off.'
          : 'Could not start this station. Try again.';
    });
    if (!shouldRetry || _retryTimer != null) return;
    final request = _stationSelectionRequest;
    _retryTimer = Timer(Duration(seconds: _retryIntervalSeconds), () {
      _retryTimer = null;
      if (!mounted ||
          !_playbackRequested ||
          request != _stationSelectionRequest) {
        return;
      }
      _selectStation(station);
    });
  }

  Future<void> _togglePlayback() async {
    if (_selected == null) return;
    if (_playbackRequested) {
      _playbackRequested = false;
      _retryTimer?.cancel();
      _retryTimer = null;
      _connectionTimer?.cancel();
      _connectionTimer = null;
      await _radioPlayer.pause();
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _isBuffering = false;
          _playbackLoading = false;
        });
      }
    } else {
      await _selectStation(_selected!);
    }
  }

  void _playAdjacentStation(int offset) {
    if (_stations.isEmpty || _loading) return;
    final currentIndex = _stations.indexWhere(
      (station) => station.uuid == _selected?.uuid,
    );
    final nextIndex = currentIndex < 0
        ? (offset > 0 ? 0 : _stations.length - 1)
        : (currentIndex + offset + _stations.length) % _stations.length;
    _selectStation(_stations[nextIndex]);
  }

  Future<void> _stopPlayback() async {
    _playbackRequested = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _connectionTimer?.cancel();
    _connectionTimer = null;
    await _radioPlayer.stop();
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _isBuffering = false;
        _playbackLoading = false;
      });
    }
  }

  void _changeVolume(double volume) {
    setState(() {
      _volume = volume;
      if (volume > 0) _lastNonZeroVolume = volume;
    });
    unawaited(_radioPlayer.setVolume(volume).catchError((Object _) {}));
  }

  void _toggleMute() {
    _changeVolume(_volume > 0 ? 0 : _lastNonZeroVolume);
  }

  Future<void> _initialize() async {
    try {
      final settings = await widget.store.load();
      if (!mounted) return;
      // Load favorites before notifying the app-level theme state. A theme
      // rebuild must never prevent the station collection from being restored.
      widget.favorites.replace(settings.favorites);
      setState(() {
        _limit = settings.resultLimit;
        _retryEnabled = settings.retryEnabled;
        _retryIntervalSeconds = settings.retryIntervalSeconds;
        _bufferSeconds = settings.bufferSeconds;
        _minimumGenreStationCount = settings.minimumGenreStationCount;
        _themeMode = settings.themeMode;
        _favoritesWarning = settings.favoritesWarning;
        _settingsLoaded = true;
        if (_section == 'Favorites') {
          _stations = widget.favorites.stations;
          _loading = false;
          _error = null;
        }
      });
      unawaited(
        _radioPlayer
            .setBufferSeconds(settings.bufferSeconds)
            .catchError((Object _) {}),
      );
    } catch (_) {
      // Local settings are optional; browsing remains available with defaults.
      if (!mounted) return;
      setState(() => _settingsLoaded = true);
    }
    if (mounted) _loadStations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onThemeModeChanged(_parseThemeMode(_themeMode));
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _countrySearchController.dispose();
    _taxonomySearchController.dispose();
    _playingSubscription?.cancel();
    _playbackErrorSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _currentTrackSubscription?.cancel();
    _audioParamsSubscription?.cancel();
    _audioTrackSubscription?.cancel();
    _audioBitrateSubscription?.cancel();
    _volumeSubscription?.cancel();
    _radioPlayer.dispose();
    _retryTimer?.cancel();
    _connectionTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStations() async {
    if (_section == 'Favorites') {
      if (!_settingsLoaded) {
        setState(() {
          _loading = true;
          _error = null;
        });
        return;
      }
      setState(() {
        _stations = widget.favorites.stations;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final bitrateRange = _selectedBitrateRange == null
        ? null
        : _bitrateRanges[_selectedBitrateRange!];
    try {
      final stations = await widget.client.search(
        query: _searchController.text,
        limit: _limit,
        country: _selectedCountry,
        genre: _selectedGenre,
        language: _selectedLanguage,
        codec: _selectedCodec,
        bitrateMin: bitrateRange?.min,
        bitrateMax: bitrateRange?.max,
      );
      if (!mounted) return;
      setState(() {
        _stations = stations;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not connect to Radio-Browser. Check your connection and try again.';
        _loading = false;
      });
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _loadStations);
  }

  Future<void> _openTaxonomyBrowser(String category) async {
    _navigateTo(_MiddleRoute.taxonomy(category));
    final requestGeneration = ++_taxonomyRequestGeneration;
    setState(() => _taxonomyError = null);
    _taxonomySearchController.clear();
    if (_taxonomyOptionsByCategory[category]?.isNotEmpty == true) {
      setState(() => _taxonomyLoading = false);
      return;
    }
    setState(() => _taxonomyLoading = true);
    try {
      final options = await widget.client.taxonomy(
        category,
        minimumGenreStationCount: _minimumGenreStationCount,
      );
      if (!mounted || requestGeneration != _taxonomyRequestGeneration) return;
      setState(() {
        _taxonomyOptionsByCategory[category] = options;
        _taxonomyLoading = false;
      });
    } catch (_) {
      if (!mounted || requestGeneration != _taxonomyRequestGeneration) return;
      setState(() {
        _taxonomyError = 'Could not load the list.';
        _taxonomyLoading = false;
      });
    }
  }

  void _selectTaxonomyOption(String category, RadioTaxonomyOption option) {
    _navigateTo(
      _MiddleRoute.stations(
        section: 'Explore',
        filterType: category,
        filterValue: option.name,
      ),
    );
    _loadStations();
  }

  String _taxonomyDisplayName(String category, String value) {
    if (category != 'Genres' && category != 'Languages') return value;
    return value
        .split(RegExp(r'\s+'))
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  int _compareNames(String a, String b) {
    final byLowercase = a.toLowerCase().compareTo(b.toLowerCase());
    return byLowercase != 0 ? byLowercase : a.compareTo(b);
  }

  _MiddleRoute _currentMiddleRoute() {
    if (_section == 'Settings') return const _MiddleRoute.settings();
    if (_showCountryBrowser) return const _MiddleRoute.countries();
    if (_browseTaxonomy case final category?) {
      return _MiddleRoute.taxonomy(category);
    }
    return _MiddleRoute.stations(
      section: _section,
      filterType: _activeTaxonomy,
      filterValue: _activeValue,
    );
  }

  void _navigateTo(_MiddleRoute route) {
    _middleHistory.add(_currentMiddleRoute());
    setState(() => _applyRoute(route));
  }

  void _applyRoute(_MiddleRoute route) {
    _showCountryBrowser = route.kind == _MiddleRouteKind.countries;
    _browseTaxonomy = route.kind == _MiddleRouteKind.taxonomy
        ? route.category
        : null;
    _section = route.section;
    _activeTaxonomy = route.kind == _MiddleRouteKind.stations
        ? route.filterType
        : null;
    _activeValue = route.kind == _MiddleRouteKind.stations
        ? route.filterValue
        : null;
  }

  void _goBack() {
    if (_middleHistory.isEmpty) return;
    final previous = _middleHistory.removeLast();
    setState(() => _applyRoute(previous));
    if (previous.kind == _MiddleRouteKind.stations) _loadStations();
  }

  void _clearActiveFilter() {
    _middleHistory.clear();
    setState(() {
      _activeTaxonomy = null;
      _activeValue = null;
    });
    _loadStations();
  }

  Future<void> _openCountryBrowser() async {
    _navigateTo(const _MiddleRoute.countries());
    setState(() => _countryError = null);
    _countrySearchController.clear();
    if (_countries.isNotEmpty) return;
    setState(() => _countriesLoading = true);
    try {
      final countries = await widget.client.countries();
      if (!mounted) return;
      setState(() {
        _countries = countries;
        _countriesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _countryError = 'Could not load the country list.';
        _countriesLoading = false;
      });
    }
  }

  void _selectCountry(RadioCountry country) {
    _navigateTo(
      _MiddleRoute.stations(
        section: 'Explore',
        filterType: 'Countries',
        filterValue: country.name,
      ),
    );
    _loadStations();
  }

  Future<void> _toggleFavorite(Station station) async {
    setState(() => widget.favorites.toggle(station));
    if (_section == 'Favorites') {
      setState(() => _stations = widget.favorites.stations);
    }
    try {
      await widget.store.saveFavorites(widget.favorites.stations);
    } on FileSystemException {
      // Keep the in-memory favorite even when the configuration directory is unavailable.
    }
  }

  Future<void> _setResultLimit(int value) async {
    setState(() => _limit = value);
    try {
      await _saveSettings();
    } on FileSystemException {
      // The current session still uses the selected result count.
    }
    _loadStations();
  }

  Future<void> _setMinimumGenreStationCount(int? value) async {
    if (value == null || value == _minimumGenreStationCount) return;
    setState(() {
      _minimumGenreStationCount = value;
      _taxonomyOptionsByCategory.remove('Genres');
    });
    try {
      await _saveSettings();
    } on FileSystemException {
      // Keep the selected threshold for this session.
    }
    if (_browseTaxonomy == 'Genres') _openTaxonomyBrowser('Genres');
  }

  Future<void> _saveSettings() => widget.store.saveSettings(
    resultLimit: _limit,
    retryEnabled: _retryEnabled,
    retryIntervalSeconds: _retryIntervalSeconds,
    bufferSeconds: _bufferSeconds,
    minimumGenreStationCount: _minimumGenreStationCount,
    themeMode: _themeMode,
  );

  ThemeMode _parseThemeMode(String mode) => switch (mode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> _setThemeMode(String? mode) async {
    if (mode == null) return;
    setState(() => _themeMode = mode);
    widget.onThemeModeChanged(_parseThemeMode(mode));
    try {
      await _saveSettings();
    } on FileSystemException {
      // Keep the selected theme for this session.
    }
  }

  Future<void> _setRetryEnabled(bool enabled) async {
    setState(() {
      _retryEnabled = enabled;
      if (!enabled && _retryTimer != null) {
        _playbackRequested = false;
        _retryTimer?.cancel();
        _retryTimer = null;
        if (_playbackError?.startsWith('Stream interrupted') == true) {
          _playbackError = 'Stream interrupted. Automatic retry is off.';
        }
      }
    });
    try {
      await _saveSettings();
    } on FileSystemException {
      // Keep the preference in memory for this session.
    }
  }

  Future<void> _setRetryInterval(int seconds) async {
    setState(() => _retryIntervalSeconds = seconds);
    if (_retryTimer != null && _selected != null && _playbackRequested) {
      _retryTimer!.cancel();
      final request = _stationSelectionRequest;
      _retryTimer = Timer(Duration(seconds: seconds), () {
        _retryTimer = null;
        final station = _selected;
        if (mounted &&
            station != null &&
            _playbackRequested &&
            _retryEnabled &&
            request == _stationSelectionRequest) {
          _selectStation(station);
        }
      });
      setState(
        () => _playbackError =
            'Stream interrupted. Retrying in $seconds seconds…',
      );
    }
    try {
      await _saveSettings();
    } on FileSystemException {
      // Keep the preference in memory for this session.
    }
  }

  Future<void> _setBufferSeconds(int seconds) async {
    setState(() => _bufferSeconds = seconds);
    try {
      await _radioPlayer.setBufferSeconds(seconds);
    } catch (_) {
      // The setting will be applied the next time a stream opens.
    }
    try {
      await _saveSettings();
    } on FileSystemException {
      // Keep the preference in memory for this session.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) return _compactLayout();
            return Row(
              children: [
                SizedBox(width: 250, child: _navigation()),
                VerticalDivider(width: 1, color: _dividerColor(context)),
                Expanded(child: _middlePane()),
                VerticalDivider(width: 1, color: _dividerColor(context)),
                SizedBox(width: 315, child: _player()),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _compactLayout() => Column(
    children: [
      _topBar(),
      Expanded(child: _middlePane()),
      _miniPlayer(),
    ],
  );

  Widget _navigation() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 24, 14, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _accent(context),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.graphic_eq,
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.white
                          : const Color(0xFF17200F),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'RadioTop',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              _navItem(Icons.explore_outlined, 'Explore'),
              _navItem(Icons.favorite_border, 'Favorites'),
              _navItem(Icons.settings_outlined, 'Settings'),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _navItem(IconData icon, String label) {
    final active = switch (label) {
      'Favorites' => _section == 'Favorites',
      'Settings' => _section == 'Settings',
      _ => _section == 'Explore',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _selectMainMenuItem(label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: active ? _accent(context) : _muted),
              const SizedBox(width: 11),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: active
                      ? Theme.of(context).colorScheme.onSecondaryContainer
                      : _muted,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectMainMenuItem(String label) {
    _middleHistory.clear();
    _browseListGeneration++;
    switch (label) {
      case 'Favorites':
        setState(
          () => _applyRoute(const _MiddleRoute.stations(section: 'Favorites')),
        );
        _loadStations();
        break;
      case 'Settings':
        setState(() => _applyRoute(const _MiddleRoute.settings()));
        break;
      default:
        setState(() => _applyRoute(const _MiddleRoute.stations()));
        _loadStations();
    }
  }

  Widget _middlePane() {
    if (_section == 'Settings') return _settingsPane();
    return _results();
  }

  Future<void> _chooseExploreFilter(String type) async {
    try {
      if (type == 'Country' && _countries.isEmpty) {
        final values = await widget.client.countries();
        if (!mounted) return;
        setState(() => _countries = values);
      } else if (type != 'Country' &&
          _taxonomyOptionsByCategory[_filterCategory(type)] == null) {
        final category = _filterCategory(type);
        final values = await widget.client.taxonomy(
          category,
          minimumGenreStationCount: _minimumGenreStationCount,
        );
        if (!mounted) return;
        setState(() => _taxonomyOptionsByCategory[category] = values);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load $type filters.')),
        );
      }
      return;
    }
    if (!mounted) return;
    final controller = TextEditingController();
    final current = switch (type) {
      'Country' => _selectedCountry,
      'Genre' => _selectedGenre,
      'Language' => _selectedLanguage,
      _ => _selectedCodec,
    };
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refreshDialog) {
          final query = controller.text.trim().toLowerCase();
          final values = type == 'Country'
              ? _countries
                    .where((value) => value.name.toLowerCase().contains(query))
                    .toList()
              : (_taxonomyOptionsByCategory[_filterCategory(type)] ??
                        const <RadioTaxonomyOption>[])
                    .where((value) => value.name.toLowerCase().contains(query))
                    .toList();
          return AlertDialog(
            title: Text('Filter by $type'),
            content: SizedBox(
              width: 420,
              height: 440,
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    onChanged: (_) => refreshDialog(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search ${type.toLowerCase()}…',
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        ListTile(
                          title: const Text('All'),
                          trailing: current == null
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.pop(dialogContext, ''),
                        ),
                        ...values.map((value) {
                          final name = value is RadioCountry
                              ? value.name
                              : (value as RadioTaxonomyOption).name;
                          final count = value is RadioCountry
                              ? value.stationCount
                              : (value as RadioTaxonomyOption).stationCount;
                          return ListTile(
                            dense: true,
                            leading: value is RadioCountry
                                ? SizedBox(
                                    width: 30,
                                    child: Center(
                                      child: value.flag == null
                                          ? null
                                          : Text(
                                              value.flag!,
                                              style: const TextStyle(
                                                fontSize: 22,
                                              ),
                                            ),
                                    ),
                                  )
                                : null,
                            title: Text(
                              _taxonomyDisplayName(
                                type == 'Country' ? '' : _filterCategory(type),
                                name,
                              ),
                            ),
                            subtitle: Text('$count stations'),
                            trailing: current == name
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () => Navigator.pop(dialogContext, name),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() {
      final value = result.isEmpty ? null : result;
      switch (type) {
        case 'Country':
          _selectedCountry = value;
        case 'Genre':
          _selectedGenre = value;
        case 'Language':
          _selectedLanguage = value;
        default:
          _selectedCodec = value;
      }
    });
    _loadStations();
  }

  String _filterCategory(String type) => switch (type) {
    'Genre' => 'Genres',
    'Language' => 'Languages',
    _ => 'Codecs',
  };

  Future<void> _chooseBitrateFilter() async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Filter by bitrate'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('All bitrates'),
                trailing: _selectedBitrateRange == null
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(dialogContext, ''),
              ),
              ..._bitrateRanges.keys.map(
                (range) => ListTile(
                  title: Text(range),
                  trailing: _selectedBitrateRange == range
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(dialogContext, range),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _selectedBitrateRange = result.isEmpty ? null : result);
    _loadStations();
  }

  Widget _settingsPane() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 27, 28, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                letterSpacing: -.7,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Playback and connection preferences',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
      Divider(height: 1, color: _dividerColor(context)),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const _SmallLabel('APPEARANCE'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: DropdownButtonFormField<String>(
                value: _themeMode,
                dropdownColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHigh,
                decoration: const InputDecoration(
                  labelText: 'Theme',
                  border: InputBorder.none,
                ),
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('System')),
                  DropdownMenuItem(value: 'light', child: Text('Light')),
                  DropdownMenuItem(value: 'dark', child: Text('Dark')),
                ],
                onChanged: _setThemeMode,
              ),
            ),
            const SizedBox(height: 30),
            const _SmallLabel('CATALOG'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: DropdownButtonFormField<int>(
                value: _minimumGenreStationCount,
                dropdownColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHigh,
                decoration: const InputDecoration(
                  labelText: 'Only show genres with at least X stations',
                  border: InputBorder.none,
                ),
                items: const [1, 2, 5, 10, 25, 50, 100]
                    .map(
                      (count) => DropdownMenuItem(
                        value: count,
                        child: Text('$count stations'),
                      ),
                    )
                    .toList(),
                onChanged: _setMinimumGenreStationCount,
              ),
            ),
            const SizedBox(height: 30),
            const _SmallLabel('STREAM RECOVERY'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _retryEnabled,
                onChanged: _setRetryEnabled,
                activeThumbColor: _accent(context),
                title: const Text(
                  'Retry interrupted streams',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Keep the station in play mode and reconnect automatically.',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Opacity(
              opacity: _retryEnabled ? 1 : .45,
              child: IgnorePointer(
                ignoring: !_retryEnabled,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Retry interval',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Time between connection attempts',
                              style: TextStyle(color: _muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      DropdownButton<int>(
                        value: _retryIntervalSeconds,
                        dropdownColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHigh,
                        underline: const SizedBox.shrink(),
                        items: const [1, 3, 5, 10, 15, 30]
                            .map(
                              (seconds) => DropdownMenuItem(
                                value: seconds,
                                child: Text('$seconds s'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) _setRetryInterval(value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
            const _SmallLabel('AUDIO BUFFER'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Buffer duration',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '$_bufferSeconds seconds',
                        style: TextStyle(color: _accent(context), fontSize: 12),
                      ),
                    ],
                  ),
                  Slider(
                    value: _bufferSeconds.toDouble(),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    label: '$_bufferSeconds s',
                    activeColor: _accent(context),
                    onChanged: (value) =>
                        setState(() => _bufferSeconds = value.round()),
                    onChangeEnd: (value) => _setBufferSeconds(value.round()),
                  ),
                  const Text(
                    'More buffering can help unstable connections, but adds delay before playback and after dropouts.',
                    style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 7),
    child: Row(
      children: [
        Icon(Icons.graphic_eq, color: _accent(context)),
        const SizedBox(width: 8),
        const Text('RadioTop', style: TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
        IconButton(
          tooltip: 'Settings',
          onPressed: () {
            _middleHistory.clear();
            setState(() => _applyRoute(const _MiddleRoute.settings()));
          },
          icon: Icon(Icons.settings_outlined, color: _accent(context)),
        ),
        IconButton(
          onPressed: () {
            final section = _section == 'Favorites' ? 'Explore' : 'Favorites';
            _middleHistory.clear();
            setState(
              () => _applyRoute(_MiddleRoute.stations(section: section)),
            );
            _loadStations();
          },
          icon: Icon(
            _section == 'Favorites' ? Icons.favorite : Icons.favorite_border,
            color: _accent(context),
          ),
        ),
      ],
    ),
  );

  Widget _countryBrowser() {
    final query = _countrySearchController.text.trim().toLowerCase();
    final countries =
        _countries
            .where((country) => country.name.toLowerCase().contains(query))
            .toList()
          ..sort((a, b) => _compareNames(a.name, b.name));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Countries',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.7,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 1, bottom: 16),
                child: Text(
                  _countries.isEmpty
                      ? 'Browse stations by country'
                      : '${_countries.length} countries in the catalog',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ),
              TextField(
                controller: _countrySearchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Filter countries…',
                  hintStyle: const TextStyle(color: _muted, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 19, color: _muted),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: _dividerColor(context)),
        Expanded(child: _countryList(countries)),
      ],
    );
  }

  Widget _taxonomyBrowser(String category) {
    final query = _taxonomySearchController.text.trim().toLowerCase();
    final options =
        (_taxonomyOptionsByCategory[category] ?? const <RadioTaxonomyOption>[])
            .where((option) => option.name.toLowerCase().contains(query))
            .toList()
          ..sort((a, b) => _compareNames(a.name, b.name));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    category,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.7,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 1, bottom: 16),
                child: Text(
                  options.isEmpty
                      ? 'Browse stations by $category'
                      : '${options.length} options in the catalog',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ),
              TextField(
                controller: _taxonomySearchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Filter ${category.toLowerCase()}…',
                  hintStyle: const TextStyle(color: _muted, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 19, color: _muted),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: _dividerColor(context)),
        Expanded(child: _taxonomyList(category, options)),
      ],
    );
  }

  Widget _taxonomyList(String category, List<RadioTaxonomyOption> options) {
    if (_taxonomyLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: _accent(context),
          strokeWidth: 2,
        ),
      );
    }
    if (_taxonomyError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: _muted, size: 30),
            const SizedBox(height: 10),
            Text(_taxonomyError!, style: const TextStyle(color: _muted)),
            TextButton(
              onPressed: () => _openTaxonomyBrowser(category),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (options.isEmpty) {
      return Center(
        child: Text(
          'No results match your search.',
          style: TextStyle(color: _muted),
        ),
      );
    }
    return ListView.separated(
      key: PageStorageKey<String>(
        'taxonomy-list-$_browseListGeneration-$category',
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      itemCount: options.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: _dividerColor(context)),
      itemBuilder: (context, index) {
        final option = options[index];
        return InkWell(
          onTap: () => _selectTaxonomyOption(category, option),
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _taxonomyDisplayName(category, option.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${option.stationCount} stations',
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.chevron_right, size: 18, color: _muted),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _countryList(List<RadioCountry> countries) {
    if (_countriesLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: _accent(context),
          strokeWidth: 2,
        ),
      );
    }
    if (_countryError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: _muted, size: 30),
            const SizedBox(height: 10),
            Text(_countryError!, style: const TextStyle(color: _muted)),
            TextButton(
              onPressed: _openCountryBrowser,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (countries.isEmpty) {
      return const Center(
        child: Text(
          'No countries match your search.',
          style: TextStyle(color: _muted),
        ),
      );
    }
    return ListView.separated(
      key: PageStorageKey<String>('countries-list-$_browseListGeneration'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      itemCount: countries.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: _dividerColor(context)),
      itemBuilder: (context, index) {
        final country = countries[index];
        return InkWell(
          onTap: () => _selectCountry(country),
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Center(
                    child: country.flag == null
                        ? const Icon(
                            Icons.flag_outlined,
                            color: _muted,
                            size: 23,
                          )
                        : Text(
                            country.flag!,
                            style: const TextStyle(fontSize: 24),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    country.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${country.stationCount} stations',
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.chevron_right, size: 18, color: _muted),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _results() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_middleHistory.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: IconButton(
                      tooltip: 'Back',
                      onPressed: _goBack,
                      icon: const Icon(Icons.arrow_back, size: 20),
                    ),
                  ),
                Expanded(
                  child: Text(
                    _section == 'Favorites'
                        ? 'Your favorites'
                        : _activeValue == null
                        ? 'Explore stations'
                        : _taxonomyDisplayName(
                            _activeTaxonomy ?? '',
                            _activeValue!,
                          ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.7,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _section == 'Favorites'
                  ? 'Your saved stations · ${_stations.length}'
                  : _activeTaxonomy != null
                  ? 'Stations · ${_taxonomyDisplayName(_activeTaxonomy!, _activeValue!)}'
                  : 'Find your next station',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _searchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search stations…',
                      hintStyle: const TextStyle(color: _muted, fontSize: 13),
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 19,
                        color: _muted,
                      ),
                      filled: true,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHigh,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _limitPicker(),
              ],
            ),
            if (_section != 'Favorites') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _filterButton('Country', _selectedCountry),
                  _filterButton('Genre', _selectedGenre),
                  _filterButton('Language', _selectedLanguage),
                  _filterButton('Codec', _selectedCodec),
                  _filterButton('Bitrate', _selectedBitrateRange),
                ],
              ),
            ],
            const SizedBox(height: 15),
            Row(
              children: [
                const Expanded(child: _SmallLabel('STATION')),
                SizedBox(
                  width: 68,
                  child: Text(
                    'COUNTRY',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 9,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                SizedBox(
                  width: 104,
                  child: Text(
                    'FORMAT',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 9,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      Divider(height: 1, color: _dividerColor(context)),
      Expanded(child: _bodyResults()),
    ],
  );

  Widget _filterButton(String label, String? value) => OutlinedButton.icon(
    onPressed: () => label == 'Bitrate'
        ? _chooseBitrateFilter()
        : _chooseExploreFilter(label),
    icon: Icon(Icons.keyboard_arrow_down, size: 16, color: _accent(context)),
    label: Text(
      value == null
          ? label
          : _taxonomyDisplayName(
              label == 'Genre'
                  ? 'Genres'
                  : label == 'Language'
                  ? 'Languages'
                  : '',
              value,
            ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    style: OutlinedButton.styleFrom(
      foregroundColor: value == null ? _muted : _accent(context),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      visualDensity: VisualDensity.compact,
    ),
  );

  Widget _limitPicker() => PopupMenuButton<int>(
    initialValue: _limit,
    onSelected: _setResultLimit,
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    itemBuilder: (_) => [
      25,
      50,
      100,
      200,
    ].map((n) => PopupMenuItem(value: n, child: Text('$n results'))).toList(),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text('$_limit', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 5),
          const Icon(Icons.keyboard_arrow_down, size: 16, color: _muted),
        ],
      ),
    ),
  );

  Widget _bodyResults() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: _accent(context),
          strokeWidth: 2,
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: _muted, size: 30),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadStations, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_stations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _section == 'Favorites' && _favoritesWarning != null
                ? _favoritesWarning!
                : 'No stations match your search.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 5),
      itemCount: _stations.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: _dividerColor(context)),
      itemBuilder: (context, index) => _stationRow(_stations[index]),
    );
  }

  Widget _stationRow(Station station) {
    final active = _selected?.uuid == station.uuid;
    final favorite = widget.favorites.contains(station);
    return InkWell(
      onTap: () => _selectStation(station),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        color: active
            ? Theme.of(context).colorScheme.secondaryContainer
            : Colors.transparent,
        child: Row(
          children: [
            _favicon(station),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    station.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    station.tags.isEmpty ? station.codec : station.tags,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: _muted),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 68,
              child: Text(
                station.country.isEmpty ? '—' : station.country,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
            ),
            SizedBox(
              width: 104,
              child: Text(
                station.codec.isEmpty
                    ? '—'
                    : '${station.codec}${station.bitrate > 0 ? ' · ${station.bitrate} kbps' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
            ),
            IconButton(
              tooltip: favorite ? 'Remove favorite' : 'Add to favorites',
              onPressed: () => _toggleFavorite(station),
              icon: Icon(
                favorite ? Icons.favorite : Icons.favorite_border,
                size: 17,
                color: favorite ? _accent(context) : _muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _favicon(Station station) => ClipRRect(
    borderRadius: BorderRadius.circular(9),
    child: Container(
      width: 38,
      height: 38,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: station.favicon.isEmpty
          ? const Icon(Icons.radio, color: _muted, size: 18)
          : Image.network(
              station.favicon,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.radio, color: _muted, size: 18),
            ),
    ),
  );

  Widget _transportButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    bool active = false,
    bool loading = false,
  }) => SizedBox.square(
    dimension: 48,
    child: IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: active
            ? _accent(context)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: active
            ? (Theme.of(context).brightness == Brightness.light
                  ? Colors.white
                  : const Color(0xFF151915))
            : Theme.of(context).colorScheme.onSurface,
      ),
      icon: loading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
    ),
  );

  Widget _player() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 25, 20, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.graphic_eq, color: _accent(context), size: 17),
            const SizedBox(width: 8),
            const Text(
              'PLAYER',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                color: _muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (_isBuffering || (_playbackRequested && !_isPlaying))
                    ? const Color(0xFFFFC66D)
                    : _isPlaying
                    ? _accent(context)
                    : const Color(0xFF404642),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Center(child: _artwork(_selected, 184)),
        const SizedBox(height: 23),
        Text(
          _selected?.name ?? 'Choose a station',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          _selected == null
              ? 'Your radio companion'
              : [_selected!.country, _selected!.tags]
                    .where((s) => s.isNotEmpty)
                    .join(' · ')
                    .ifEmpty('Live information unavailable'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: _muted),
        ),
        if (_currentTrack != null) ...[
          const SizedBox(height: 8),
          Text(
            _currentTrack!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: _accent(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (_playbackError != null) ...[
          const SizedBox(height: 8),
          Text(
            _playbackError!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11),
          ),
        ],
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _transportButton(
              tooltip: 'Previous station',
              icon: Icons.skip_previous_rounded,
              onPressed: _stations.isEmpty || _loading
                  ? null
                  : () => _playAdjacentStation(-1),
            ),
            const SizedBox(width: 8),
            _transportButton(
              tooltip: _playbackRequested ? 'Pause playback' : 'Play station',
              icon: _playbackRequested
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              onPressed: _selected == null ? null : _togglePlayback,
              active: _isPlaying && !_isBuffering,
              loading: _isBuffering || (_playbackRequested && !_isPlaying),
            ),
            const SizedBox(width: 8),
            _transportButton(
              tooltip: 'Stop playback',
              icon: Icons.stop_rounded,
              onPressed: _selected == null ? null : _stopPlayback,
              active: _selected != null && (!_isPlaying || _isBuffering),
            ),
            const SizedBox(width: 8),
            _transportButton(
              tooltip: 'Next station',
              icon: Icons.skip_next_rounded,
              onPressed: _stations.isEmpty || _loading
                  ? null
                  : () => _playAdjacentStation(1),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              tooltip: _volume > 0 ? 'Mute' : 'Unmute',
              onPressed: _toggleMute,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _volume == 0
                    ? Icons.volume_off_rounded
                    : _volume < 50
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
                color: _volume > 0 ? _accent(context) : _muted,
              ),
            ),
            Expanded(
              child: Slider(
                value: _volume.clamp(0, 100).toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                activeColor: _accent(context),
                onChanged: _changeVolume,
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '${_volume.round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 10, color: _muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _detail('Country', _selected?.country),
        _detail('Language', _selected?.language),
        _detail('Codec', _audioTrack?.codec ?? _selected?.codec),
        _detail(
          'Bitrate',
          _audioBitrate != null && _audioBitrate! > 0
              ? '${(_audioBitrate! / 1000).round()} kbps · decoder'
              : (_selected?.bitrate ?? 0) > 0
              ? '${_selected!.bitrate} kbps · catalog'
              : null,
        ),
        _detail('Decoder format', _audioParams?.format),
        _detail(
          'Sample rate',
          (_audioParams?.sampleRate ?? 0) > 0
              ? '${((_audioParams!.sampleRate!) / 1000).toStringAsFixed(_audioParams!.sampleRate! % 1000 == 0 ? 0 : 1)} kHz · decoder'
              : null,
        ),
        _detail(
          'Channels',
          _audioParams?.hrChannels ??
              _audioParams?.channels ??
              ((_audioParams?.channelCount ?? 0) > 0
                  ? '${_audioParams!.channelCount} channels'
                  : null),
        ),
        _detail('Current track', _currentTrack),
        const Spacer(),
      ],
    ),
  );

  Widget _miniPlayer() => Container(
    height: 66,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(top: BorderSide(color: _dividerColor(context))),
    ),
    child: Row(
      children: [
        _artwork(_selected, 40),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _selected?.name ?? 'No station selected',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        IconButton(
          tooltip: _isPlaying ? 'Pause' : 'Play',
          onPressed: _selected == null ? null : _togglePlayback,
          icon: Icon(
            _playbackRequested ? Icons.pause_circle : Icons.play_circle_outline,
            color: _playbackRequested ? _accent(context) : _muted,
          ),
        ),
      ],
    ),
  );

  Widget _artwork(Station? station, double size) => ClipRRect(
    borderRadius: BorderRadius.circular(size > 50 ? 16 : 8),
    child: Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF253324), Color(0xFF171B18)],
        ),
      ),
      child: station?.favicon.isNotEmpty == true
          ? Image.network(
              station!.favicon,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _artGlyph(size),
            )
          : _artGlyph(size),
    ),
  );

  Widget _artGlyph(double size) => Center(
    child: Icon(
      Icons.radio_rounded,
      color: _accent(context).withValues(alpha: .7),
      size: size * .38,
    ),
  );

  Widget _detail(String label, String? value) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Text(
            value == null || value.isEmpty ? 'Not reported' : value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: value == null || value.isEmpty
                  ? const Color(0xFF626A64)
                  : const Color(0xFFDCE1DC),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SmallLabel extends StatelessWidget {
  const _SmallLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.25,
      color: _muted,
    ),
  );
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
