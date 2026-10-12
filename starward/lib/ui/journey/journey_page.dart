import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/journey.dart';
import '../../data/models/planet.dart';
import '../../state/game_controller.dart';
import '../exploration/exploration_page.dart';
import '../game_scope.dart';
import '../shell/shell_scope.dart';
import '../widgets/common.dart';
import '../widgets/planet_disc.dart';
import '../widgets/starfield.dart';

/// Page 3 — the auto-journey / flight ambience screen. Always mounted inside
/// the shell's [IndexedStack], so it must build while hidden and tear down its
/// timer/ticker cleanly. It is a pure view over [GameController.activeJourney];
/// the controller owns every state transition. We only drive a once-per-second
/// [GameController.tick] so the inProgress -> arrived flip surfaces promptly.
class JourneyPage extends StatefulWidget {
  const JourneyPage({super.key});

  @override
  State<JourneyPage> createState() => _JourneyPageState();
}

class _JourneyPageState extends State<JourneyPage>
    with TickerProviderStateMixin {
  // Flips the arrived state once per second while a voyage is in progress.
  Timer? _tickTimer;

  // One-shot reveal for the arrival ceremony (fade + scale the planet in).
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  // Monotonic per-frame phase (seconds) driving the star-stream + engine glow.
  // A Ticker (not a repeating controller) gives an ever-increasing value, which
  // the starfield needs: its scrollSpeed is a static offset, so continuous
  // forward motion only appears while that offset keeps growing.
  late final _flightTicker = createTicker((elapsed) {
    _phase.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  });
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);

  JourneyStatus? _lastStatus;
  @override
  void dispose() {
    _tickTimer?.cancel();
    _flightTicker.dispose();
    _phase.dispose();
    _reveal.dispose();
    super.dispose();
  }

  /// Keeps the timer, flight ticker and reveal animation in lock-step with the
  /// live journey status. Driven from the controller rebuild so it reacts the
  /// instant a voyage launches elsewhere or flips to arrived.
  void _sync(GameController c) {
    final status = c.activeJourney?.status;
    if (status == JourneyStatus.inProgress) {
      _tickTimer ??=
          Timer.periodic(const Duration(seconds: 1), (_) => c.tick());
      if (!_flightTicker.isActive) _flightTicker.start();
    } else {
      _tickTimer?.cancel();
      _tickTimer = null;
      if (_flightTicker.isActive) _flightTicker.stop();
    }
    if (status == JourneyStatus.arrived &&
        _lastStatus != JourneyStatus.arrived) {
      _reveal.forward(from: 0);
    }
    _lastStatus = status;
  }

  @override
  Widget build(BuildContext context) {
    final c = GameScope.of(context);
    return Scaffold(
      backgroundColor: StarColors.abyss,
      body: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          _sync(c);
          final journey = c.activeJourney;
          switch (journey?.status) {
            case JourneyStatus.inProgress:
              return _buildFlight(c, journey!);
            case JourneyStatus.arrived:
              return _buildArrival(c, journey!);
            case JourneyStatus.completed:
            case null:
              return _buildStandby(c);
          }
        },
      ),
    );
  }
  // --- Arrival actions -----------------------------------------------------

  Future<void> _startExploration(GameController c, Planet dest) async {
    // Filler planets have nothing to explore: acknowledge the arrival (freeing
    // the ship) and drop the player back on the map instead of a blank scene.
    if (dest.pointsOfInterest.isEmpty) {
      await c.acknowledgeArrival();
      if (!mounted) return;
      ShellScope.go(context, 0);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScope(
          controller: c,
          child: ExplorationPage(planetId: dest.id),
        ),
      ),
    );
  }

  Future<void> _returnToMap(GameController c) async {
    await c.acknowledgeArrival();
    if (!mounted) return;
    ShellScope.go(context, 0);
  }

  // --- Flight actions ------------------------------------------------------

  Future<void> _abortFlight(GameController c) async {
    final ok = await _confirm(
      title: '停止航行',
      message: '飞船将在当前位置停下，漂浮于深空。已消耗的能量不会退还。',
      confirmLabel: '停止',
      danger: true,
    );
    if (ok != true) return;
    await c.abortJourney();
  }

  Future<void> _changeCourse(GameController c) async {
    final ok = await _confirm(
      title: '改变航向',
      message: '将中止当前航行并回到星图重新选择目的地。已消耗的能量不会退还。',
      confirmLabel: '去星图',
    );
    if (ok != true) return;
    await c.abortJourney();
    if (!mounted) return;
    ShellScope.go(context, 0);
  }

  Future<void> _returnHome(GameController c) async {
    final ok = await _confirm(
      title: '返航',
      message: '飞船将掉头返回出发点，需要为返程消耗能量。',
      confirmLabel: '返航',
    );
    if (ok != true) return;
    final res = await c.returnToOrigin();
    if (!mounted) return;
    if (res == LaunchResult.insufficientEnergy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('能量不足，无法返航')),
      );
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StarColors.deepNavy,
        title: Text(title, style: const TextStyle(color: StarColors.offWhite)),
        content: Text(message,
            style: const TextStyle(color: StarColors.muted, height: 1.5)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(color: StarColors.faint)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel,
                style: TextStyle(
                    color: danger ? StarColors.danger : StarColors.cyan,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Nearest not-yet-explored planet, preferring the hand-authored hero worlds
  /// so the suggestion always leads somewhere with real content to discover.
  Planet? _recommendDestination(GameController c) {
    Planet? best;
    double bestDistance = double.infinity;
    for (final p in c.planets) {
      if (p.id == c.currentPlanetId) continue;
      if (c.stateOf(p.id) == DiscoveryState.explored) continue;
      final distance = c.distanceTo(p);
      final isBetter = best == null ||
          (p.featured && !best.featured) ||
          (p.featured == best.featured && distance < bestDistance);
      if (isBetter) {
        best = p;
        bestDistance = distance;
      }
    }
    return best;
  }
  // --- State 1: standby ----------------------------------------------------

  Widget _buildStandby(GameController c) {
    final current = c.currentPlanet;
    final drifting = current == null;
    final rec = _recommendDestination(c);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // No motion while idle — a calm, static deep-space field.
        const Positioned.fill(
          child: StarfieldBackground(seed: 7, starCount: 150),
        ),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 76, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: 24),
                Icon(drifting ? Icons.explore_rounded : Icons.nightlight_round,
                    size: 44, color: StarColors.cyanDim),
                const SizedBox(height: 16),
                Text(
                  drifting ? '漂浮于深空' : '没有进行中的航行',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: StarColors.offWhite,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  drifting
                      ? '你的飞船正静静悬停在星海之中，等待你选择第一个目的地。'
                      : '飞船正在 ${current.name} 停泊待命，等待下一段旅程。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: StarColors.muted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),
                if (drifting)
                  _DriftDock(controller: c)
                else
                  _CurrentDock(planet: current),
                if (rec != null) ...<Widget>[
                  const SizedBox(height: 24),
                  const Text(
                    '推荐目的地',
                    style: TextStyle(
                      color: StarColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RecommendCard(controller: c, planet: rec),
                ],
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _TopBar(energy: c.energy, subtitle: drifting ? '深空待命' : '待命'),
        ),
      ],
    );
  }
  // --- State 2: flight -----------------------------------------------------

  Widget _buildFlight(GameController c, Journey journey) {
    final isStar = GameController.isStarDestination(journey.destinationPlanetId);
    final destPlanet = c.planetById(journey.destinationPlanetId);
    final destName = c.locationLabel(journey.destinationPlanetId);
    final now = c.now;
    final progress = journey.progressAt(now);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(
          child: ValueListenableBuilder<double>(
            valueListenable: _phase,
            builder: (context, phase, _) {
              final speedFactor = 180 * (1 + progress * 0.6);
              return StarfieldBackground(
                seed: 7,
                starCount: 170,
                scrollSpeed: 0.0008 * speedFactor * phase,
              );
            },
          ),
        ),
        // Destination ahead — a planet disc, or a bright star for star trips.
        Align(
          alignment: const Alignment(0, -0.4),
          child: (isStar || destPlanet == null)
              ? _FlightStar(progress: progress)
              : _FlightPlanet(planet: destPlanet, progress: progress),
        ),
        Align(
          alignment: const Alignment(0, 0.3),
          child: ValueListenableBuilder<double>(
            valueListenable: _phase,
            builder: (context, phase, _) => _Ship(
              glow: 0.5 + 0.5 * math.sin(phase * math.pi * 2 / 1.5),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _FlightPanel(
                  controller: c,
                  journey: journey,
                  destName: destName,
                  progress: progress,
                  now: now,
                ),
                const SizedBox(height: 12),
                _FlightControls(
                  onReturn: () => _returnHome(c),
                  onChangeCourse: () => _changeCourse(c),
                  onStop: () => _abortFlight(c),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _TopBar(energy: c.energy, subtitle: '航行中'),
        ),
      ],
    );
  }
  // --- State 3: arrival ----------------------------------------------------

  Widget _buildArrival(GameController c, Journey journey) {
    final isStar = GameController.isStarDestination(journey.destinationPlanetId);
    final isDeepSpace =
        GameController.isCoordDestination(journey.destinationPlanetId);
    final dest = c.planetById(journey.destinationPlanetId);
    final destName = c.locationLabel(journey.destinationPlanetId);
    final canExplore = !isStar && dest != null && dest.pointsOfInterest.isNotEmpty;
    final reveal = CurvedAnimation(parent: _reveal, curve: Curves.easeOutCubic);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const Positioned.fill(
          child: StarfieldBackground(seed: 7, starCount: 150),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 76, 24, 28),
            child: Column(
              children: <Widget>[
                const Spacer(),
                AnimatedBuilder(
                  animation: _reveal,
                  builder: (context, child) => Opacity(
                    opacity: reveal.value,
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * reveal.value,
                      child: child,
                    ),
                  ),
                  child: (isStar || dest == null)
                      ? const _ArrivalStar()
                      : _GlowPlanet(planet: dest, intensity: 0.9, size: 180),
                ),
                const SizedBox(height: 28),
                const Text(
                  '已抵达',
                  style: TextStyle(
                    color: StarColors.muted,
                    fontSize: 13,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  destName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: StarColors.offWhite,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isDeepSpace
                      ? '深空坐标'
                      : (isStar || dest == null
                          ? '恒星系'
                          : '${dest.designation} · ${StarLabels.planetType(dest.type)}'),
                  style: const TextStyle(
                    color: StarColors.faint,
                    fontSize: 12,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                if (canExplore) ...<Widget>[
                  _ActionButton(
                    label: '开始探索',
                    icon: Icons.travel_explore_rounded,
                    color: StarColors.gold,
                    onPressed: () => _startExploration(c, dest),
                  ),
                  const SizedBox(height: 12),
                ],
                _ActionButton(
                  label: '返回星图',
                  icon: Icons.public_rounded,
                  filled: !canExplore,
                  onPressed: () => _returnToMap(c),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _TopBar(energy: c.energy, subtitle: '已抵达'),
        ),
      ],
    );
  }
}
/// Top bar shared by all three states: small "航行" title + current status on
/// the left, live energy readout on the right.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.energy, required this.subtitle});

  final int energy;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '航行',
                  style: TextStyle(
                    color: StarColors.offWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style:
                      const TextStyle(color: StarColors.muted, fontSize: 12),
                ),
              ],
            ),
            EnergyBadge(energy: energy),
          ],
        ),
      ),
    );
  }
}
/// Where the ship is currently docked, shown in the standby state.
class _CurrentDock extends StatelessWidget {
  const _CurrentDock({required this.planet});

