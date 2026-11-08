import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/radio_browser_client.dart';
import '../data/radio_top_store.dart';
import '../models/radio_country.dart';
import '../models/station.dart';
import '../models/radio_taxonomy_option.dart';

const _lime = Color(0xFFB7F36B);
const _muted = Color(0xFF858B86);
const _line = Color(0xFF292E2B);

enum _MiddleRouteKind { stations, countries, taxonomy }

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
  });

  final RadioBrowserClient client;
  final StationFavorites favorites;
  final RadioTopStore store;

  @override
  State<RadioHomePage> createState() => _RadioHomePageState();
}

class _RadioHomePageState extends State<RadioHomePage> {
  final _searchController = TextEditingController();
  final _countrySearchController = TextEditingController();
  final _taxonomySearchController = TextEditingController();
  final Map<String, List<RadioTaxonomyOption>> _taxonomyOptionsByCategory = {};
  final List<_MiddleRoute> _middleHistory = [];
  List<Station> _stations = [];
  List<RadioCountry> _countries = [];
  Station? _selected;
  String? _activeTaxonomy;
  String? _activeValue;
  String _section = 'Explore';
  String? _error;
  bool _loading = true;
  bool _showCountryBrowser = false;
  String? _browseTaxonomy;
  bool _countriesLoading = false;
  String? _countryError;
  bool _taxonomyLoading = false;
  String? _taxonomyError;
  int _limit = 100;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final settings = await widget.store.load();
      if (!mounted) return;
      setState(() {
        _limit = settings.resultLimit;
        widget.favorites.replace(settings.favorites);
      });
    } catch (_) {
      // Local settings are optional; browsing remains available with defaults.
    }
    if (mounted) _loadStations();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _countrySearchController.dispose();
    _taxonomySearchController.dispose();
    widget.client.close();
    super.dispose();
  }

  Future<void> _loadStations() async {
    if (_section == 'Favorites') {
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
    try {
      final stations = await widget.client.search(
        query: _searchController.text,
        limit: _limit,
        filterType: _activeTaxonomy,
        filterValue: _activeValue,
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
    setState(() => _taxonomyError = null);
    _taxonomySearchController.clear();
    if (_taxonomyOptionsByCategory[category]?.isNotEmpty == true) return;
    setState(() => _taxonomyLoading = true);
    try {
      final options = await widget.client.taxonomy(category);
      if (!mounted) return;
      setState(() {
        _taxonomyOptionsByCategory[category] = options;
        _taxonomyLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
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

  _MiddleRoute _currentMiddleRoute() {
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
      await widget.store.saveSettings(resultLimit: value);
    } on FileSystemException {
      // The current session still uses the selected result count.
    }
    _loadStations();
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
                const VerticalDivider(width: 1, color: _line),
                Expanded(child: _middlePane()),
                const VerticalDivider(width: 1, color: _line),
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
                      color: _lime,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.graphic_eq,
                      color: Color(0xFF17200F),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'radiotop',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              const _SmallLabel('LIBRARY'),
              const SizedBox(height: 12),
              _navItem(Icons.explore_outlined, 'Explore'),
              _navItem(Icons.favorite_border, 'Favorites'),
              const SizedBox(height: 16),
              const Divider(color: _line),
              const SizedBox(height: 14),
              const Text(
                'Discover stations',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              const Text(
                'Filter by category',
                style: TextStyle(fontSize: 11, color: _muted),
              ),
              const SizedBox(height: 12),
              _countryCategoryButton(),
              _taxonomyCategoryButton('Genres', Icons.music_note),
              _taxonomyCategoryButton('Languages', Icons.translate),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C211E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.public, size: 17, color: _lime),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Stations from around the world',
                  style: TextStyle(fontSize: 11, color: _muted),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _navItem(IconData icon, String label) {
    final active = _section == label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          _middleHistory.clear();
          setState(() => _applyRoute(_MiddleRoute.stations(section: label)));
          _loadStations();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF242A25) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: active ? _lime : _muted),
              const SizedBox(width: 11),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: active ? Colors.white : _muted,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taxonomyCategoryButton(String title, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => _openTaxonomyBrowser(title),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 17, color: _muted),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 13))),
            const Icon(Icons.chevron_right, size: 17, color: _muted),
          ],
        ),
      ),
    ),
  );

  Widget _countryCategoryButton() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: _openCountryBrowser,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 13),
        child: Row(
          children: [
            Icon(Icons.language, size: 17, color: _muted),
            SizedBox(width: 12),
            Expanded(child: Text('Countries', style: TextStyle(fontSize: 13))),
            Icon(Icons.chevron_right, size: 17, color: _muted),
          ],
        ),
      ),
    ),
  );

  Widget _middlePane() {
    if (_showCountryBrowser) return _countryBrowser();
    final category = _browseTaxonomy;
    if (category != null) return _taxonomyBrowser(category);
    return _results();
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 7),
    child: Row(
      children: [
        const Icon(Icons.graphic_eq, color: _lime),
        const SizedBox(width: 8),
        const Text('radiotop', style: TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
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
            color: _lime,
          ),
        ),
      ],
    ),
  );

  Widget _countryBrowser() {
    final query = _countrySearchController.text.trim().toLowerCase();
    final countries = _countries
        .where((country) => country.name.toLowerCase().contains(query))
        .toList();
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
                  IconButton(
                    tooltip: 'Back to stations',
                    onPressed: _goBack,
                    icon: const Icon(Icons.arrow_back, size: 19),
                  ),
                  const SizedBox(width: 4),
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
                padding: const EdgeInsets.only(left: 52, top: 1, bottom: 16),
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
                  fillColor: const Color(0xFF191D1A),
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
        const Divider(height: 1, color: _line),
        Expanded(child: _countryList(countries)),
      ],
    );
  }

  Widget _taxonomyBrowser(String category) {
    final query = _taxonomySearchController.text.trim().toLowerCase();
    final options =
        (_taxonomyOptionsByCategory[category] ?? const <RadioTaxonomyOption>[])
            .where((option) => option.name.toLowerCase().contains(query))
            .toList();
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
                  IconButton(
                    tooltip: 'Back to stations',
                    onPressed: _goBack,
                    icon: const Icon(Icons.arrow_back, size: 19),
                  ),
                  const SizedBox(width: 4),
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
                padding: const EdgeInsets.only(left: 52, top: 1, bottom: 16),
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
                  fillColor: const Color(0xFF191D1A),
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
        const Divider(height: 1, color: _line),
        Expanded(child: _taxonomyList(category, options)),
      ],
    );
  }

  Widget _taxonomyList(String category, List<RadioTaxonomyOption> options) {
    if (_taxonomyLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _lime, strokeWidth: 2),
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
      return const Center(
        child: Text(
          'No results match your search.',
          style: TextStyle(color: _muted),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      itemCount: options.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: _line),
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
                    option.name,
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
      return const Center(
        child: CircularProgressIndicator(color: _lime, strokeWidth: 2),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      itemCount: countries.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: _line),
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
                        : _activeValue ?? 'Explore stations',
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
                  ? 'Your saved stations'
                  : _activeTaxonomy != null
                  ? 'Stations · $_activeTaxonomy'
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
                      fillColor: const Color(0xFF191D1A),
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
            if (_activeValue != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ActionChip(
                  label: Text(
                    '${_activeTaxonomy!}: $_activeValue  ×',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _clearActiveFilter,
                ),
              ),
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
      const Divider(height: 1, color: _line),
      Expanded(child: _bodyResults()),
    ],
  );

  Widget _limitPicker() => PopupMenuButton<int>(
    initialValue: _limit,
    onSelected: _setResultLimit,
    itemBuilder: (_) => [
      25,
      50,
      100,
      200,
    ].map((n) => PopupMenuItem(value: n, child: Text('$n results'))).toList(),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF191D1A),
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
      return const Center(
        child: CircularProgressIndicator(color: _lime, strokeWidth: 2),
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
      return const Center(
        child: Text(
          'No stations match your search.',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 5),
      itemCount: _stations.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: _line),
      itemBuilder: (context, index) => _stationRow(_stations[index]),
    );
  }

  Widget _stationRow(Station station) {
    final active = _selected?.uuid == station.uuid;
    final favorite = widget.favorites.contains(station);
    return InkWell(
      onTap: () => setState(() => _selected = station),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        color: active ? const Color(0xFF1C241B) : Colors.transparent,
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
                      color: active ? _lime : Colors.white,
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
                color: favorite ? _lime : _muted,
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
      color: const Color(0xFF252A27),
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

  Widget _player() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 25, 20, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.graphic_eq, color: _lime, size: 17),
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
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF404642),
              ),
            ),
          ],
        ),
        const Spacer(),
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
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Playback coming soon'),
            style: FilledButton.styleFrom(
              disabledBackgroundColor: const Color(0xFF283020),
              disabledForegroundColor: _lime,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 26),
        const Divider(color: _line),
        const SizedBox(height: 12),
        const _SmallLabel('STATION DETAILS'),
        const SizedBox(height: 14),
        _detail('Country', _selected?.country),
        _detail('Language', _selected?.language),
        _detail('Codec', _selected?.codec),
        _detail(
          'Bitrate',
          (_selected?.bitrate ?? 0) > 0 ? '${_selected!.bitrate} kbps' : null,
        ),
        _detail('Container', null),
        _detail('Sample rate', null),
        _detail('Channels', null),
        _detail('Current track', null),
        const Spacer(),
        const Center(
          child: Text(
            'Technical details appear when reported by the source.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: _muted),
          ),
        ),
      ],
    ),
  );

  Widget _miniPlayer() => Container(
    height: 66,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: const BoxDecoration(
      color: Color(0xFF181C19),
      border: Border(top: BorderSide(color: _line)),
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
        const Icon(Icons.play_circle_outline, color: _muted),
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
      color: _lime.withValues(alpha: .7),
      size: size * .38,
    ),
  );

  Widget _detail(String label, String? value) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
        ),
        Text(
          value == null || value.isEmpty ? 'Not reported' : value,
          style: TextStyle(
            fontSize: 11,
            color: value == null || value.isEmpty
                ? const Color(0xFF626A64)
                : const Color(0xFFDCE1DC),
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
