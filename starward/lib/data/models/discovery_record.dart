/// A logged discovery — the collectible reward for exploring a planet.
class DiscoveryRecord {
  const DiscoveryRecord({
    required this.id,
    required this.planetId,
    required this.discoveryType,
    required this.title,
    required this.description,
    required this.discoveredAt,
    required this.seedColor,
  });

  final String id;
  final String planetId;

  /// Free-form category, e.g. "mineral", "lifeform", "ruin", "signal".
  final String discoveryType;
  final String title;
  final String description;
  final DateTime discoveredAt;

  /// Colour seed used to render the collectible card art procedurally.
  final int seedColor;

  factory DiscoveryRecord.fromJson(Map<String, dynamic> json) =>
      DiscoveryRecord(
        id: json['id'] as String,
        planetId: json['planetId'] as String,
        discoveryType: json['discoveryType'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        discoveredAt:
            DateTime.fromMillisecondsSinceEpoch(json['discoveredAt'] as int),
        seedColor: json['seedColor'] as int,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'planetId': planetId,
        'discoveryType': discoveryType,
        'title': title,
        'description': description,
        'discoveredAt': discoveredAt.millisecondsSinceEpoch,
        'seedColor': seedColor,
      };
}
