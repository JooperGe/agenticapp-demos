import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/planet.dart';
import '../../state/game_controller.dart';
import '../game_scope.dart';
import '../widgets/common.dart';
import '../widgets/planet_disc.dart';

/// Shown when a star is tapped on the overview: the system's planets, each a
/// row you can open (to view details / launch). The overview is a star map, so
/// this is how you "look inside" a system before travelling there.
class StarSystemSheet extends StatelessWidget {
  const StarSystemSheet({
    super.key,
    required this.hygId,
    required this.onSelectPlanet,
    required this.onGoToStar,
  });

  final int hygId;
  final void Function(String planetId) onSelectPlanet;
  final void Function(int hygId) onGoToStar;

  @override
  Widget build(BuildContext context) {
    final c = GameScope.of(context);
    final name = c.universe.starLabel(hygId);
    final planets = c.universe.planetsAtStar(hygId);
    final starCost = c.energyCostToStar(hygId);
    final starDist = c.distanceToStar(hygId).round();

    return Container(
      decoration: const BoxDecoration(
        color: StarColors.deepNavy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: StarColors.panelBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: StarColors.faint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              const Icon(Icons.brightness_7_rounded,
                  color: StarColors.gold, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(name,
                        style: const TextStyle(
                            color: StarColors.offWhite,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('恒星系 · ${planets.length} 颗行星',
                        style: const TextStyle(
                            color: StarColors.muted, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Travel to the star itself (works even with no planets) — you drift
          // in beside it.
          _GoToStarButton(
            distanceLy: starDist,
            cost: starCost,
            onTap: () {
              Navigator.of(context).pop();
              onGoToStar(hygId);
            },
          ),
          const SizedBox(height: 16),
          if (planets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('该恒星周围没有探测到行星，但你仍可航行至此。',
                  style: TextStyle(color: StarColors.muted, fontSize: 13)),
            )
          else ...<Widget>[
            const Text('行星',
                style: TextStyle(
                    color: StarColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const SizedBox(height: 10),
            ...planets.map((p) => _PlanetRow(
                  controller: c,
                  planet: p,
                  onTap: () {
                    Navigator.of(context).pop();
                    onSelectPlanet(p.id);
                  },
                )),
          ],
        ],
      ),
    );
  }
}

class _GoToStarButton extends StatelessWidget {
  const _GoToStarButton({
    required this.distanceLy,
    required this.cost,
    required this.onTap,
  });

  final int distanceLy;
  final int cost;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StarColors.cyan,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.rocket_launch_rounded,
                  color: StarColors.abyss, size: 19),
              const SizedBox(width: 9),
              Text(
                '航行至该恒星系 · $distanceLy ly · $cost EN',
                style: const TextStyle(
                    color: StarColors.abyss,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanetRow extends StatelessWidget {
  const _PlanetRow({
    required this.controller,
    required this.planet,
    required this.onTap,
  });

  final GameController controller;
  final Planet planet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typeColor = StarLabels.planetTypeColor(planet.type);
    final distance = controller.distanceTo(planet).round();
    final cost = controller.energyCostTo(planet);
    final state = controller.stateOf(planet.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: StarColors.panelLight,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                PlanetDisc(planet: planet, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(planet.name,
                          style: const TextStyle(
                              color: StarColors.offWhite,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Row(
                        children: <Widget>[
                          Icon(StarLabels.planetTypeIcon(planet.type),
                              color: typeColor, size: 12),
                          const SizedBox(width: 4),
                          Text(StarLabels.planetType(planet.type),
                              style: TextStyle(color: typeColor, fontSize: 11)),
                          const SizedBox(width: 8),
                          Text('· ${StarLabels.discoveryState(state)}',
                              style: const TextStyle(
                                  color: StarColors.faint, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text('$distance ly',
                        style: const TextStyle(
                            color: StarColors.muted, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text('$cost EN',
                        style: const TextStyle(
                            color: StarColors.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded,
                    color: StarColors.faint, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
