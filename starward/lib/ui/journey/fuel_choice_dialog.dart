import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/engine.dart';
import '../../data/models/journey.dart';
import '../widgets/common.dart';

/// Asks what to do about a voyage the ship cannot currently afford.
///
/// Returns the chosen [FuelPolicy], or null if the player backed out. Only
/// [FuelPolicy.halt] and [FuelPolicy.coast] are offered when there is fuel in
/// the tank: an empty ship has nothing to burn, so giving up (or going to
/// train) is the only honest answer.
Future<FuelPolicy?> showFuelChoiceDialog(
  BuildContext context, {
  required int energy,
  required int cost,
  required double distanceLy,
  required Engine engine,
}) {
  final reach = engine.reachableLyFor(energy);
  return showModalBottomSheet<FuelPolicy>(
    context: context,
    backgroundColor: Colors.transparent,
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
                '你只有 $energy EN，可以飞 ${reach.toStringAsFixed(1)} ly，'
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
              if (energy > 0) ...<Widget>[
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
