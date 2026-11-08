class Station {
  const Station({
    required this.uuid,
    required this.name,
    required this.streamUrl,
    this.homepage = '',
    this.favicon = '',
    this.country = '',
    this.countryCode = '',
    this.state = '',
    this.language = '',
    this.tags = '',
    this.codec = '',
    this.bitrate = 0,
    this.votes = 0,
    this.hls = false,
  });

  final String uuid;
  final String name;
  final String streamUrl;
  final String homepage;
  final String favicon;
  final String country;
  final String countryCode;
  final String state;
  final String language;
  final String tags;
  final String codec;
  final int bitrate;
  final int votes;
  final bool hls;

  factory Station.fromJson(Map<String, dynamic> json) {
    final uuid = json['stationuuid']?.toString() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    final streamUrl =
        json['url_resolved']?.toString() ?? json['url']?.toString() ?? '';
    if (uuid.isEmpty || name.isEmpty || streamUrl.isEmpty) {
      throw const FormatException(
        'The station is missing an identity, name, or stream URL.',
      );
    }
    int number(Object? value) => int.tryParse(value?.toString() ?? '') ?? 0;
    return Station(
      uuid: uuid,
      name: name,
      streamUrl: streamUrl,
      homepage: json['homepage']?.toString() ?? '',
      favicon: json['favicon']?.toString() ?? '',
      country: json['country']?.toString() ?? '',
      countryCode: json['countrycode']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      language: json['language']?.toString() ?? '',
      tags: json['tags']?.toString() ?? '',
      codec: json['codec']?.toString() ?? '',
      bitrate: number(json['bitrate']),
      votes: number(json['votes']),
      hls: json['hls'] == true || json['hls']?.toString() == 'true',
    );
  }

  Map<String, dynamic> toJson() => {
    'stationuuid': uuid,
    'name': name,
    'url_resolved': streamUrl,
    'homepage': homepage,
    'favicon': favicon,
    'country': country,
    'countrycode': countryCode,
    'state': state,
    'language': language,
    'tags': tags,
    'codec': codec,
    'bitrate': bitrate,
    'votes': votes,
    'hls': hls,
  };
}

class StationFavorites {
  final Map<String, Station> _stations = {};

  bool contains(Station station) => _stations.containsKey(station.uuid);

  List<Station> get stations => _stations.values.toList();

  void replace(Iterable<Station> stations) {
    _stations
      ..clear()
      ..addEntries(stations.map((station) => MapEntry(station.uuid, station)));
  }

  void toggle(Station station) {
    if (_stations.containsKey(station.uuid)) {
      _stations.remove(station.uuid);
    } else {
      _stations[station.uuid] = station;
    }
  }

  List<Station> filter(Iterable<Station> stations) =>
      stations.where(contains).toList();
}
