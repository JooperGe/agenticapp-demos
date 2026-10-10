import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/discovery_record.dart';
import '../../data/models/planet.dart';
import '../../state/game_controller.dart';
import '../game_scope.dart';
import '../shell/shell_scope.dart';
import '../widgets/common.dart';
import '../widgets/planet_disc.dart';
import '../widgets/starfield.dart';

/// Page 7 — 发现 (探索日志).
///
/// A personal exploration journal rather than a database table: discoveries
/// are grouped by the planet they came from and rendered as collectible cards,
/// each with a procedurally painted emblem derived from its seed colour. Only
/// what the player has actually logged (`c.discoveries`) is ever shown, so
/// unexplored planets reveal nothing. Observes the controller via an
/// [AnimatedBuilder] so a newly logged find appears immediately.
class DiscoveryLogPage extends StatefulWidget {
  const DiscoveryLogPage({super.key});

  @override
  State<DiscoveryLogPage> createState() => _DiscoveryLogPageState();
}

class _DiscoveryLogPageState extends State<DiscoveryLogPage> {
  @override
  Widget build(BuildContext context) {
    final c = GameScope.of(context);
    return Scaffold(
      backgroundColor: StarColors.abyss,
      body: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          return Stack(
            children: <Widget>[
              const Positioned.fill(
                child: StarfieldBackground(seed: 17, starCount: 110),
              ),
              SafeArea(
                child: Column(
                  children: <Widget>[
                    _TopBar(energy: c.energy),
                    Expanded(child: _buildBody(context, c)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, GameController c) {
    final records = c.discoveries; // already newest-first
    if (records.isEmpty) {
      return const _EmptyState();
    }

    // Group by planet while preserving the newest-first order of first
    // appearance, so the planet with the most recent find leads the journal.
    final grouped = <String, List<DiscoveryRecord>>{};
    for (final r in records) {
      grouped.putIfAbsent(r.planetId, () => <DiscoveryRecord>[]).add(r);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        _StatsHeader(controller: c),
        const SizedBox(height: 18),
        for (final entry in grouped.entries)
          if (c.planetById(entry.key) != null) ...<Widget>[
            _PlanetSection(
              planet: c.planetById(entry.key)!,
              records: entry.value,
            ),
            const SizedBox(height: 20),
          ],
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.energy});

  final int energy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          const Text(
            '发现',
            style: TextStyle(
              color: StarColors.offWhite,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          EnergyBadge(energy: energy),
        ],
      ),
    );
  }
}

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return StarPanel(
      child: Row(
        children: <Widget>[
          _Stat(
            icon: Icons.radar_rounded,
            label: '已发现星球',
            value: '${controller.discoveredCount}',
          ),
          _divider(),
          _Stat(
            icon: Icons.travel_explore_rounded,
            label: '已探索星球',
            value: '${controller.exploredCount}',
          ),
          _divider(),
          _Stat(
            icon: Icons.auto_stories_rounded,
            label: '发现条目',
            value: '${controller.discoveries.length}',
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
              style: const TextStyle(
                  color: StarColors.offWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: StarColors.faint, fontSize: 10)),
        ],
      ),
    );
  }
}

/// One planet's chapter in the journal: a header identifying the world, then
/// its discoveries as collectible cards.
class _PlanetSection extends StatelessWidget {
  const _PlanetSection({required this.planet, required this.records});

  final Planet planet;
  final List<DiscoveryRecord> records; // newest-first

  @override
  Widget build(BuildContext context) {
    // Earliest discovery = when this planet first entered the journal.
    final firstAt = records
        .map((r) => r.discoveredAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            PlanetDisc(planet: planet, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    planet.name,
                    style: const TextStyle(
                      color: StarColors.offWhite,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    planet.designation,
                    style: const TextStyle(
                      color: StarColors.faint,
                      fontSize: 11,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      _TypeTag(type: planet.type),
                      Text(
                        '首次发现 · ${_formatTime(firstAt)}',
                        style: const TextStyle(
                            color: StarColors.faint, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (final r in records) ...<Widget>[
          _RecordCard(record: r, planet: planet),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.type});

  final PlanetType type;

  @override
  Widget build(BuildContext context) {
    final color = StarLabels.planetTypeColor(type);
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
          Icon(StarLabels.planetTypeIcon(type), color: color, size: 13),
          const SizedBox(width: 5),
          Text(StarLabels.planetType(type),
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// A single collectible discovery card — like a specimen or travel photo.
/// Tapping opens a read-only detail view.
class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.planet});

  final DiscoveryRecord record;
  final Planet planet;

  @override
  Widget build(BuildContext context) {
    final accent = Color(record.seedColor);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showRecordDetail(context, record, planet),
        child: StarPanel(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _RecordEmblem(
                seedColor: record.seedColor,
                seed: record.id.hashCode,
                icon: _typeIcon(record.discoveryType),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _TypeBadge(
                      label: _typeLabel(record.discoveryType),
                      color: accent,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      record.title,
                      style: const TextStyle(
                        color: StarColors.offWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: StarColors.muted,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: StarColors.faint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// A procedurally painted emblem for a discovery, seeded by the record so it
/// looks identical every launch — the "collectible art" of each card.
class _RecordEmblem extends StatelessWidget {
  const _RecordEmblem({
    required this.seedColor,
    required this.seed,
    required this.icon,
    this.size = 58,
  });

  final int seedColor;
  final int seed;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CustomPaint(
              size: Size(size, size),
              painter: _EmblemPainter(seedColor: Color(seedColor), seed: seed),
            ),
          ),
          Icon(icon, color: StarColors.offWhite, size: size * 0.38),
        ],
      ),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  _EmblemPainter({required this.seedColor, required this.seed});

  final Color seedColor;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed);
    final rect = Offset.zero & size;

    // Two-tone gradient ground, lit from the top-left like the planet discs.
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          _lighten(seedColor, 0.28),
          seedColor,
          _darken(seedColor, 0.45),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    final center = size.center(Offset.zero);

    // Faint concentric rings — a "specimen under glass" feel.
    for (var i = 0; i < 3; i++) {
      final r = size.shortestSide * (0.22 + i * 0.17);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color =
              Colors.white.withValues(alpha: 0.1 + rng.nextDouble() * 0.08),
      );
    }

    // Scattered specks of light, like dust motes or distant particles.
    for (var i = 0; i < 6; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final d = rng.nextDouble() * size.shortestSide * 0.42;
      final p = center + Offset(math.cos(a), math.sin(a)) * d;
      canvas.drawCircle(
        p,
        1.2 + rng.nextDouble() * 1.6,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45 + rng.nextDouble() * 0.3),
      );
    }
  }

  Color _lighten(Color c, double amt) => Color.lerp(c, Colors.white, amt)!;
  Color _darken(Color c, double amt) => Color.lerp(c, Colors.black, amt)!;

  @override
  bool shouldRepaint(_EmblemPainter old) =>
      old.seedColor != seedColor || old.seed != seed;
}

/// Read-only detail view for a logged discovery. Shows only what has already
/// been recorded — nothing is revealed for planets that are not yet explored.
void _showRecordDetail(
    BuildContext context, DiscoveryRecord record, Planet planet) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (dialogContext) =>
        _RecordDetailDialog(record: record, planet: planet),
  );
}

class _RecordDetailDialog extends StatelessWidget {
  const _RecordDetailDialog({required this.record, required this.planet});

  final DiscoveryRecord record;
  final Planet planet;

  @override
  Widget build(BuildContext context) {
    final accent = Color(record.seedColor);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Container(
        decoration: panelDecoration(color: StarColors.deepNavy, radius: 22),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _RecordEmblem(
                  seedColor: record.seedColor,
                  seed: record.id.hashCode,
                  icon: _typeIcon(record.discoveryType),
                  size: 64,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _TypeBadge(
                        label: _typeLabel(record.discoveryType),
                        color: accent,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        record.title,
                        style: const TextStyle(
                          color: StarColors.offWhite,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              record.description,
              style: const TextStyle(
                color: StarColors.offWhite,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 18),
            _MetaRow(
              icon: Icons.place_rounded,
              label: '发现地点',
              value: planet.name,
            ),
            const SizedBox(height: 8),
            _MetaRow(
              icon: Icons.schedule_rounded,
              label: '发现时间',
              value: _formatTime(record.discoveredAt),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: accent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 13),
                    child: Text(
                      '收起',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: StarColors.abyss,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: StarColors.cyanDim, size: 15),
        const SizedBox(width: 8),
        Text('$label  ',
            style: const TextStyle(color: StarColors.faint, fontSize: 12)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: StarColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.auto_stories_rounded,
                color: StarColors.faint, size: 54),
            const SizedBox(height: 20),
            const Text(
              '你的探索日志还是空白的 — 出发去发现第一颗星球吧',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: StarColors.muted,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: StarColors.cyan,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  // Jump to the star map (tab 0) to begin exploring.
                  onTap: () => ShellScope.go(context, 0),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.public_rounded,
                            color: StarColors.abyss, size: 19),
                        SizedBox(width: 8),
                        Text(
                          '前往星图',
                          style: TextStyle(
                            color: StarColors.abyss,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Discovery type presentation ------------------------------------------
//
// `discoveryType` is a free-form string in the data (e.g. "mineral"). These
// helpers give known categories friendly Chinese labels and icons while
// degrading gracefully to the raw value for anything unexpected.

String _typeLabel(String type) {
  switch (type) {
    case 'mineral':
      return '矿物样本';
    case 'lifeform':
      return '生命形态';
    case 'ruin':
      return '文明遗迹';
    case 'signal':
      return '异常信号';
    case 'phenomenon':
      return '天象奇观';
    case 'artifact':
      return '神秘造物';
    default:
      return type;
  }
}

IconData _typeIcon(String type) {
  switch (type) {
    case 'mineral':
      return Icons.diamond_rounded;
    case 'lifeform':
      return Icons.eco_rounded;
    case 'ruin':
      return Icons.account_balance_rounded;
    case 'signal':
      return Icons.sensors_rounded;
    case 'phenomenon':
      return Icons.auto_awesome_rounded;
    case 'artifact':
      return Icons.diamond_outlined;
    default:
      return Icons.travel_explore_rounded;
  }
}

/// Absolute timestamp like "2026.10.10 14:05" — the journal records when each
/// find happened, not a fuzzy "x ago".
String _formatTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}.${two(t.month)}.${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}