  final Planet planet;

  @override
  Widget build(BuildContext context) {
    return StarPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          PlanetDisc(planet: planet, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('当前停泊',
                    style: TextStyle(color: StarColors.faint, fontSize: 11)),
                const SizedBox(height: 3),
                Text(
                  planet.name,
                  style: const TextStyle(
                    color: StarColors.offWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.anchor_rounded,
              color: StarColors.cyanDim, size: 20),
        ],
      ),
    );
  }
}

/// Shown in the standby state when the player is still drifting in deep space
/// (before the first arrival): the ship's randomised galactic coordinates.
class _DriftDock extends StatelessWidget {
  const _DriftDock({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final p = controller.deepSpaceOrigin3D;
    final coord = p == null
        ? '—'
        : 'X ${p.x.toStringAsFixed(1)}  Y ${p.y.toStringAsFixed(1)}  Z ${p.z.toStringAsFixed(1)} ly';
    return StarPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: StarColors.panelLight,
            ),
            child: const Icon(Icons.my_location_rounded,
                color: StarColors.cyan, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('当前坐标 · 深空',
                    style: TextStyle(color: StarColors.faint, fontSize: 11)),
                const SizedBox(height: 3),
                Text(
                  coord,
                  style: const TextStyle(
                    color: StarColors.offWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
/// Suggested next destination with a shortcut to the star map.
class _RecommendCard extends StatelessWidget {
  const _RecommendCard({required this.controller, required this.planet});

  final GameController controller;
  final Planet planet;

  @override
  Widget build(BuildContext context) {
    final distance = StarLabels.distance(controller.distanceTo(planet));
    final cost = controller.energyCostTo(planet);
    return StarPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _GlowPlanet(planet: planet, intensity: 0.5, size: 68),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      planet.name,
                      style: const TextStyle(
                        color: StarColors.offWhite,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${planet.designation} · ${StarLabels.planetType(planet.type)}',
                      style: const TextStyle(
                          color: StarColors.faint, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '距离 $distance · 预计消耗 $cost EN',
                      style: const TextStyle(
                          color: StarColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ActionButton(
            label: '在星图中查看',
            icon: Icons.public_rounded,
            onPressed: () => ShellScope.go(context, 0),
          ),
        ],
      ),
    );
  }
}
/// A [PlanetDisc] wrapped in a soft coloured halo. [intensity] (0..1) scales
/// the glow so the same disc can read as "distant" or "looming close".
class _GlowPlanet extends StatelessWidget {
  const _GlowPlanet({
    required this.planet,
    required this.intensity,
    required this.size,
  });

  final Planet planet;
  final double intensity;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(planet.seedColor)
                .withValues(alpha: 0.25 + 0.45 * intensity),
            blurRadius: 30 + 50 * intensity,
            spreadRadius: 2 + 8 * intensity,
          ),
        ],
      ),
      child: PlanetDisc(planet: planet, size: size),
    );
  }
}

