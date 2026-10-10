import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/journey.dart';
import '../../data/models/planet.dart';

/// Shared display helpers so planet/journey vocabulary stays consistent across
/// every page.
class StarLabels {
  StarLabels._();

  static String planetType(PlanetType t) {
    switch (t) {
      case PlanetType.dead:
        return '死寂星球';
      case PlanetType.alive:
        return '生命星球';
      case PlanetType.civilization:
        return '文明星球';
    }
  }

  static Color planetTypeColor(PlanetType t) {
    switch (t) {
      case PlanetType.dead:
        return StarColors.muted;
      case PlanetType.alive:
        return StarColors.flora;
      case PlanetType.civilization:
        return StarColors.gold;
    }
  }

  static IconData planetTypeIcon(PlanetType t) {
    switch (t) {
      case PlanetType.dead:
        return Icons.terrain_rounded;
      case PlanetType.alive:
        return Icons.eco_rounded;
      case PlanetType.civilization:
        return Icons.account_balance_rounded;
    }
  }

  static String discoveryState(DiscoveryState s) {
    switch (s) {
      case DiscoveryState.undiscovered:
        return '未探索';
      case DiscoveryState.discovered:
        return '已抵达 · 待探索';
      case DiscoveryState.explored:
        return '已探索';
    }
  }

  static String journeyStatus(JourneyStatus s) {
    switch (s) {
      case JourneyStatus.inProgress:
        return '航行中';
      case JourneyStatus.arrived:
        return '已抵达';
      case JourneyStatus.completed:
        return '已完成';
    }
  }

  /// Human-friendly duration like "7 分 30 秒" / "1 时 05 分".
  static String duration(Duration d) {
    if (d.inHours >= 1) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      return '$h 时 $m 分';
    }
    if (d.inMinutes >= 1) {
      final m = d.inMinutes;
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$m 分 $s 秒';
    }
    return '${d.inSeconds} 秒';
  }
}

/// The translucent info panel used throughout the app.
class StarPanel extends StatelessWidget {
  const StarPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.color,
    this.radius = 18,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: panelDecoration(color: color, radius: radius),
      child: child,
    );
  }
}

/// A compact energy readout chip, shown at the top of most pages.
class EnergyBadge extends StatelessWidget {
  const EnergyBadge({super.key, required this.energy});

  final int energy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: panelDecoration(radius: 99),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.bolt_rounded, color: StarColors.cyan, size: 18),
          const SizedBox(width: 6),
          Text(
            '$energy',
            style: const TextStyle(
              color: StarColors.offWhite,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 3),
          const Text('EN',
              style: TextStyle(
                  color: StarColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
