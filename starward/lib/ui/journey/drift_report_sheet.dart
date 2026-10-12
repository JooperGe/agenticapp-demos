import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/drift_report.dart';
import '../../state/game_controller.dart';
import '../widgets/common.dart';

/// Shows a drift report. The caller marks it read; the sheet only displays it.
Future<void> showDriftReportSheet(
  BuildContext context, {
  required GameController controller,
  required DriftReport report,
}) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DriftReportSheet(controller: controller, report: report),
    );

/// "2 天 3 小时" / "5 小时 12 分" / "40 分 9 秒" — whichever unit reads best.
String _duration(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} 天 ${d.inHours % 24} 小时';
  if (d.inHours >= 1) return '${d.inHours} 小时 ${d.inMinutes % 60} 分';
  return '${d.inMinutes} 分 ${d.inSeconds % 60} 秒';
}

class _DriftReportSheet extends StatelessWidget {
  const _DriftReportSheet({required this.controller, required this.report});

  final GameController controller;
  final DriftReport report;

  bool get _isFuelOut => report.kind == DriftReportKind.fuelOut;

  String get _headline => _isFuelOut
      ? '燃料烧尽前飞了 ${report.distanceLy.toStringAsFixed(1)} ly，'
          '用时 ${_duration(report.elapsed)}。'
      : '滑行了 ${_duration(report.elapsed)}，'
          '共 ${report.distanceLy.toStringAsFixed(1)} ly。';

  String get _whereabouts {
    final p = report.toPos;
    final coord = 'X ${p.x.toStringAsFixed(1)}  Y ${p.y.toStringAsFixed(1)}  '
        'Z ${p.z.toStringAsFixed(1)} ly';
    if (_isFuelOut) {
      return controller.isCoasting
          ? '现在位于 $coord，正以巡航速度继续滑行。'
          : '现在停在 $coord，漂浮于深空。';
    }
    return report.hitBoundary
        ? '现在位于 $coord，已贴着宇宙边界滑行。'
        : '现在位于 $coord。';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: StarPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    _isFuelOut
                        ? Icons.bolt_rounded
                        : Icons.explore_rounded,
                    color: StarColors.cyan,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _isFuelOut ? '燃料耗尽' : '滑行播报',
                    style: const TextStyle(
                      color: StarColors.offWhite,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _headline,
                style: const TextStyle(
                  color: StarColors.offWhite,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _whereabouts,
                style: const TextStyle(
                  color: StarColors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              if (report.passedCount > 0) ...<Widget>[
                Text(
                  '途经 ${report.passedCount} 个恒星系',
                  style: const TextStyle(
                    color: StarColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                for (final s in report.nearest)
                  _PassedRow(
                    name: controller.starLabelFor(s.hygId),
                    distanceLy: s.distanceLy,
                  ),
                if (report.passedCount > report.nearest.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '……以及其他 ${report.passedCount - report.nearest.length} 个',
                      style: const TextStyle(
                        color: StarColors.faint,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ] else
                const Text(
                  '这一段是空旷的星际空间，没有经过任何恒星系。',
                  style: TextStyle(
                    color: StarColors.faint,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              const SizedBox(height: 18),
              _DismissButton(
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PassedRow extends StatelessWidget {
  const _PassedRow({required this.name, required this.distanceLy});

  final String name;
  final double distanceLy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          const Icon(Icons.star_rounded, color: StarColors.cyanDim, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: StarColors.offWhite,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            '最近 ${distanceLy.toStringAsFixed(1)} ly',
            style: const TextStyle(color: StarColors.faint, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: StarColors.cyan,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
            child: Text(
              '知道了',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: StarColors.abyss,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