/// The destination as seen from the cockpit: grows from a distant speck to a
/// looming disc and brightens as the voyage completes.
class _FlightPlanet extends StatelessWidget {
  const _FlightPlanet({required this.planet, required this.progress});

  final Planet planet;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return _GlowPlanet(
      planet: planet,
      intensity: 0.3 + progress * 0.7,
      size: 70 + progress * 180,
    );
  }
}
/// Minimal "ship console" readout for the flight state: destination, a big
/// ETA, a progress bar, and a compact distance/energy line. Pared down to the
/// essentials so it reads like a cockpit display rather than a data dump.
class _FlightPanel extends StatelessWidget {
  const _FlightPanel({
    required this.controller,
    required this.journey,
    required this.destName,
    required this.progress,
    required this.now,
  });

  final GameController controller;
  final Journey journey;
  final String destName;
  final double progress;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final distance = StarLabels.distance(controller.journeyDistance(journey));
    final remaining = journey.remainingAt(now);
    final percent = (progress * 100).round();
    return StarPanel(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.navigation_rounded,
                  color: StarColors.cyan, size: 15),
              const SizedBox(width: 6),
              const Text('航向',
                  style: TextStyle(
                      color: StarColors.faint,
                      fontSize: 11,
                      letterSpacing: 2)),
              const Spacer(),
              Text('$percent%',
                  style: const TextStyle(
                      color: StarColors.cyan,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            destName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: StarColors.offWhite,
                fontSize: 22,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              const Text('剩余  ',
                  style: TextStyle(color: StarColors.faint, fontSize: 12)),
              Text(
                StarLabels.duration(remaining),
                style: const TextStyle(
                    color: StarColors.cyan,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: StarColors.panelLight,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(StarColors.cyan),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('航程 $distance',
                  style:
                      const TextStyle(color: StarColors.muted, fontSize: 12)),
              Text('能量 ${controller.energy} EN',
                  style:
                      const TextStyle(color: StarColors.muted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The destination star during a star-bound flight: a bright, growing point of
/// light with layered glow (a star is a point, not a disc).
class _FlightStar extends StatelessWidget {
  const _FlightStar({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final size = 40 + progress * 120;
    return SizedBox(
      width: size * 2,
      height: size * 2,
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: <Color>[Colors.white, StarColors.cyan, Color(0x00000000)],
              stops: <double>[0.0, 0.35, 1.0],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: StarColors.cyan.withValues(alpha: 0.4 + 0.4 * progress),
                blurRadius: 40 + 60 * progress,
                spreadRadius: 4 + 10 * progress,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Arrival emblem for a star system (no planet to land on).
class _ArrivalStar extends StatelessWidget {
  const _ArrivalStar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: <Color>[Colors.white, StarColors.gold, Color(0x00000000)],
          stops: <double>[0.0, 0.4, 1.0],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: StarColors.gold.withValues(alpha: 0.6),
            blurRadius: 70,
            spreadRadius: 10,
          ),
        ],
      ),
    );
  }
}

/// Full-width pill button matching the app's primary/secondary action style.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
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
    final fg = filled ? StarColors.abyss : color;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: filled ? color : Colors.transparent,
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
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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
/// Mid-flight command row: turn back, re-plot a course, or stop and drift.
class _FlightControls extends StatelessWidget {
  const _FlightControls({
    required this.onReturn,
    required this.onChangeCourse,
    required this.onStop,
  });

  final VoidCallback onReturn;
  final VoidCallback onChangeCourse;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _FlightControlButton(
            label: '返航',
            icon: Icons.u_turn_left_rounded,
            color: StarColors.cyan,
            onTap: onReturn,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FlightControlButton(
            label: '改航向',
            icon: Icons.alt_route_rounded,
            color: StarColors.gold,
            onTap: onChangeCourse,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FlightControlButton(
            label: '停止',
            icon: Icons.stop_rounded,
            color: StarColors.danger,
            onTap: onStop,
          ),
        ),
      ],
    );
  }
}

class _FlightControlButton extends StatelessWidget {
  const _FlightControlButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StarColors.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The player's ship: a sleek hull with a pulsing engine bloom. [glow] (0..1)
/// is driven by the flight phase so the exhaust breathes in real time.
class _Ship extends StatelessWidget {
  const _Ship({required this.glow});

  final double glow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 128,
      child: CustomPaint(painter: _ShipPainter(glow: glow)),
    );
  }
}

class _ShipPainter extends CustomPainter {
  _ShipPainter({required this.glow});

  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Soft engine bloom beneath the ship — the core of the "flight" feel.
    final bloomCenter = Offset(cx, h * 0.86);
    final bloomRadius = w * (0.42 + 0.12 * glow);
    canvas.drawCircle(
      bloomCenter,
      bloomRadius,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            StarColors.cyan.withValues(alpha: 0.45 + 0.35 * glow),
            StarColors.cyan.withValues(alpha: 0.0),
          ],
        ).createShader(
            Rect.fromCircle(center: bloomCenter, radius: bloomRadius))
        ..blendMode = BlendMode.screen,
    );

    // Exhaust flame, length pulsing with the engine glow.
    final flame = Path()
      ..moveTo(cx - w * 0.11, h * 0.6)
      ..quadraticBezierTo(cx, h * (0.9 + 0.08 * glow), cx + w * 0.11, h * 0.6)
      ..close();
    canvas.drawPath(
      flame,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[StarColors.offWhite, StarColors.cyan],
        ).createShader(
            Rect.fromLTWH(cx - w * 0.11, h * 0.6, w * 0.22, h * 0.3)),
    );

