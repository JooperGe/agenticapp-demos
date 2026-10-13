import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/journey.dart';
import 'camera3d.dart';
import 'galaxy3d_scene.dart';
import 'star_field_painter.dart';
import 'universe_shell.dart';

/// The universe seen from outside its own boundary: the hollow shell of
/// `universeRadius` with the whole catalogue inside it.
///
/// Differs from Galaxy3DPainter in four ways, all deliberate:
/// - draws the shell, split so the star field sits between its two halves;
/// - **no** magnitude distance-rescale (from out here it would black the sky);
/// - no planets, no host-star bloom, no phase shadow — local concepts that are
///   sub-pixel at this scale;
/// - keeps the route at true scale, so it is invisible at full framing and the
///   readout bar offers a "focus route" framing instead.
class UniverseOverviewPainter extends CustomPainter {
  UniverseOverviewPainter({
    required this.scene,
    required this.camera,
    required this.shipPosition,
    required this.universeRadiusLy,
    required this.journey,
    required this.journeyProgress,
    required this.repaint,
  }) : super(repaint: repaint);

  final Galaxy3DScene scene;
  final Camera3D camera;
  final Vec3 shipPosition;
  final double universeRadiusLy;
  final Journey? journey;
  final double journeyProgress;
  final Listenable repaint;

  /// Draw cap for the catalogue. At full framing nearly every star lands on
  /// screen, so this bounds both density and cost; it is a tuning knob, not a
  /// design promise (see the spec's §6.3). The synthetic galaxies get
  /// [kGalaxyMaxDraw] instead, because clipping one distorts the thing the
  /// view is showing.
  static const int _hygMaxDraw = 5000;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = Size2(size.width, size.height);
    final ws = scene.worldScale;
    final rWorld = universeRadiusLy * ws;
    const centre = Vec3(0, 0, 0);
    final fade = shellFade(
      radius: rWorld,
      distance: (camera.eye - centre).length,
    );

    // ① Far half of the shell — behind the stars.
    UniverseShell? shell;
    if (fade > 0) {
      shell = UniverseShell(
        centre: centre,
        radius: rWorld,
        forward: camera.forward,
      );
      shell.paintFarHalf(canvas, camera: camera, viewport: vp, fade: fade);
    }

    // ② The star field, between the two halves.
    final hyg = scene.hyg;
    if (hyg != null) {
      drawStarField(
        canvas,
        size: size,
        field: hyg,
        camera: camera,
        worldScale: ws,
        maxDraw: _hygMaxDraw,
        distanceScaled: false,
      );
    }
    for (final g in scene.extraGalaxies) {
      drawStarField(
        canvas,
        size: size,
        field: g,
        camera: camera,
        worldScale: ws,
        maxDraw: kGalaxyMaxDraw,
        distanceScaled: false,
      );
    }

    // ③ Near half — in front of the stars, which is what makes it read hollow.
    if (shell != null) {
      shell.paintNearHalf(canvas, camera: camera, viewport: vp, fade: fade);
    }

    // ④ Landmarks, the route at true scale, then the ship.
    if (hyg != null) {
      drawFieldLabels(
        canvas,
        size: size,
        field: hyg,
        camera: camera,
        worldScale: ws,
        distanceScaled: false,
      );
    }
    for (final g in scene.extraGalaxies) {
      drawFieldLabels(
        canvas,
        size: size,
        field: g,
        camera: camera,
        worldScale: ws,
        distanceScaled: false,
      );
    }
    _drawRoute(canvas, vp);
    _drawShip(canvas, vp);
  }

  void _drawRoute(Canvas canvas, Size2 vp) {
    final j = journey;
    if (j == null) return;
    final from = scene.positionOf(j.originPlanetId);
    final to = scene.positionOf(j.destinationPlanetId);
    final pf = camera.project(from, vp);
    final pt = camera.project(to, vp);
    if (!pf.visible || !pt.visible) return;
    canvas.drawLine(
      pf.screen,
      pt.screen,
      Paint()
        ..color = StarColors.cyan.withValues(alpha: 0.6)
        ..strokeWidth = 1.5,
    );
    final marker = Offset.lerp(pf.screen, pt.screen, journeyProgress)!;
    canvas.drawCircle(marker, 4, Paint()..color = StarColors.gold);
  }

  void _drawShip(Canvas canvas, Size2 vp) {
    // Unlike the star map there is no cockpit case to skip: the overview camera
    // is never the ship, so the marker always belongs on screen.
    final pr = camera.project(shipPosition, vp);
    if (!pr.visible) return;
    canvas.drawCircle(pr.screen, 5, Paint()..color = StarColors.offWhite);
    canvas.drawCircle(
      pr.screen,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = StarColors.cyan,
    );
  }

  @override
  bool shouldRepaint(UniverseOverviewPainter old) => true;
}
