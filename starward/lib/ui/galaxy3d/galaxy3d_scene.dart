import '../../core/vec3.dart';
import '../../data/hyg_catalog.dart';
import '../../data/models/planet.dart';
import '../../state/game_controller.dart' show kDeepSpaceId;

/// A star to draw (kept for the painter's fallback path; normally the HYG fast
/// path is used instead).
class SceneStar {
  const SceneStar({
    required this.position,
    required this.color,
    required this.magnitude,
    this.name,
    this.isSun = false,
    this.isReal = true,
  });

  final Vec3 position;
  final int color;
  final double magnitude;
  final String? name;
  final bool isSun;
  final bool isReal;
}

/// A game planet with its resolved 3D position (in world units).
class ScenePlanet {
  const ScenePlanet({required this.planet, required this.position});
  final Planet planet;
  final Vec3 position;
}

/// The renderable 3D galaxy: the full HYG star field plus the player's current
/// near-set of procedural/hero planets, each at its real 3D position scaled to
/// world units. Positions come straight from the Universe (via each planet's
/// [Planet.pos]) — the scene no longer invents them.
class Galaxy3DScene {
  Galaxy3DScene({
    required this.planets,
    required this.planetPositions,
    required this.worldScale,
    required this.hyg,
    this.extraGalaxies = const <HygStars>[],
    this.stars = const <SceneStar>[],
  });

  final List<SceneStar> stars;
  final List<ScenePlanet> planets;
  final Map<String, Vec3> planetPositions;
  final double worldScale;
  final HygStars? hyg;

  /// Extra (fictional) galaxies to render alongside the real HYG field.
  final List<HygStars> extraGalaxies;

  Vec3 positionOf(String planetId) =>
      planetPositions[planetId] ?? const Vec3(0, 0, 0);

  static Galaxy3DScene build(
    List<Planet> nearbyPlanets, {
    required HygStars hyg,
    double worldScale = 12.0,
    Vec3? deepSpaceOrigin,
    List<HygStars> extraGalaxies = const <HygStars>[],
  }) {
    final positions = <String, Vec3>{};
    final planets = <ScenePlanet>[];
    for (final p in nearbyPlanets) {
      final pos = p.pos * worldScale;
      positions[p.id] = pos;
      planets.add(ScenePlanet(planet: p, position: pos));
    }
    if (deepSpaceOrigin != null) {
      positions[kDeepSpaceId] = deepSpaceOrigin * worldScale;
    }
    return Galaxy3DScene(
      planets: planets,
      planetPositions: positions,
      worldScale: worldScale,
      hyg: hyg,
      extraGalaxies: extraGalaxies,
    );
  }
}
