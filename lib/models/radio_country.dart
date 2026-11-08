import 'package:sealed_countries/sealed_countries.dart';

class RadioCountry {
  const RadioCountry({required this.name, required this.stationCount});

  final String name;
  final int stationCount;

  factory RadioCountry.fromJson(Map<String, dynamic> json) => RadioCountry(
    name: json['name']?.toString().trim() ?? '',
    stationCount: int.tryParse(json['stationcount']?.toString() ?? '') ?? 0,
  );

  String? get flag => CountryFlagLookup.forName(name);
}

class CountryFlagLookup {
  static final Map<String, String> _flagsByName = _buildNameMap();

  static String? forName(String name) => _flagsByName[_normalize(name)];

  static Map<String, String> _buildNameMap() {
    final result = <String, String>{};
    for (final country in WorldCountry.list) {
      for (final name in [
        country.name.common,
        country.name.official,
        ...country.altSpellings,
      ]) {
        result[_normalize(name)] = country.emoji;
      }
    }
    return result;
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
