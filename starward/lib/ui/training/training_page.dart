import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/training_session.dart';
import '../../state/game_controller.dart';
import '../game_scope.dart';
import '../widgets/common.dart';
import '../widgets/starfield.dart';
import 'courses.dart';

/// Page 6 — 训练 (energy refill).
///
/// A bottom-nav tab that is always mounted, so it is a [StatefulWidget] like
/// the other tabs. Completing a guided course grants energy (EN), which is the
/// fuel the player spends travelling the galaxy. Everything observes the
/// [GameController] through an [AnimatedBuilder] so the energy badge and the
/// supply log update the instant a reward is claimed.
class TrainingPage extends StatefulWidget {
  const TrainingPage({super.key});

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
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
              // Keep the starfield showing through the translucent panels so
              // the page matches the rest of the app's "cozy sci-fi" depth.
              const Positioned.fill(
                child: StarfieldBackground(seed: 23, starCount: 110),
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: <Widget>[
        const _IntroLine(),
        const SizedBox(height: 16),
        for (final course in kTrainingCourses) ...<Widget>[
          _CourseCard(
            course: course,
            onStart: () => _startCourse(context, c, course),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        _SupplyLog(controller: c),
      ],
    );
  }

  /// Starts a course then pushes the guided flow. The started session is
  /// created up front so an exit mid-flow still leaves a (non-completed)
  /// record — only [GameController.completeCourse] grants the reward.
  Future<void> _startCourse(
      BuildContext context, GameController c, TrainingCourse course) async {
    final session = await c.startCourse(course.id);
    if (!context.mounted) return;
    // Pushed routes do NOT inherit the GameScope, so re-wrap it here.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScope(
          controller: c,
          child: _CourseFlowPage(course: course, session: session),
        ),
      ),
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
            '训练',
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

class _IntroLine extends StatelessWidget {
  const _IntroLine();

