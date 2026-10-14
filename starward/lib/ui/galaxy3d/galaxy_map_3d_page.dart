import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/journey.dart';
import '../../data/models/planet.dart';
import '../../state/game_controller.dart';
import '../galaxy/planet_details_sheet.dart';
import '../game_scope.dart';
import '../journey/fuel_choice_dialog.dart';
import '../shell/shell_scope.dart';
import '../widgets/common.dart';
import 'camera3d.dart';
import 'cockpit_hud.dart';
import 'galaxy3d_painter.dart';
import 'galaxy3d_scene.dart';
import 'star_system_sheet.dart';
import 'universe_overview_painter.dart';

/// Page 1 (3D) — the galaxy as a real, rotatable, zoomable volume rendered by
/// projecting a 3D scene onto a 2D canvas. Drag to orbit, pinch to zoom, switch
/// between the star-map overview, the first-person cockpit and the universe
/// overview, and adjust the ship's sensor range (the per-ship "view range" hook
/// for future upgrades).
class GalaxyMap3DPage extends StatefulWidget {
  const GalaxyMap3DPage({super.key});

  @override
  State<GalaxyMap3DPage> createState() => _GalaxyMap3DPageState();
}

class _GalaxyMap3DPageState extends State<GalaxyMap3DPage> {
  late final GameController _c;
  final Camera3D _camera = Camera3D();

  static const double _worldScale = 12;

  /// Last scene built in [build], reused by the tap handler for hit-testing.
  Galaxy3DScene? _scene;

  String? _selectedId;

  /// Ship sensor range in world units. Placeholder for the upgrade system:
  /// different ships / levels resolve detail at different distances.
  double _sensorRange = 2600;

  double _lastScale = 1;
  bool _initedCamera = false;

  /// Guards the post-frame callback that serves a `requestCockpit()`, so a
  /// rebuild loop cannot queue more than one.
  bool _cockpitRequestScheduled = false;

  double? _radiusLy;

  /// `Universe.universeRadius` scans the whole catalogue on first access and
  /// caches it per Universe instance; this caches it per page so a rebuild
  /// never risks re-triggering that scan.
  double get _universeRadiusLy => _radiusLy ??= _c.universe.universeRadius;

  /// Sphere radius in world units.
  double get _universeRadiusWorld => _universeRadiusLy * _worldScale;

  /// Upper zoom bound. Derived from the framing distance rather than picked by
  /// eye: `d_default` is 2.3R in landscape but 4.15R in portrait (400×800), so
  /// a bound chosen for landscape would clamp the camera *closer* than the
  /// framing distance on a phone and slice the shell open.
  double get _maxDistance =>
      maxDistanceFor(_camera.mode, _universeRadiusWorld);

  /// The framing distance with a 15% margin, so the shell does not touch the
  /// viewport edge.
  double _overviewDefaultDistance(Size2 vp) =>
      1.15 *
      fitDistanceForSphere(
        radius: _universeRadiusWorld,
        viewport: vp,
        fovDegrees: _camera.fovDegrees,
      );

  @override
  void initState() {
    super.initState();
    _c = GameScope.read(context);
  }

  Galaxy3DScene _buildScene() => Galaxy3DScene.build(
        _c.planets,
        hyg: _c.stars,
        worldScale: _worldScale,
        deepSpaceOrigin: _c.deepSpaceOrigin3D,
        extraGalaxies: _c.universe.extraGalaxies,
      );

  /// The ship's 3D world position: its planet when docked, otherwise its live
  /// deep-space position (scaled into world units).
  ///
  /// This must be [GameController.playerPosition3D], not the deep-space
  /// *anchor*: the anchor only moves on a launch or an arrival, so a coasting
  /// ship would leave the marker — and every reading derived from it, the
  /// universe-overview "飞船距球心" among them — frozen for the whole coast.
  Vec3 get _shipPos => _c.playerPosition3D * _worldScale;

  void _initCamera() {
    _initedCamera = true;
    _camera
      ..mode = CameraMode.orbit
      ..target = _shipPos
      ..yaw = 0.6
      ..pitch = 0.35
      ..distance = 520
      ..fovDegrees = 60;
  }

