import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/vec3.dart';

/// The three kinds of destinations a player can explore.
enum PlanetType { dead, alive, civilization }

/// Lifecycle of a planet from the player's perspective.
///
/// [undiscovered] planets are visible on the map but their contents are
/// unknown. [discovered] means a journey has reached it at least once but it
/// has not been explored. [explored] means its discovery has been logged.
enum DiscoveryState { undiscovered, discovered, explored }

PlanetType planetTypeFromName(String name) =>
    PlanetType.values.firstWhere((t) => t.name == name,
        orElse: () => PlanetType.dead);

/// A single clickable point of interest inside an exploration scene.
@immutable
class PointOfInterest {
  const PointOfInterest({
    required this.id,
    required this.label,
    required this.discoveryType,
    required this.discoveryTitle,
    required this.discoveryDescription,
    required this.x,
    required this.y,
  });

  final String id;
  final String label;

  /// Category of what is found here, e.g. "mineral", "lifeform", "ruin".
  final String discoveryType;

  /// Title/description recorded into the discovery log when found.
  final String discoveryTitle;
  final String discoveryDescription;

  /// Normalised position within the scene (0..1), kept resolution-independent
  /// so the same hotspot lands correctly on any screen size.
  final double x;
  final double y;

  factory PointOfInterest.fromJson(Map<String, dynamic> json) =>
      PointOfInterest(
        id: json['id'] as String,
        label: json['label'] as String,
        discoveryType: json['discoveryType'] as String,
        discoveryTitle: json['discoveryTitle'] as String,
        discoveryDescription: json['discoveryDescription'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'discoveryType': discoveryType,
        'discoveryTitle': discoveryTitle,
        'discoveryDescription': discoveryDescription,
        'x': x,
        'y': y,
      };
}

/// Static definition of a planet. Positions, names and content are fixed seed
/// data — the galaxy is never re-randomised between launches.
@immutable
class Planet {
  const Planet({
    required this.id,
    required this.name,
    required this.designation,
    required this.type,
    required this.coordinateX,
    required this.coordinateY,
    required this.seedColor,
    required this.description,
    required this.intel,
    this.pointsOfInterest = const <PointOfInterest>[],
    this.featured = false,
    this.positionLy,
  });

  final String id;
  final String name;

  /// Catalogue designation, e.g. "SW-017".
  final String designation;
  final PlanetType type;

  /// Legacy 2D galaxy-map coordinates (used only by hand-authored content for
  /// backward-compat). Distances now come from [positionLy].
  final double coordinateX;
  final double coordinateY;

  /// 32-bit ARGB seed colour driving the procedural planet disc. Keeping the
  /// colour in data guarantees a planet looks identical every time.
  final int seedColor;

  final String description;
  final String intel;

  /// Hand-authored content planets expose explorable hotspots; filler planets
  /// leave this empty and fall back to a generic scan.
  final List<PointOfInterest> pointsOfInterest;

  /// Whether this is one of the hand-designed hero planets.
  final bool featured;

  /// True 3D position in light-years (Sun at origin, Y = north celestial pole).
  /// Set for every planet the [Universe] produces; the authoritative position
  /// for distance, rendering and travel.
  final Vec3? positionLy;

  /// Resolved 3D position — [positionLy] when known, else the legacy 2D coords
  /// lifted into the X/Z plane.
  Vec3 get pos => positionLy ?? Vec3(coordinateX, 0, coordinateY);

  Planet copyWith({Vec3? positionLy}) => Planet(
        id: id,
        name: name,
        designation: designation,
        type: type,
        coordinateX: coordinateX,
        coordinateY: coordinateY,
        seedColor: seedColor,
        description: description,
        intel: intel,
        pointsOfInterest: pointsOfInterest,
        featured: featured,
        positionLy: positionLy ?? this.positionLy,
      );

  /// Euclidean distance from another map point (legacy 2D helper).
  double distanceTo(double x, double y) =>
      math.sqrt(math.pow(coordinateX - x, 2) + math.pow(coordinateY - y, 2));

  factory Planet.fromJson(Map<String, dynamic> json) => Planet(
        id: json['id'] as String,
        name: json['name'] as String,
        designation: json['designation'] as String,
        type: planetTypeFromName(json['type'] as String),
        coordinateX: (json['coordinateX'] as num).toDouble(),
        coordinateY: (json['coordinateY'] as num).toDouble(),
        seedColor: json['seedColor'] as int,
        description: json['description'] as String,
        intel: json['intel'] as String,
        featured: json['featured'] as bool? ?? false,
        pointsOfInterest: (json['pointsOfInterest'] as List<dynamic>? ??
                const <dynamic>[])
            .map((e) => PointOfInterest.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'designation': designation,
        'type': type.name,
        'coordinateX': coordinateX,
        'coordinateY': coordinateY,
        'seedColor': seedColor,
        'description': description,
        'intel': intel,
        'featured': featured,
        'pointsOfInterest':
            pointsOfInterest.map((e) => e.toJson()).toList(),
      };
}
