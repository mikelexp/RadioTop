class RadioTaxonomyOption {
  const RadioTaxonomyOption({required this.name, required this.stationCount});

  final String name;
  final int stationCount;

  factory RadioTaxonomyOption.fromJson(Map<String, dynamic> json) =>
      RadioTaxonomyOption(
        name: json['name']?.toString().trim() ?? '',
        stationCount: int.tryParse(json['stationcount']?.toString() ?? '') ?? 0,
      );
}