  void _onScaleStart(ScaleStartDetails d) => _lastScale = 1;

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      // Rotation from drag (one finger): horizontal → yaw, vertical → pitch.
      final delta = d.focalPointDelta;
      // Drag-to-look is a *screen* gesture, so it has to be scaled by how much
      // of the world a screen pixel covers. At the default 60° FOV the factor
      // is 1 and the feel is unchanged; zoomed in to 30° the same drag turns
      // half as far, which keeps a star that was under the finger under the
      // finger. Only the cockpit changes FOV (`_initCamera` sets 60 and the
      // pinch clamp is 30–95), so the other two modes always get `k = 0.006`.
      final k = 0.006 * (_camera.fovDegrees / 60);
      if (_camera.mode == CameraMode.cockpit) {
        // Cockpit: look around (invert so dragging feels like turning the view).
        _camera.yaw -= delta.dx * k;
        _camera.pitch -= delta.dy * k;
      } else {
        // Orbit and universe-overview both rotate the volume under the camera.
        _camera.yaw -= delta.dx * k;
        _camera.pitch += delta.dy * k;
      }
      _camera.clampPitch();

      // Zoom from pinch: cockpit changes FOV, the orbiting modes change distance.
      if (d.scale != 1.0) {
        final factor = d.scale / _lastScale;
        _lastScale = d.scale;
        if (_camera.mode == CameraMode.cockpit) {
          _camera.fovDegrees = (_camera.fovDegrees / factor).clamp(30.0, 95.0);
        } else {
          _camera.distance =
              (_camera.distance / factor).clamp(kMinZoomDistance, _maxDistance);
        }
      }
    });
  }

  void _onTapUp(TapUpDetails d, Size size) {
    // The universe overview is read-only. At 12–16 ly/px a tap would hit a
    // near-arbitrary star, and a mis-tap costs a voyage that may burn all the
    // ship's energy — so there is no hit-testing here at all, rather than an
    // inaccurate one. Switch back to 总览 to pick a star.
    if (_camera.mode == CameraMode.overview) return;
    final scene = _scene;
    if (scene == null) return;
    // In-system planet disc first (the only planets drawn)…
    final pid = pickPlanet(
      scene: scene,
      camera: _camera,
      size: size,
      tap: d.localPosition,
      shipPosition: _shipPos,
      sensorRange: _sensorRange,
    );
    if (pid != null) {
      final planet = _c.planetById(pid);
      if (planet != null) {
        setState(() => _selectedId = pid);
        _openDetails(planet);
        return;
      }
    }
    // …otherwise a star: open its system view.
    final starId = pickStarId(
      scene: scene,
      camera: _camera,
      size: size,
      tap: d.localPosition,
      shipPosition: _shipPos,
      sensorRange: _sensorRange,
    );
    if (starId != null) _openSystem(starId);
  }

  String _launchMessage(LaunchResult r) {
    switch (r) {
      case LaunchResult.insufficientEnergy:
        return '能量不足，无法出发';
      case LaunchResult.engineDormant:
        return '引擎处于休眠状态，请先激活（5 EN）';
      case LaunchResult.alreadyTraveling:
        return '已有航行进行中';
      case LaunchResult.alreadyHere:
        return '已经在这里了';
      case LaunchResult.noSelection:
        return '目标不可用';
      case LaunchResult.success:
        return '出发！';
    }
  }

  /// Lights the engine along whatever the reticle is on.
  ///
  /// `FuelPolicy.coast` rather than `halt`: a free cruise that runs out of power
  /// keeps drifting, which is what the player asked for by choosing a
  /// destination-less cruise. Stopping dead in the dark is a surprise, not a
  /// default.
  Future<void> _igniteFromCockpit() async {
    final result =
        await _c.igniteCruise(_camera.forward, onEmpty: FuelPolicy.coast);
    if (!mounted) return;
    if (result != LaunchResult.success) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_launchMessage(result))));
    }
  }

  Future<void> _correctFromCockpit() async {
    final heading = _camera.forward;
    final cost = _c.turnCostTo(heading);
    final ok = await _c.correctHeading(heading);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? '航向已修正（$cost EN）' : '能量不足，无法修正航向'),
    ));
  }

  Future<void> _brakeFromCockpit() async {
    await _c.stopShip();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已制动停下')));
  }

  /// What the cockpit points at: the recommended destination — beyond the
  /// sensor range if the player has lowered it, which is precisely the case the
  /// star map could not show — plus the galactic centre as a fixed reference.
  ///
  /// The recommendation comes from the same 20-ly-stale working set the voyage
  /// dock reads, so the marker's *identity* can lag by up to 20 ly of drift; its
  /// *position* is read fresh from the scene. The marker makes that lag visible,
  /// but it is not a regression — the dock has always read the same set.
  List<HudMarker> _hudMarkers(Galaxy3DScene scene) {
    final out = <HudMarker>[];
    final rec = _c.recommendedDestination;
    if (rec != null && scene.planetPositions.containsKey(rec.id)) {
      out.add(HudMarker(
        world: scene.positionOf(rec.id),
        label: rec.name,
        color: StarColors.gold,
      ));
    }
    out.add(const HudMarker(
      world: Vec3(0, 0, 0),
      label: '银心',
      color: StarColors.cyan,
    ));
    return out;
  }

  /// Launches to a star system, asking how the voyage should end when the
  /// ship cannot afford the whole trip.
  Future<void> _launchToStar(int hygId) async {
    final cost = _c.energyCostToStar(hygId);
    FuelPolicy? policy;
    if (_c.energy < cost) {
      // Below the braking cost there is nothing the dialog could offer — not
      // even running dry, since the ship cannot leave the drift at all.
      if (_c.energy <= _c.brakingCost) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_c.brakingCost > 0
                ? '能量不足，连制动都不够，先去做一组训练吧'
                : '能量不足，先去做一组训练吧'),
          ),
        );
        return;
      }
      policy = await showFuelChoiceDialog(
        context,
        energy: _c.energy,
        cost: cost,
        braking: _c.brakingCost,
        distanceLy: _c.distanceToStar(hygId),
        engine: _c.ship.engine,
      );
      if (policy == null || !mounted) return;
    }
    final result = await _c.launchToStar(hygId, onEmpty: policy ?? FuelPolicy.refuse);
    if (!mounted) return;
    if (result == LaunchResult.success) {
      ShellScope.go(context, 1);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_launchMessage(result))),
      );
    }
  }

  void _openSystem(int hygId) {
    final shell = ShellScope.maybeOf(context);    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        Widget child = GameScope(
          controller: _c,
          child: StarSystemSheet(
            hygId: hygId,
            onSelectPlanet: (planetId) {
              final planet = _c.planetById(planetId);
              if (planet != null) {
                setState(() => _selectedId = planetId);
                _openDetails(planet);
              }
            },
            onGoToStar: (id) => _launchToStar(id),
          ),
        );
        if (shell != null) {
          child = ShellScope(goToTab: shell.goToTab, child: child);
        }
        return child;
      },
    );
  }

  void _openDetails(Planet planet) {
    final shell = ShellScope.maybeOf(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        Widget child = GameScope(
          controller: _c,
          child: PlanetDetailsSheet(planetId: planet.id),
        );
        if (shell != null) {
          child = ShellScope(goToTab: shell.goToTab, child: child);
        }
        return child;
      },
    ).whenComplete(() {
      if (mounted) setState(() => _selectedId = null);
    });
  }

  void _setMode(CameraMode mode, Size2 vp) {
    if (_camera.mode == mode) return;
    setState(() {
      placeCamera(
        _camera,
        mode: mode,
        shipPosition: _shipPos,
        overviewDistance: _overviewDefaultDistance(vp),
      );
      // Entering the cockpit points it at the galactic centre (origin); the
      // other two modes are fully placed by placeCamera.
      if (mode == CameraMode.cockpit) _aimCockpitAtOrigin();
    });
  }

  /// Enters cockpit mode when the voyage screen has asked for it.
  ///
  /// Called from inside the `LayoutBuilder`, which is the only place `vp`
  /// exists — `_setMode` needs it for the overview distance. Both branches defer
  /// their real work to a post-frame callback, because each one calls
  /// `acknowledgeCockpitRequest`, which notifies listeners: the star map's
  /// `AnimatedBuilder` is an ancestor of this `LayoutBuilder` (and is live even
  /// while another tab is selected, because `IndexedStack` builds every child),
  /// so notifying from in here marks it dirty during build — and
  /// `_setMode` would `setState` in the same forbidden phase.
  void _maybeEnterRequestedCockpit(Size2 vp) {
    if (!_c.cockpitRequested) return;
    if (_camera.mode == CameraMode.cockpit) {
      // Already there: nothing to place, so this branch does not need the
      // `_cockpitRequestScheduled` guard (which exists to stop `_setMode` being
      // queued twice). The acknowledge is idempotent, so a re-check inside the
      // callback is enough.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_c.cockpitRequested) return;
        _c.acknowledgeCockpitRequest();
      });
      return;
    }
    if (_cockpitRequestScheduled) return;
    _cockpitRequestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cockpitRequestScheduled = false;
      if (!mounted) return;
      _setMode(CameraMode.cockpit, vp);
      _c.acknowledgeCockpitRequest();
    });
  }

  /// Points the cockpit at the galactic centre. A decorative default, not an
  /// exact aim: the `* 0.6` flattens the tilt so the view lands on the
  /// starfield rather than on the empty middle of the shell. Deliberately
  /// different from `aimCameraAt`, which is the exact form the reticle needs.
  void _aimCockpitAtOrigin() {
    final dir = (const Vec3(0, 0, 0) - _shipPos).normalized;
    _camera.yaw = math.atan2(dir.x, dir.z);
    _camera.pitch = math.asin(dir.y.clamp(-1.0, 1.0)) * 0.6;
    _camera.clampPitch();
  }

  void _recenter(Size2 vp) {
    setState(() {
      if (_camera.mode == CameraMode.cockpit) {
        // `placeCamera` only sets `eyeOverride` in this mode and never touches
        // the aim, so a plain recenter would leave the view pointing exactly
        // where it already points. What the button means here is "point me
        // somewhere known".
        _aimCockpitAtOrigin();
        return;
      }
      placeCamera(
        _camera,
        mode: _camera.mode,
        shipPosition: _shipPos,
        overviewDistance: _overviewDefaultDistance(vp),
      );
    });
  }

  /// Frames the active voyage so it fills about 60% of the viewport's short
  /// edge. At full framing the route is 0.15–3.4 px long — invisible — so this
  /// is the only way to see it without giving up true scale.
  void _focusRoute(Size2 vp) {
    final j = _c.activeJourney;
    final scene = _scene;
    if (j == null || scene == null) return;
    setState(() {
      placeCameraForRoute(
        _camera,
        from: scene.positionOf(j.originPlanetId),
        to: scene.positionOf(j.destinationPlanetId),
        viewport: vp,
        fovDegrees: _camera.fovDegrees,
      );
      // A route can be long enough — or the viewport tall enough — that the
      // framing distance needs more than `_maxDistance`, which would leave the
      // camera past the zoom-out bound until the next pinch clamps it. The
      // drag-zoom path and this one must agree on the valid range, so clamp here
      // rather than teaching the pure framing helper about the universe radius.
      _camera.distance =
          _camera.distance.clamp(kMinZoomDistance, _maxDistance);
    });
  }

  /// The two endpoints of the active voyage, named via the controller (which
  /// knows how to label star destinations and the deep-space pseudo-planet).
  (String, String) _routeEndpoints() {
    final j = _c.activeJourney;
    if (j == null) return ('—', '—');
    return (
      _c.locationLabel(j.originPlanetId),
      _c.locationLabel(j.destinationPlanetId),
    );
  }

  /// Straight-line length of the active voyage, in light-years.
  double _routeLengthLy() {
    final j = _c.activeJourney;
    final scene = _scene;
    if (j == null || scene == null) return 0;
    final from = scene.positionOf(j.originPlanetId);
    final to = scene.positionOf(j.destinationPlanetId);
    return (to - from).length / _worldScale;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StarColors.abyss,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          if (!_initedCamera) _initCamera();
          final scene = _buildScene();
          _scene = scene;
          return LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final vp = Size2(size.width, size.height);
              _maybeEnterRequestedCockpit(vp);
              final endpoints = _routeEndpoints();
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const DecoratedBox(
                    decoration: BoxDecoration(gradient: StarGradients.space),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onTapUp: (d) => _onTapUp(d, size),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _camera.mode == CameraMode.overview
                          ? UniverseOverviewPainter(
                              scene: scene,
                              camera: _camera,
                              shipPosition: _shipPos,
                              universeRadiusLy: _universeRadiusLy,
                              journey: _c.activeJourney,
                              journeyProgress:
                                  _c.activeJourney?.progressAt(_c.now) ?? 0,
                              repaint: _c,
                            )
                          : Galaxy3DPainter(
                              scene: scene,
                              camera: _camera,
                              selectedId: _selectedId,
                              shipPosition: _shipPos,
                              sensorRange: _sensorRange,
                              parkedPlanetId: _c.currentPlanetId,
                              journey: _c.activeJourney,
                              journeyProgress:
                                  _c.activeJourney?.progressAt(_c.now) ?? 0,
                              repaint: _c,
                            ),
                    ),
                  ),
                  // Cockpit framing — a through-the-viewport feel in first
                  // person. Non-interactive so gestures pass through.
                  if (_camera.mode == CameraMode.cockpit) ...<Widget>[
                    const Positioned.fill(
                      child: IgnorePointer(child: _CockpitOverlay()),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: CockpitHudPainter(
                            camera: _camera,
                            markers: _hudMarkers(scene),
                          ),
                        ),
                      ),
                    ),
                  ],
                  _TopBar(controller: _c, mode: _camera.mode),
                  _SideControls(
                    mode: _camera.mode,
                    onSelect: (m) => _setMode(m, vp),
                    onRecenter: () => _recenter(vp),
                  ),
                  if (_camera.mode == CameraMode.overview)
                    _OverviewReadout(
                      radiusLy: _universeRadiusLy,
                      shipDistanceLy: _shipPos.length / _worldScale,
                      hasJourney: _c.activeJourney != null,
                      routeLengthLy: _routeLengthLy(),
                      originLabel: endpoints.$1,
                      destinationLabel: endpoints.$2,
                      onFocusRoute: () => _focusRoute(vp),
                    )
                  else if (_camera.mode == CameraMode.cockpit)
                    _HeadingBar(
                      controller: _c,
                      camera: _camera,
                      onActivate: () => _c.activate(),
                      onIgnite: _igniteFromCockpit,
                      onCorrect: _correctFromCockpit,
                      onBrake: _brakeFromCockpit,
                    )
                  else
                    _BottomControls(
                      sensorRange: _sensorRange,
                      mode: _camera.mode,
                      onSensorChanged: (v) => setState(() => _sensorRange = v),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.mode});
  final GameController controller;
  final CameraMode mode;

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
                const Text('STARWARD',
                    style: TextStyle(
                        color: StarColors.offWhite,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 4)),
                const SizedBox(height: 2),
                Text(
                  switch (mode) {
                    CameraMode.overview => '星图 · 寰宇',
                    CameraMode.orbit => '星图 · 总览',
                    CameraMode.cockpit => '星图 · 座舱视角',
                  },
                  style: const TextStyle(color: StarColors.muted, fontSize: 12),
                ),
              ],
            ),
            EnergyBadge(energy: controller.energy),
          ],
        ),
      ),
    );
  }
}

