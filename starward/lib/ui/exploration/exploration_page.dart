import 'package:flutter/material.dart';

import '../../core/balance.dart';
import '../../core/theme.dart';
import '../../data/models/planet.dart';
import '../../state/game_controller.dart';
import '../game_scope.dart';
import '../widgets/common.dart';
import '../widgets/planet_disc.dart';
import 'alive_world_scene.dart';
import 'civilization_scene.dart';
import 'dead_world_scene.dart';

/// Reports a hotspot tap up to the page. Scenes only know *that* a POI was
/// tapped; the page decides what happens (record it, reveal its card). Keeping
/// this on the page means all three worlds share one interaction flow.
typedef HotspotTap = void Function(PointOfInterest poi);

/// Page 4 — Planet Exploration.
///
/// Dispatches to one of three painted atmospheric scenes based on the planet's
/// [PlanetType] and owns the shared chrome: the top bar (back + identity) and
/// the bottom record/complete flow. The scene is the "world"; this is the HUD
/// drawn over it.
class ExplorationPage extends StatelessWidget {
  const ExplorationPage({super.key, required this.planetId});

  final String planetId;

  @override
  Widget build(BuildContext context) {
    final controller = GameScope.of(context);
    final planet = controller.planetById(planetId);
    if (planet == null) {
      // Stale/unknown id (e.g. an old save after a universe-version bump).
      return const Scaffold(
        backgroundColor: StarColors.abyss,
        body: Center(
          child: Text('星球数据不可用',
              style: TextStyle(color: StarColors.muted)),
        ),
      );
    }
    return _ExplorationView(controller: controller, planet: planet);
  }
}

class _ExplorationView extends StatefulWidget {
  const _ExplorationView({required this.controller, required this.planet});

  final GameController controller;
  final Planet planet;

  @override
  State<_ExplorationView> createState() => _ExplorationViewState();
}

class _ExplorationViewState extends State<_ExplorationView> {
  // The POI whose record card is currently revealed (null = nothing showing).
  PointOfInterest? _activeRecord;
  // Shown briefly after the first completion so the reward reads as earned.
  bool _showReward = false;
  // Guards against double-taps re-entering the completion flow.
  bool _completing = false;

  GameController get _c => widget.controller;
  Planet get _planet => widget.planet;

  /// Featured planets expose authored hotspots; filler planets fall back to a
  /// single generic surface scan so EVERY planet stays explorable.
  List<PointOfInterest> get _pois => _planet.pointsOfInterest.isEmpty
      ? <PointOfInterest>[_genericScanPoi(_planet)]
      : _planet.pointsOfInterest;

  Future<void> _onTapHotspot(PointOfInterest poi) async {
    // The controller de-dupes by poi.id, so tapping an already-found hotspot
    // is a harmless no-op that simply reopens its record card.
    await _c.recordDiscovery(_planet, poi);
    if (!mounted) return;
    setState(() => _activeRecord = poi);
  }

  void _closeRecord() => setState(() => _activeRecord = null);

  // Kicked off from a plain (sync) VoidCallback so the discarded future never
  // trips the analyzer, while the real work stays async below.
  void _completeAndExit() {
    if (_completing) return;
    _completing = true;
    _runCompletion();
  }

  Future<void> _runCompletion() async {
    final first = await _c.completeExploration(_planet);
    if (!mounted) return;
    if (first) {
      // Reward only lands the first time; linger on a confirmation, then exit.
      setState(() => _showReward = true);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      if (!mounted) return;
    }
    Navigator.of(context).pop();
  }