  @override
  Widget build(BuildContext context) {
    return StarPanel(
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: StarColors.flora.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.favorite_rounded,
                color: StarColors.flora, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '能量是你探索星海的燃料。完成一节训练即可补充能量（EN），让下一次远航走得更远。',
              style:
                  TextStyle(color: StarColors.muted, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course, required this.onStart});

  final TrainingCourse course;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final accent = Color(course.seedColor);
    return StarPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _CourseEmblem(color: accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      course.name,
                      style: const TextStyle(
                        color: StarColors.offWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      course.subtitle,
                      style: const TextStyle(
                          color: StarColors.muted, fontSize: 12.5, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        _MetaChip(
                          icon: Icons.schedule_rounded,
                          label: course.durationLabel,
                          color: StarColors.cyanDim,
                        ),
                        const SizedBox(width: 8),
                        _MetaChip(
                          icon: Icons.bolt_rounded,
                          label: '+${course.reward} EN',
                          color: accent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _StartButton(color: accent, onTap: onStart),
        ],
      ),
    );
  }
}

/// A small procedurally-tinted emblem so each course reads as its own thing
/// without needing bitmap art — mirrors how planets derive art from a seed.
class _CourseEmblem extends StatelessWidget {
  const _CourseEmblem({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            Color.lerp(color, Colors.white, 0.35)!,
            color,
          ],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 12),
        ],
      ),
      child: const Icon(Icons.self_improvement_rounded,
          color: StarColors.abyss, size: 24),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip(
      {required this.icon, required this.label, required this.color});

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

class _StartButton extends StatelessWidget {
  const _StartButton({required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.play_arrow_rounded,
                    color: StarColors.abyss, size: 20),
                SizedBox(width: 6),
                Text('开始',
                    style: TextStyle(
                        color: StarColors.abyss,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "补给记录" section: a reverse-chronological list of completed courses,
/// each showing the course name, energy gained and a relative timestamp.
class _SupplyLog extends StatelessWidget {
  const _SupplyLog({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    // Only completed sessions count as supply records; newest first.
    final completed = controller.trainingSessions
        .where((s) => s.status == TrainingStatus.completed)
        .toList()
      ..sort((a, b) => (b.completedAt ?? b.startedAt)
          .compareTo(a.completedAt ?? a.startedAt));
    final courseById = <String, TrainingCourse>{
      for (final course in kTrainingCourses) course.id: course,
    };
    final now = controller.now;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Row(
          children: <Widget>[
            Icon(Icons.history_rounded, color: StarColors.muted, size: 16),
            SizedBox(width: 6),
            Text(
              '补给记录',
              style: TextStyle(
                color: StarColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (completed.isEmpty)
          const StarPanel(
            child: Text(
              '还没有补给记录 — 完成一节训练来补充能量吧。',
              style: TextStyle(
                  color: StarColors.faint, fontSize: 13, height: 1.4),
            ),
          )
        else
          for (final s in completed) ...<Widget>[
            _SupplyEntry(
              course: courseById[s.courseId],
              when: _relativeTime(s.completedAt ?? s.startedAt, now),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _SupplyEntry extends StatelessWidget {
  const _SupplyEntry({required this.course, required this.when});

  /// May be null if a saved session references a course no longer in the
  /// catalogue — the UI degrades gracefully instead of crashing.
  final TrainingCourse? course;
  final String when;

  @override
  Widget build(BuildContext context) {
    final name = course?.name ?? '训练';
    final reward = course?.reward;
    return StarPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle_rounded,
              color: StarColors.flora, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color: StarColors.offWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (reward != null)
            Text(
              '+$reward EN',
              style: const TextStyle(
                color: StarColors.flora,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(width: 10),
          Text(
            when,
            style: const TextStyle(color: StarColors.faint, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Compact relative timestamp for the supply log, e.g. "刚刚" / "12 分钟前".
String _relativeTime(DateTime from, DateTime now) {
  final d = now.difference(from);
  if (d.inMinutes < 1) return '刚刚';
  if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
  if (d.inHours < 24) return '${d.inHours} 小时前';
  return '${d.inDays} 天前';
}

/// The full-screen guided course flow. Pushed as its own route (wrapped in a
/// fresh [GameScope]), it walks the player through each step and only grants
/// the reward on the final 完成 tap via [GameController.completeCourse].
class _CourseFlowPage extends StatefulWidget {
  const _CourseFlowPage({required this.course, required this.session});

  final TrainingCourse course;
  final TrainingSession session;

  @override
  State<_CourseFlowPage> createState() => _CourseFlowPageState();
}

class _CourseFlowPageState extends State<_CourseFlowPage> {
  int _stepIndex = 0;
  bool _completed = false;
  bool _claiming = false; // guards against double-tapping 完成

  TrainingCourse get _course => widget.course;

  void _next() {
    if (_stepIndex < _course.steps.length - 1) {
      setState(() => _stepIndex++);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    final c = GameScope.read(context);
    final result = await c.completeCourse(widget.session.id, _course.reward);
    if (!mounted) return;
    if (result == TrainingClaimResult.success) {
      setState(() => _completed = true);
    } else {
      // Guard tripped (already claimed / not completed / not found): the
      // controller already prevents a second grant, so just acknowledge.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已领取')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(_course.seedColor);
    return Scaffold(
      backgroundColor: StarColors.abyss,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: StarfieldBackground(seed: 31, starCount: 120),
          ),
          SafeArea(
            child: _completed
                ? _CourseResult(
                    course: _course,
                    onBack: () => Navigator.of(context).pop(),
                  )
                : _buildSteps(context, accent),
          ),
        ],
      ),
    );
  }

  Widget _buildSteps(BuildContext context, Color accent) {
    final total = _course.steps.length;
    final isLast = _stepIndex == total - 1;
    return Column(
      children: <Widget>[
        // Close bar — a clear exit is available on every step.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: <Widget>[
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: StarColors.muted),
                tooltip: '退出',
              ),
              Expanded(
                child: Text(
                  _course.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: StarColors.offWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Balances the leading icon button so the title stays centred.
              const SizedBox(width: 48),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '步骤 ${_stepIndex + 1} / $total',
                style: const TextStyle(color: StarColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (_stepIndex + 1) / total,
                  minHeight: 6,
                  backgroundColor: StarColors.panelLight,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: StarPanel(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: 0.16),
                        border: Border.all(
                            color: accent.withValues(alpha: 0.5), width: 1.5),
                      ),
                      child: Text(
                        '${_stepIndex + 1}',
                        style: TextStyle(
                          color: accent,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _course.steps[_stepIndex],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: StarColors.offWhite,
                        fontSize: 18,
                        height: 1.6,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: _FlowButton(
            label: isLast ? '完成' : '下一步',
            color: accent,
            onTap: _claiming ? null : _next,
          ),
        ),
      ],
    );
  }
}
/// The post-completion screen: celebrates the reward and shows the fresh
/// balance. Subscribes to the controller so the balance is always current.
class _CourseResult extends StatelessWidget {
  const _CourseResult({required this.course, required this.onBack});

  final TrainingCourse course;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = GameScope.of(context);
    final accent = Color(course.seedColor);
    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 92,
                    height: 92,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.16),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                            color: accent.withValues(alpha: 0.35),
                            blurRadius: 24),
                      ],
                    ),
                    child: Icon(Icons.check_rounded, color: accent, size: 48),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '训练完成 · +${course.reward} EN',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: StarColors.offWhite,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '当前能量 ${c.energy} EN',
                    style: const TextStyle(
                      color: StarColors.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    course.name,
                    style:
                        const TextStyle(color: StarColors.faint, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: _FlowButton(label: '返回', color: accent, onTap: onBack),
        ),
      ],
    );
  }
}

class _FlowButton extends StatelessWidget {
  const _FlowButton({required this.label, required this.color, this.onTap});

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: disabled ? StarColors.panelLight : color,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: disabled ? StarColors.faint : StarColors.abyss,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}