class _SideControls extends StatelessWidget {
  const _SideControls({
    required this.mode,
    required this.onSelect,
    required this.onRecenter,
  });

  final CameraMode mode;
  final ValueChanged<CameraMode> onSelect;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _RoundButton(
                icon: Icons.blur_circular_rounded,
                label: '寰宇',
                selected: mode == CameraMode.overview,
                onTap: () => onSelect(CameraMode.overview),
              ),
              const SizedBox(height: 10),
              _RoundButton(
                icon: Icons.public_rounded,
                label: '总览',
                selected: mode == CameraMode.orbit,
                onTap: () => onSelect(CameraMode.orbit),
              ),
              const SizedBox(height: 10),
              _RoundButton(
                icon: Icons.flight_rounded,
                label: '座舱',
                selected: mode == CameraMode.cockpit,
                onTap: () => onSelect(CameraMode.cockpit),
              ),
              const SizedBox(height: 12),
              _RoundButton(
                icon: Icons.my_location_rounded,
                // In cockpit mode `placeCamera` only re-pins `eyeOverride` to
                // the ship and never touches the aim — and the aim is what this
                // mode is about, since the reticle at the centre of the screen
                // *is* the heading. The useful "put me back on a known
                // reference" here is therefore to re-aim at the galactic
                // centre, which is why the label changes with the mode.
                label: mode == CameraMode.cockpit ? '对准银心' : '居中',
                onTap: onRecenter,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: panelDecoration(
              radius: 23,
              color: selected ? StarColors.panelLight : null,
              border: selected ? StarColors.cyan.withValues(alpha: 0.75) : null,
            ),
            child: Icon(
              icon,
              color: selected ? StarColors.gold : StarColors.cyan,
              size: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: selected ? StarColors.offWhite : StarColors.muted,
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.sensorRange,
    required this.mode,
    required this.onSensorChanged,
  });