  Widget _buildScene(List<PointOfInterest> pois, Set<String> foundIds) {
    switch (_planet.type) {
      case PlanetType.dead:
        return DeadWorldScene(
          planet: _planet,
          pointsOfInterest: pois,
          foundIds: foundIds,
          onTapHotspot: _onTapHotspot,
        );
      case PlanetType.alive:
        return AliveWorldScene(
          planet: _planet,
          pointsOfInterest: pois,
          foundIds: foundIds,
          onTapHotspot: _onTapHotspot,
        );
      case PlanetType.civilization:
        return CivilizationScene(
          planet: _planet,
          pointsOfInterest: pois,
          foundIds: foundIds,
          onTapHotspot: _onTapHotspot,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StarColors.abyss,
      // AnimatedBuilder keeps found-state and progress live as the controller
      // records discoveries.
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final pois = _pois;
          final foundIds = _c.foundPoiIds(_planet.id);
          final explored = _c.stateOf(_planet.id) == DiscoveryState.explored;
          final foundCount =
              pois.where((p) => foundIds.contains(p.id)).length;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Positioned.fill(child: _buildScene(pois, foundIds)),
              // Scrims behind the HUD so text stays legible over busy scenes;
              // IgnorePointer lets taps fall through to hotspots underneath.
              const Positioned.fill(child: IgnorePointer(child: _ChromeScrim())),
              SafeArea(
                child: Column(
                  children: <Widget>[
                    _TopBar(
                      planet: _planet,
                      onBack: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    _BottomBar(
                      foundCount: foundCount,
                      total: pois.length,
                      explored: explored,
                      onComplete: _completeAndExit,
                      onReturn: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              if (_activeRecord != null)
                _RecordOverlay(poi: _activeRecord!, onClose: _closeRecord),
              if (_showReward) const _RewardToast(),
            ],
          );
        },
      ),
    );
  }
}

/// Builds the fallback "scan the surface" POI for planets without authored
/// content, with flavour text matched to the planet's type so even filler
/// worlds record something that fits their nature.
PointOfInterest _genericScanPoi(Planet planet) {
  switch (planet.type) {
    case PlanetType.dead:
      return PointOfInterest(
        id: '${planet.id}-scan',
        label: '扫描地表',
        discoveryType: 'scan',
        discoveryTitle: '荒芜地表扫描',
        discoveryDescription:
            '扫描完成：风化的岩层与尘埃铺满地表，没有大气、没有液态水，是一颗彻底沉寂的世界。',
        x: 0.5,
        y: 0.56,
      );
    case PlanetType.alive:
      return PointOfInterest(
        id: '${planet.id}-scan',
        label: '扫描地表',
        discoveryType: 'scan',
        discoveryTitle: '生机地表扫描',
        discoveryDescription:
            '扫描完成：大气中检出水汽与有机分子，地表的色泽暗示着某种初生的生态正在悄然蔓延。',
        x: 0.5,
        y: 0.56,
      );
    case PlanetType.civilization:
      return PointOfInterest(
        id: '${planet.id}-scan',
        label: '扫描地表',
        discoveryType: 'scan',
        discoveryTitle: '信号地表扫描',
        discoveryDescription:
            '扫描完成：捕捉到规律的人造电磁脉冲，暗示这颗星球曾经，或仍然，是某个文明的居所。',
        x: 0.5,
        y: 0.56,
      );
  }
}

/// Twin top/bottom gradients that darken the scene behind the HUD without
/// hiding the middle band where the hotspots live.
class _ChromeScrim extends StatelessWidget {
  const _ChromeScrim();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          height: 150,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                StarColors.abyss.withValues(alpha: 0.72),
                StarColors.abyss.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
        const Spacer(),
        Container(
          height: 220,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: <Color>[
                StarColors.abyss.withValues(alpha: 0.88),
                StarColors.abyss.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The AppBar-like top bar: back arrow, a small [PlanetDisc] emblem that ties
/// the explored world to its map appearance, and the planet's identity.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.planet, required this.onBack});

  final Planet planet;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final typeColor = StarLabels.planetTypeColor(planet.type);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            color: StarColors.offWhite,
            tooltip: '返回',
          ),
          PlanetDisc(planet: planet, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  planet.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: StarColors.offWhite,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(StarLabels.planetTypeIcon(planet.type),
                        color: typeColor, size: 13),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '${StarLabels.planetType(planet.type)} · ${planet.designation}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: typeColor, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared bottom flow: discovery progress plus the primary action. The action
/// adapts to state — "返回" once the planet is explored, otherwise a complete
/// button gated on having found at least one POI.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.foundCount,
    required this.total,
    required this.explored,
    required this.onComplete,
    required this.onReturn,
  });

  final int foundCount;
  final int total;
  final bool explored;
  final VoidCallback onComplete;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final allFound = foundCount >= total;
    final canComplete = foundCount >= 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: StarPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.travel_explore_rounded,
                    color: StarColors.cyan, size: 18),
                const SizedBox(width: 8),
                Text(
                  '已发现 $foundCount / $total 兴趣点',
                  style: const TextStyle(
                    color: StarColors.offWhite,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (allFound)
                  const Text(
                    '全部已发现',
                    style: TextStyle(
                      color: StarColors.flora,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _Progress(found: foundCount, total: total),
            const SizedBox(height: 14),
            if (explored)
              _ActionButton(
                label: '返回',
                icon: Icons.check_circle_rounded,
                color: StarColors.flora,
                onPressed: onReturn,
              )
            else
              _ActionButton(
                label: '完成探索 · 加入日志',
                icon: Icons.auto_stories_rounded,
                color: StarColors.gold,
                onPressed: canComplete ? onComplete : null,
              ),
            if (!explored && !canComplete) ...<Widget>[
              const SizedBox(height: 8),
              const Text(
                '轻触场景中的光点，发现至少一个兴趣点后即可完成探索。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: StarColors.faint, fontSize: 11.5, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.found, required this.total});

  final int found;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : (found / total).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 6,
        backgroundColor: StarColors.panelLight,
        valueColor: const AlwaysStoppedAnimation<Color>(StarColors.cyan),
      ),
    );
  }
}

/// Filled pill button; falls back to a muted disabled look when [onPressed] is
/// null, matching the action buttons used elsewhere in the app.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final bg = disabled ? StarColors.panelLight : color;
    final fg = disabled ? StarColors.faint : StarColors.abyss;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: fg, size: 19),
              const SizedBox(width: 9),
              Text(
                label,
                style: TextStyle(
                    color: fg, fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen scrim + centred record card that enters with a fade + scale
/// "reveal". Tapping the scrim or the card's button dismisses it.
class _RecordOverlay extends StatelessWidget {
  const _RecordOverlay({required this.poi, required this.onClose});

  final PointOfInterest poi;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        // Keying on the POI id restarts the reveal when a new hotspot opens.
        key: ValueKey<String>(poi.id),
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
        builder: (context, t, _) {
          final tc = t.clamp(0.0, 1.0);
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.6 * tc),
                  ),
                ),
              ),
              Center(
                child: Transform.scale(
                  scale: 0.9 + 0.1 * t,
                  child: Opacity(
                    opacity: tc,
                    child: _RecordCard(poi: poi, onClose: onClose),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.poi, required this.onClose});

  final PointOfInterest poi;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final meta = _discoveryMeta(poi.discoveryType);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      constraints: const BoxConstraints(maxWidth: 360),
      child: StarPanel(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: meta.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: meta.color.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(meta.icon, color: meta.color, size: 13),
                      const SizedBox(width: 5),
                      Text(
                        meta.label,
                        style: TextStyle(
                            color: meta.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const Icon(Icons.check_circle_rounded,
                    color: StarColors.flora, size: 18),
                const SizedBox(width: 4),
                const Text(
                  '已记录',
                  style: TextStyle(
                      color: StarColors.flora,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              poi.discoveryTitle,
              style: const TextStyle(
                  color: StarColors.offWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              poi.discoveryDescription,
              style: const TextStyle(
                  color: StarColors.muted, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onClose,
                style:
                    TextButton.styleFrom(foregroundColor: StarColors.cyan),
                child: const Text('收起'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Visual metadata for a discovery category, so record cards and chips stay
/// consistent and the free-form English [discoveryType] never leaks into the
/// Chinese UI.
class _DiscoveryMeta {
  const _DiscoveryMeta(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

_DiscoveryMeta _discoveryMeta(String type) {
  switch (type) {
    case 'terrain':
      return const _DiscoveryMeta('地貌', Icons.terrain_rounded, StarColors.muted);
    case 'mineral':
      return const _DiscoveryMeta('矿物', Icons.diamond_rounded, StarColors.cyan);
    case 'ruin':
      return const _DiscoveryMeta(
          '遗迹', Icons.account_balance_rounded, StarColors.gold);
    case 'flora':
      return const _DiscoveryMeta(
          '植物', Icons.local_florist_rounded, StarColors.flora);
    case 'lifeform':
      return const _DiscoveryMeta('生命', Icons.pets_rounded, StarColors.flora);
    case 'civilization':
      return const _DiscoveryMeta(
          '文明', Icons.apartment_rounded, StarColors.gold);
    case 'signal':
      return const _DiscoveryMeta('信号', Icons.sensors_rounded, StarColors.cyan);
    case 'scan':
      return const _DiscoveryMeta('扫描', Icons.radar_rounded, StarColors.cyanDim);
    default:
      return const _DiscoveryMeta(
          '发现', Icons.auto_awesome_rounded, StarColors.cyan);
  }
}

/// Brief, non-interactive confirmation shown once when the planet is completed
/// for the first time, surfacing the one-time energy reward.
class _RewardToast extends StatelessWidget {
  const _RewardToast();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
          builder: (context, t, child) {
            final tc = t.clamp(0.0, 1.0);
            return Opacity(
              opacity: tc,
              child: Transform.scale(scale: 0.92 + 0.08 * tc, child: child),
            );
          },
          child: Center(
            child: StarPanel(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.verified_rounded,
                      color: StarColors.gold, size: 34),
                  const SizedBox(height: 10),
                  const Text(
                    '探索完成',
                    style: TextStyle(
                        color: StarColors.offWhite,
                        fontSize: 17,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '+${Balance.explorationReward} EN 已记录',
                    style: const TextStyle(
                        color: StarColors.gold,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pulsing beacon marking a point of interest. Shared by all three scenes so
/// hotspots behave identically regardless of the surrounding art; [accent] lets
/// each world tint the beacon to match its palette. Found hotspots drop their
/// pulse and dim to a checkmark, but stay tappable to reopen their record.
class ExplorationHotspot extends StatefulWidget {
  const ExplorationHotspot({
    super.key,
    required this.label,
    required this.found,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool found;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<ExplorationHotspot> createState() => _ExplorationHotspotState();
}

class _ExplorationHotspotState extends State<ExplorationHotspot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 58,
            height: 58,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                final t = _pulse.value;
                return Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    // Expanding ring; suppressed once found so the site reads
                    // as quiet and already-visited.
                    if (!widget.found)
                      Opacity(
                        opacity: (1 - t) * 0.55,
                        child: Container(
                          width: 22 + t * 34,
                          height: 22 + t * 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: accent, width: 2),
                          ),
                        ),
                      ),
                    child!,
                  ],
                );
              },
              child: _HotspotCore(found: widget.found, accent: accent),
            ),
          ),
          const SizedBox(height: 4),
          _HotspotLabel(
            text: widget.label,
            found: widget.found,
            accent: accent,
          ),
        ],
      ),
    );
  }
}

class _HotspotCore extends StatelessWidget {
  const _HotspotCore({required this.found, required this.accent});

  final bool found;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: found ? accent.withValues(alpha: 0.35) : accent,
        border: Border.all(
            color: StarColors.offWhite.withValues(alpha: 0.85), width: 1.5),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: accent.withValues(alpha: 0.7),
              blurRadius: 12,
              spreadRadius: 1),
        ],
      ),
      child: Icon(
        found ? Icons.check_rounded : Icons.add_rounded,
        size: 15,
        color: found ? StarColors.offWhite : StarColors.abyss,
      ),
    );
  }
}

class _HotspotLabel extends StatelessWidget {
  const _HotspotLabel(
      {required this.text, required this.found, required this.accent});

  final String text;
  final bool found;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: StarColors.abyss.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: found ? 0.25 : 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: found ? StarColors.muted : StarColors.offWhite,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