    // Rear fins.
    final finPaint = Paint()..color = StarColors.cyanDim;
    canvas.drawPath(
      Path()
        ..moveTo(cx - w * 0.14, h * 0.42)
        ..lineTo(cx - w * 0.34, h * 0.62)
        ..lineTo(cx - w * 0.14, h * 0.6)
        ..close(),
      finPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(cx + w * 0.14, h * 0.42)
        ..lineTo(cx + w * 0.34, h * 0.62)
        ..lineTo(cx + w * 0.14, h * 0.6)
        ..close(),
      finPaint,
    );

    // Sleek hull pointing up.
    final hull = Path()
      ..moveTo(cx, h * 0.04)
      ..cubicTo(cx + w * 0.26, h * 0.26, cx + w * 0.2, h * 0.52, cx + w * 0.13,
          h * 0.62)
      ..lineTo(cx - w * 0.13, h * 0.62)
      ..cubicTo(cx - w * 0.2, h * 0.52, cx - w * 0.26, h * 0.26, cx, h * 0.04)
      ..close();
    canvas.drawPath(
      hull,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[StarColors.offWhite, StarColors.muted],
        ).createShader(Rect.fromLTWH(cx - w * 0.26, 0, w * 0.52, h * 0.62)),
    );

    // Glowing cockpit.
    final cockpit = Offset(cx, h * 0.26);
    canvas.drawCircle(
      cockpit,
      w * 0.09,
      Paint()..color = StarColors.cyan.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      cockpit,
      w * 0.09,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = StarColors.offWhite.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(_ShipPainter old) => old.glow != glow;
}