  final double sensorRange;
  final CameraMode mode;
  final ValueChanged<double> onSensorChanged;

  @override
  Widget build(BuildContext context) {
    // Report range in light-years (world units ÷ scale) so it reads physically.
    final ly = (sensorRange / 12).round();
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: StarPanel(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.sensors_rounded,
                        color: StarColors.cyan, size: 16),
                    const SizedBox(width: 8),
                    const Text('飞行器传感器范围',
                        style: TextStyle(
                            color: StarColors.offWhite,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('$ly ly',
                        style: const TextStyle(
                            color: StarColors.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                Slider(
                  value: sensorRange,
                  min: 600,
                  max: 5000,
                  onChanged: onSensorChanged,
                ),
                Text(
                  switch (mode) {
                    CameraMode.overview => '拖动旋转 · 双指缩放',
                    CameraMode.orbit => '拖动旋转 · 双指缩放 · 点击恒星进入星系',
                    CameraMode.cockpit => '拖动环视四周 · 双指调整视场 · 点击恒星进入星系',
                  },
                  style:
                      const TextStyle(color: StarColors.faint, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// First-person cockpit framing: a darkened viewport vignette, a rounded window
/// frame with corner struts, and a faint central reticle — so looking around in
/// cockpit mode feels like peering out of the ship's canopy.
class _CockpitOverlay extends StatelessWidget {
  const _CockpitOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.infinite, painter: _CockpitPainter());
  }
}

class _CockpitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;

    // Vignette: darken the edges so the centre reads as the view out the glass.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.95,
          colors: <Color>[
            const Color(0x00000000),
            const Color(0x00000000),
            StarColors.abyss.withValues(alpha: 0.55),
            StarColors.abyss.withValues(alpha: 0.92),
          ],
          stops: const <double>[0.0, 0.55, 0.85, 1.0],
        ).createShader(rect),
    );

    // Window frame: a rounded rectangle inset from the edges.
    final inset = 14.0;
    final frameRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(inset, inset + 48, w - inset, h - inset - 40),
      const Radius.circular(34),
    );
    canvas.drawRRect(
      frameRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = StarColors.cyan.withValues(alpha: 0.25),
    );
    canvas.drawRRect(
      frameRect.inflate(5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = StarColors.deepNavy.withValues(alpha: 0.45),
    );

    // Corner struts.
    final strut = Paint()
      ..color = StarColors.cyan.withValues(alpha: 0.3)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const s = 34.0;
    final l = frameRect.left + 20, t = frameRect.top + 20;
    final r = frameRect.right - 20, b = frameRect.bottom - 20;
    canvas.drawLine(Offset(l, t), Offset(l + s, t), strut);
    canvas.drawLine(Offset(l, t), Offset(l, t + s), strut);
    canvas.drawLine(Offset(r, t), Offset(r - s, t), strut);
    canvas.drawLine(Offset(r, t), Offset(r, t + s), strut);
    canvas.drawLine(Offset(l, b), Offset(l + s, b), strut);
    canvas.drawLine(Offset(l, b), Offset(l, b - s), strut);
    canvas.drawLine(Offset(r, b), Offset(r - s, b), strut);
    canvas.drawLine(Offset(r, b), Offset(r, b - s), strut);

    // Central reticle.
    final c = Offset(w / 2, h / 2);
    final reticle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = StarColors.cyan.withValues(alpha: 0.35);
    canvas.drawCircle(c, 16, reticle);
    canvas.drawLine(c.translate(-26, 0), c.translate(-16, 0), reticle);
    canvas.drawLine(c.translate(16, 0), c.translate(26, 0), reticle);
    canvas.drawLine(c.translate(0, -26), c.translate(0, -16), reticle);
    canvas.drawLine(c.translate(0, 16), c.translate(0, 26), reticle);
    canvas.drawCircle(c, 1.5, Paint()..color = StarColors.cyan.withValues(alpha: 0.5));
  }

  @override
  bool shouldRepaint(_CockpitPainter oldDelegate) => false;
}

/// How far the ship is from the universe boundary, for the overview readout.
/// Negative distances read as 「壳外 X ly」 rather than as a negative distance.
///
/// That branch is defensive now. When the radius was the 95th percentile of
/// star distances it fired for real — SG-2 sits at 3400 ly, outside a 3066 ly
/// shell — but the shell became the catalogue's bounding radius on 2026-10-13,
/// so a star-spawned ship can no longer be outside it. It survives for the
/// degenerate cases: an empty catalogue (radius 0) puts everything outside, and
/// it is the visible symptom if the containment invariant ever breaks.
String boundaryLabel(double radiusLy, double shipDistanceLy) {
  final toEdge = radiusLy - shipDistanceLy;
  return toEdge >= 0
      ? StarLabels.distance(toEdge)
      : '壳外 ${StarLabels.distance(-toEdge)}';
}

/// The universe-overview readout: the boundary radius, where the ship sits
/// inside it, and — when a voyage is running — the route and a button to frame
/// it. Replaces the sensor slider, whose 50–416 ly range is meaningless at this
/// scale.
class _OverviewReadout extends StatelessWidget {
  const _OverviewReadout({
    required this.radiusLy,
    required this.shipDistanceLy,
    required this.hasJourney,
    required this.routeLengthLy,
    required this.originLabel,
    required this.destinationLabel,
    required this.onFocusRoute,
  });

  final double radiusLy;
  final double shipDistanceLy;
  final bool hasJourney;
  final double routeLengthLy;
  final String originLabel;
  final String destinationLabel;
  final VoidCallback onFocusRoute;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: StarPanel(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.blur_circular_rounded,
                        color: StarColors.gold, size: 16),
                    const SizedBox(width: 8),
                    const Text('宇宙全览',
                        style: TextStyle(
                            color: StarColors.offWhite,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('R ${radiusLy.round()} ly',
                        style: const TextStyle(
                            color: StarColors.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                _ReadoutRow(
                  label: '飞船距球心',
                  value: StarLabels.distance(shipDistanceLy),
                ),
                _ReadoutRow(
                  label: '飞船距边界',
                  // A negative reading must say so rather than print a negative
                  // distance. It is defensive: since the shell became the
                  // catalogue's bounding radius no star-spawned ship can be
                  // outside it, so only an empty catalogue reaches this branch.
                  value: boundaryLabel(radiusLy, shipDistanceLy),
                ),
                if (hasJourney) ...<Widget>[
                  const SizedBox(height: 6),
                  _ReadoutRow(
                    label: '航线 $originLabel→$destinationLabel',
                    value: StarLabels.distance(routeLengthLy),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: onFocusRoute,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: panelDecoration(radius: 99),
                        child: const Text('聚焦航线',
                            style: TextStyle(
                                color: StarColors.cyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                const Text('拖动旋转 · 双指缩放',
                    style: TextStyle(color: StarColors.faint, fontSize: 10.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A label/value line inside the readout panel.
class _ReadoutRow extends StatelessWidget {
  const _ReadoutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: StarColors.muted, fontSize: 11.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
                color: StarColors.offWhite,
                fontSize: 11.5,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// The cockpit's bottom panel: where the reticle is pointing, what it would
/// cost to go there, and the one button that does it.
///
/// Replaces the sensor slider in this mode — a sensor range is a property of
/// the star map's detail level, and the cockpit's question is "which way",
/// which the marker overlay answers better.
class _HeadingBar extends StatelessWidget {
  const _HeadingBar({
    required this.controller,
    required this.camera,
    required this.onActivate,
    required this.onIgnite,
    required this.onCorrect,
    required this.onBrake,
  });

  final GameController controller;
  final Camera3D camera;
  final VoidCallback onActivate;
  final VoidCallback onIgnite;
  final VoidCallback onCorrect;
  final VoidCallback onBrake;

  @override
  Widget build(BuildContext context) {
    final heading = camera.forward;
    final label = headingLabel(heading);
    final dormant = controller.isDormant;
    final moving = controller.hasMomentum;
    final turnCost = controller.turnCostTo(heading);
    final braking = controller.brakingCost;
    // A turn past 60° costs more than stopping and re-lighting the engine, and
    // that is the real Δv, not a pricing mistake — but a player who does not
    // know it is being offered the expensive option first. So say the cheap one
    // out loud, and make it tappable.
    final turningIsDearer = moving && !dormant && turnCost > braking;

    return SafeArea(
      // Keyed because `HomeShell` mounts all four pages in an `IndexedStack`,
      // so an unscoped `find.text` in a widget test matches this bar *and* the
      // voyage tab's dock behind it. The assertions on this bar's own text in
      // `cruise_ui_test.dart` scope to this key.
      key: const Key('cockpit-heading-bar'),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: StarPanel(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.gps_fixed_rounded,
                        color: StarColors.cyan, size: 16),
                    const SizedBox(width: 8),
                    const Text('准星航向',
                        style: TextStyle(
                            color: StarColors.offWhite,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${label.bearing}  ${label.elevation}',
                        style: const TextStyle(
                            color: StarColors.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 10),
                if (dormant)
                  _HudButton(
                    label: '激活引擎',
                    detail: '${controller.ship.engine.activationCost} EN',
                    icon: Icons.power_settings_new_rounded,
                    onPressed: onActivate,
                  )
                else if (!moving)
                  _HudButton(
                    label: '点火巡航',
                    detail: '沿准星方向',
                    icon: Icons.rocket_launch_rounded,
                    onPressed: onIgnite,
                  )
                else
                  _HudButton(
                    label: '修正航向',
                    detail: '$turnCost EN',
                    icon: Icons.alt_route_rounded,
                    onPressed: onCorrect,
                  ),
                if (turningIsDearer) ...<Widget>[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: onBrake,
                    behavior: HitTestBehavior.opaque,
                    child: Text('制动停下只需 $braking EN',
                        style: const TextStyle(
                            color: StarColors.cyan,
                            fontSize: 11,
                            decoration: TextDecoration.underline)),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  switch ((dormant, moving)) {
                    (true, _) => '引擎已休眠，飞船仍在滑行。激活后才能再次点火或改向。',
                    (false, false) => '拖动环视 · 准星所指即点火方向 · 双指调整视场',
                    (false, true) => '拖动环视 · 修正航向不减速，按转角收费 · 双指调整视场',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: StarColors.faint, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A full-width labelled button for the cockpit panel.
class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.label,
    required this.detail,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String detail;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: panelDecoration(radius: 12, color: StarColors.panelLight),
        child: Row(
          children: <Widget>[
            Icon(icon, color: StarColors.cyan, size: 18),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    color: StarColors.offWhite,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(detail,
                style: const TextStyle(
                    color: StarColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}