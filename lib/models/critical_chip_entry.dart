class CriticalChipEntry {
  const CriticalChipEntry({required this.label, required this.value});

  final String label;
  final String value;

  Map<String, dynamic> toJson() => {
        'label': label,
        'value': value,
      };

  factory CriticalChipEntry.fromJson(Map<String, dynamic> json) {
    return CriticalChipEntry(
      label: json['label'] as String,
      value: json['value'] as String,
    );
  }
}
