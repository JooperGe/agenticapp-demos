import 'package:flutter/material.dart';

import '../../core/balance.dart';
import '../../core/theme.dart';
import '../../data/models/journey.dart';
import '../../data/models/planet.dart';
import '../../state/game_controller.dart';
import '../exploration/exploration_page.dart';
import '../game_scope.dart';
import '../shell/shell_scope.dart';
import '../widgets/common.dart';
import '../widgets/planet_disc.dart';

/// Page 2 — Planet Details. A translucent sheet over the map that adapts its
/// primary action to the planet's state (travel / view voyage / explore).
class PlanetDetailsSheet extends StatelessWidget {
  const PlanetDetailsSheet({super.key, required this.planetId});

  final String planetId;

  @override
  Widget build(BuildContext context) {
    final c = GameScope.of(context);
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final planet = c.planetById(planetId);
        if (planet == null) return const SizedBox.shrink();
        final state = c.stateOf(planetId);
        final journey = c.activeJourney;
        final atPlanet = c.currentPlanetId == planetId;
        final travelingHere = journey != null &&
            journey.destinationPlanetId == planetId &&
            journey.status == JourneyStatus.inProgress;

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: StarColors.deepNavy,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                border: Border(
                  top: BorderSide(color: StarColors.panelBorder),
                ),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
                  const SizedBox(height: 18),
                  _Header(planet: planet, state: state),
                  const SizedBox(height: 20),
                  _StatsGrid(controller: c, planet: planet),
                  const SizedBox(height: 18),
                  _IntelCard(planet: planet, state: state),
                  const SizedBox(height: 22),
                  _PrimaryAction(
                    controller: c,
                    planet: planet,
                    state: state,
                    atPlanet: atPlanet,
                    travelingHere: travelingHere,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.planet, required this.state});
  final Planet planet;
  final DiscoveryState state;

  @override
  Widget build(BuildContext context) {
    final known = state != DiscoveryState.undiscovered;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PlanetDisc(planet: planet, size: 76),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                known ? planet.name : '未知星球',
                style: const TextStyle(
                  color: StarColors.offWhite,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                planet.designation,
                style: const TextStyle(
                  color: StarColors.faint,
                  fontSize: 12,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  _Tag(
                    icon: StarLabels.planetTypeIcon(planet.type),
                    label: StarLabels.planetType(planet.type),
                    color: StarLabels.planetTypeColor(planet.type),
                  ),
                  const SizedBox(width: 8),
                  _Tag(
                    icon: Icons.radar_rounded,
                    label: StarLabels.discoveryState(state),
                    color: StarColors.cyan,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.controller, required this.planet});
  final GameController controller;
  final Planet planet;

  @override
  Widget build(BuildContext context) {
    final atPlanet = controller.currentPlanetId == planet.id;
    final distance = controller.distanceTo(planet);
    final cost = controller.energyCostTo(planet);
    final duration = controller.travelDurationTo(planet);
    return StarPanel(
      child: Row(
        children: <Widget>[
          _Stat(
            icon: Icons.straighten_rounded,
            label: '距离',
            value: atPlanet ? '当前位置' : '${distance.round()} ly',
          ),
          _divider(),
          _Stat(
            icon: Icons.schedule_rounded,
            label: '预计航行',
            value: atPlanet ? '—' : StarLabels.duration(duration),
          ),
          _divider(),
          _Stat(
            icon: Icons.bolt_rounded,
            label: '所需能量',
            value: atPlanet ? '—' : '$cost EN',
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 34,
        color: StarColors.panelBorder,
        margin: const EdgeInsets.symmetric(horizontal: 4),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Icon(icon, color: StarColors.cyanDim, size: 18),
          const SizedBox(height: 6),
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: StarColors.offWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: StarColors.faint, fontSize: 10)),
        ],
      ),
    );
  }
}

class _IntelCard extends StatelessWidget {
  const _IntelCard({required this.planet, required this.state});
  final Planet planet;
  final DiscoveryState state;

