import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/planet.dart';
import '../../state/game_controller.dart';
import '../galaxy/planet_details_sheet.dart';
import '../game_scope.dart';
import '../shell/shell_scope.dart';
import '../widgets/common.dart';
import 'camera3d.dart';
import 'galaxy3d_painter.dart';
import 'galaxy3d_scene.dart';

/// Page 1 (3D) — the galaxy as a real, rotatable, zoomable volume rendered by
/// projecting a 3D scene onto a 2D canvas. Drag to orbit, pinch to zoom, toggle
/// between the star-map overview and the first-person cockpit, and adjust the
/// ship's sensor range (the per-ship "view range" hook for future upgrades).
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

  /// The ship's 3D world position: its planet when docked, otherwise the
  /// randomised deep-space drift coordinate (scaled into world units).
  Vec3 get _shipPos {
    final origin = _c.deepSpaceOrigin3D;
    if (origin != null) return origin * _worldScale;
    final planet = _c.currentPlanet;
    if (planet == null) return const Vec3(0, 0, 0);
    return planet.pos * _worldScale;
  }

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
      const k = 0.006;
      if (_camera.mode == CameraMode.orbit) {
        _camera.yaw -= delta.dx * k;
        _camera.pitch += delta.dy * k;
      } else {
        // Cockpit: look around (invert so dragging feels like turning the view).
        _camera.yaw -= delta.dx * k;
        _camera.pitch -= delta.dy * k;
      }
      _camera.clampPitch();

      // Zoom from pinch: orbit changes distance, cockpit changes FOV.
      if (d.scale != 1.0) {
        final factor = d.scale / _lastScale;
        _lastScale = d.scale;
        if (_camera.mode == CameraMode.orbit) {
          _camera.distance = (_camera.distance / factor).clamp(70.0, 1800.0);
        } else {
          _camera.fovDegrees = (_camera.fovDegrees / factor).clamp(30.0, 95.0);
        }
      }
    });
  }

  void _onTapUp(TapUpDetails d, Size size) {
    final scene = _scene;
    if (scene == null) return;
    final id = pickPlanet(
      scene: scene,
      camera: _camera,
      size: size,
      tap: d.localPosition,
      shipPosition: _shipPos,
      sensorRange: _sensorRange,
    );
    if (id == null) return;
    final planet = _c.planetById(id);
    if (planet == null) return;
    setState(() => _selectedId = id);
    _openDetails(planet);
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

  void _toggleMode() {
    setState(() {
      if (_camera.mode == CameraMode.orbit) {
        _camera.mode = CameraMode.cockpit;
        _camera.eyeOverride = _shipPos;
        // Aim the cockpit toward the galactic centre (origin) initially.
        final dir = (const Vec3(0, 0, 0) - _shipPos).normalized;
        _camera.yaw = math.atan2(dir.x, dir.z);
        _camera.pitch = math.asin(dir.y.clamp(-1.0, 1.0)) * 0.6;
        _camera.clampPitch();
      } else {
        _camera.mode = CameraMode.orbit;
        _camera.target = _shipPos;
        _camera.distance = 520;
      }
    });
  }

  void _recenter() {
    setState(() {
      if (_camera.mode == CameraMode.orbit) {
        _camera.target = _shipPos;
      } else {
        _camera.eyeOverride = _shipPos;
      }
    });
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
                      painter: Galaxy3DPainter(
                        scene: scene,
                        camera: _camera,
                        selectedId: _selectedId,
                        shipPosition: _shipPos,
                        sensorRange: _sensorRange,
                        journey: _c.activeJourney,
                        journeyProgress:
                            _c.activeJourney?.progressAt(_c.now) ?? 0,
                        repaint: _c,
                      ),
                    ),
                  ),
                  _TopBar(controller: _c, mode: _camera.mode),
                  _SideControls(
                    mode: _camera.mode,
                    onToggleMode: _toggleMode,
                    onRecenter: _recenter,
                  ),
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
                  mode == CameraMode.orbit ? '星图 · 总览' : '星图 · 座舱视角',
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
    required this.onToggleMode,
    required this.onRecenter,
  });

  final CameraMode mode;
  final VoidCallback onToggleMode;
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
                icon: mode == CameraMode.orbit
                    ? Icons.flight_rounded
                    : Icons.public_rounded,
                label: mode == CameraMode.orbit ? '座舱' : '总览',
                onTap: onToggleMode,
              ),
              const SizedBox(height: 12),
              _RoundButton(
                icon: Icons.my_location_rounded,
                label: '居中',
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
  const _RoundButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: panelDecoration(radius: 23),
            child: Icon(icon, color: StarColors.cyan, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(color: StarColors.muted, fontSize: 10)),
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
                  mode == CameraMode.orbit
                      ? '拖动旋转 · 双指缩放 · 点击星球查看详情'
                      : '拖动环视四周 · 双指调整视场 · 点击星球查看详情',
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