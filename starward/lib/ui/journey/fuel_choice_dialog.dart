import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/engine.dart';
import '../../data/models/journey.dart';
import '../widgets/common.dart';

/// Asks what to do about a voyage the ship cannot currently afford.
///
/// Returns the chosen [FuelPolicy], or null if the player backed out. Only
/// [FuelPolicy.halt] and [FuelPolicy.coast] are offered when the tank has a
/// drop left after the braking burn: once the braking eats it all there is
/// nothing to burn, so giving up (or going to train) is the only honest
/// answer.
Future<FuelPolicy?> showFuelChoiceDialog(
  BuildContext context, {
  required int energy,
  required int cost,
  required int braking,
  required double distanceLy,
  required Engine engine,
}) {
  // The braking burn comes off the top, so what matters for the voyage is what
  // is left after it — not the whole balance. Both call sites gate on
  // `energy > braking`; clamping here keeps a caller that forgets from putting
  // a negative tank and a negative reach in front of the player.
  final afterBraking = math.max(0, energy - braking);
  final reach = engine.reachableLyFor(afterBraking);
  return showModalBottomSheet<FuelPolicy>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: StarPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '能量不足以飞完全程',
                style: TextStyle(
                  color: StarColors.offWhite,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                braking > 0
                    ? '你只有 $energy EN，其中 $braking EN 要先用于制动。'
                        '制动后剩 $afterBraking EN，'
                        '可以飞 ${reach.toStringAsFixed(1)} ly，'
                        '全程 ${distanceLy.toStringAsFixed(1)} ly。'
                    : '你只有 $energy EN，可以飞 ${reach.toStringAsFixed(1)} ly，'
                        '全程 ${distanceLy.toStringAsFixed(1)} ly。',
                style: const TextStyle(
                  color: StarColors.muted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              _Choice(
                label: '放弃航行',
                detail: '不出发，回星图重新选目标',
                icon: Icons.close_rounded,
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
              // The drop of fuel those policies need is the drop left *after*
              // braking — with the tank at or below the braking cost there is
              // nothing to decide.
              if (energy > braking) ...<Widget>[
                const SizedBox(height: 10),
                _Choice(
                  label: '耗尽后停下',
                  detail: '飞到燃料烧干的位置停下，漂浮于深空',
                  icon: Icons.anchor_rounded,
                  onTap: () =>
                      Navigator.of(sheetContext).pop(FuelPolicy.halt),
                ),
                const SizedBox(height: 10),
                _Choice(
                  label: '耗尽后滑行',
                  detail: '飞到燃料烧干后，以巡航速度继续滑行漫游',
                  icon: Icons.explore_rounded,
                  onTap: () =>
                      Navigator.of(sheetContext).pop(FuelPolicy.coast),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Asks what a destination-less cruise should do when the tank runs dry.
///
/// A second function rather than a flag on [showFuelChoiceDialog]: that one opens
/// 「能量不足以飞完全程」 and reports a reach against a distance, and a cruise has
/// neither — there is no whole trip to fail to afford. What survives is the
/// sheet's shape and the halt/coast pair, which is what §4.2 asks to reuse.
///
/// No `FuelPolicy.refuse`, per §4.2: refusing means "I cannot afford this trip",
/// and there is no trip. Backing out is [Navigator.pop] with null, which the
/// caller reads as "do not ignite".
Future<FuelPolicy?> showCruiseFuelChoiceDialog(
  BuildContext context, {
  required int energy,
  required int braking,
  required Engine engine,
}) {
  // The same rule as the voyage dialog: the braking burn comes off the top, so
  // what the cruise can spend is what is left after it.
  final budget = math.max(0, energy - braking);
  final reach = engine.reachableLyFor(budget);
  return showModalBottomSheet<FuelPolicy>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: StarPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                '电量耗尽时怎么办',
                style: TextStyle(
                  color: StarColors.offWhite,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '你只有 $energy EN，其中 $braking EN 是制动储备，'
                '巡航可用 $budget EN，可以飞 ${reach.toStringAsFixed(1)} ly。'
                '两条路都在这里耗尽并进入休眠，区别只在耗尽的那一刻。',
                style: const TextStyle(
                  color: StarColors.muted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              _Choice(
                label: '耗尽后停下',
                // `$braking`, never a literal: the reserve is
                // `Engine.brakingCostFor`, so a ship with a different engine
                // would be quoted a number that is not its own. Every other
                // number in this sheet interpolates for the same reason.
                detail: '电量耗尽前引擎先制动停下，保留 $braking EN 的制动储备',
                icon: Icons.anchor_rounded,
                onTap: () => Navigator.of(sheetContext).pop(FuelPolicy.halt),
              ),
              const SizedBox(height: 10),
              _Choice(
                label: '耗尽后滑行',
                detail: '电量耗尽后飞船以巡航速度继续滑行',
                icon: Icons.explore_rounded,
                onTap: () => Navigator.of(sheetContext).pop(FuelPolicy.coast),
              ),
              const SizedBox(height: 10),
              _Choice(
                label: '取消点火',
                detail: '不点火，留在原地',
                icon: Icons.close_rounded,
                onTap: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.detail,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String detail;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StarColors.panelLight,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: <Widget>[
              Icon(icon, color: StarColors.cyan, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label,
                        style: const TextStyle(
                          color: StarColors.offWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 2),
                    Text(detail,
                        style: const TextStyle(
                          color: StarColors.faint,
                          fontSize: 11,
                          height: 1.4,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