  @override
  Widget build(BuildContext context) {
    final known = state != DiscoveryState.undiscovered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text('已知情报',
            style: TextStyle(
                color: StarColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        Text(
          known ? planet.description : '尚未抵达。远程扫描只能辨认出它的轮廓，详情需要亲自前往确认。',
          style: const TextStyle(
              color: StarColors.offWhite, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 10),
        Text(
          planet.intel,
          style: const TextStyle(
              color: StarColors.muted, fontSize: 12.5, height: 1.5),
        ),
        if (known && state != DiscoveryState.explored) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            '探索可获得：探索记录 · 收藏图像 · +${Balance.explorationReward} EN',
            style: const TextStyle(
                color: StarColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.controller,
    required this.planet,
    required this.state,
    required this.atPlanet,
    required this.travelingHere,
  });

  final GameController controller;
  final Planet planet;
  final DiscoveryState state;
  final bool atPlanet;
  final bool travelingHere;

  @override
  Widget build(BuildContext context) {
    // 1) Travelling toward this planet → jump to the journey view.
    if (travelingHere) {
      return _Button(
        label: '查看航行',
        icon: Icons.visibility_rounded,
        onPressed: () {
          ShellScope.go(context, 1);
          Navigator.of(context).pop();
        },
      );
    }

    // 2) Standing on this planet → explore (if it has content).
    if (atPlanet) {
      if (planet.pointsOfInterest.isEmpty) {
        return const _Button(label: '当前停泊位置', icon: Icons.anchor_rounded);
      }
      final explored = state == DiscoveryState.explored;
      return _Button(
        label: explored ? '再次探索' : '开始探索',
        icon: Icons.travel_explore_rounded,
        color: StarColors.gold,
        onPressed: () {
          // Capture the navigator before popping so the push targets a valid
          // navigator even as the sheet route is being removed.
          final navigator = Navigator.of(context);
          navigator.pop();
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => GameScope(
                controller: controller,
                child: ExplorationPage(planetId: planet.id),
              ),
            ),
          );
        },
      );
    }

    // 3) Elsewhere, already travelling → cannot launch another voyage.
    if (controller.isTraveling) {
      return const _Button(
        label: '航行进行中，无法出发',
        icon: Icons.block_rounded,
      );
    }

    // 4) Launch a new voyage.
    final cost = controller.energyCostTo(planet);
    final canAfford = controller.energy >= cost;
    if (!canAfford) {
      return Column(
        children: <Widget>[
          _Button(
            label: '能量不足（需 $cost EN · 现有 ${controller.energy} EN）',
            icon: Icons.bolt_rounded,
          ),
          const SizedBox(height: 10),
          _Button(
            label: '前往训练补充能量',
            icon: Icons.favorite_rounded,
            color: StarColors.flora,
            filled: false,
            onPressed: () {
              ShellScope.go(context, 3);
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    }
    return _Button(
      label: '开始航行 · $cost EN',
      icon: Icons.rocket_launch_rounded,
      color: StarColors.cyan,
      onPressed: () async {
        final result = await controller.launchJourney(planet);
        if (!context.mounted) return;
        if (result == LaunchResult.success) {
          ShellScope.go(context, 1);
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_messageFor(result))),
          );
        }
      },
    );
  }

  String _messageFor(LaunchResult r) {
    switch (r) {
      case LaunchResult.insufficientEnergy:
        return '能量不足，无法出发';
      case LaunchResult.alreadyTraveling:
        return '已有航行进行中';
      case LaunchResult.alreadyHere:
        return '已经在这颗星球了';
      case LaunchResult.noSelection:
        return '请先选择目的地';
      case LaunchResult.success:
        return '出发！';
    }
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.icon,
    this.onPressed,
    this.color = StarColors.cyan,
    this.filled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final bg = disabled
        ? StarColors.panelLight
        : (filled ? color : Colors.transparent);
    final fg = disabled
        ? StarColors.faint
        : (filled ? StarColors.abyss : color);
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: filled
                  ? null
                  : Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: fg, size: 19),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                        color: fg,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
