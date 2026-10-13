import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'camera3d.dart';

/// Meridians (longitude lines) drawn on the shell.
const int kShellMeridians = 12;

/// Parallels (latitude lines) drawn on the shell, three per hemisphere.
const int kShellParallels = 6;

/// Segments per meridian polyline (inclusive of both endpoints, so the loop
/// closes).
const int kShellMeridianSegments = 32;

/// Segments per parallel polyline.
const int kShellParallelSegments = 48;

/// The shell's graticule, split by which side of the centre plane each vertex
/// falls on: a vertex is on the far side when `dot(P - centre, forward) < 0`.
class ShellLattice {
  const ShellLattice({required this.far, required this.near});

  /// Polylines on the far side of the centre plane — drawn *before* the star
  /// field, so the stars occlude them.
  final List<List<Vec3>> far;

  /// Polylines on the near side — drawn *after* the star field, so they sit in
  /// front of it. This two-pass split is what makes the globe read as hollow
  /// rather than as a ball the stars are painted onto.
  final List<List<Vec3>> near;
}

/// Builds the meridian/parallel graticule of a sphere of [radius] centred on
/// [centre], split into far and near halves by the plane through [centre]
/// perpendicular to [forward].
///
/// The polar axis is [Vec3.up] (the catalogue's north celestial pole).
ShellLattice buildShellLattice({
  required Vec3 centre,
  required double radius,
  required Vec3 forward,
  int meridians = kShellMeridians,
  int parallels = kShellParallels,
}) {
  final far = <List<Vec3>>[];
  final near = <List<Vec3>>[];

  // A polyline is cut into maximal runs of same-side vertices, so a great
  // circle crossing the plane twice contributes one run to each half. Runs are
  // never split mid-edge, which is what keeps a drawn segment from jumping
  // across the split.
  void emit(List<Vec3> pts) {
    var run = <Vec3>[];
    bool? runFar;
    void flush() {
      if (run.isNotEmpty) (runFar! ? far : near).add(run);
      run = <Vec3>[];
    }

    for (final p in pts) {
      final isFar = (p - centre).dot(forward) < 0;
      if (runFar != null && isFar != runFar) flush();
      runFar = isFar;
      run.add(p);
    }
    flush();
  }

  // Meridians: great circles through both poles.
  for (var j = 0; j < meridians; j++) {
    final phi = j * 2 * math.pi / meridians;
    final ux = math.cos(phi), uz = math.sin(phi);
    final pts = <Vec3>[];
    for (var s = 0; s <= kShellMeridianSegments; s++) {
      final t = s * 2 * math.pi / kShellMeridianSegments;
      final c = math.cos(t), sn = math.sin(t);
      pts.add(centre + Vec3(radius * c * ux, radius * sn, radius * c * uz));
    }
    emit(pts);
  }

  // Parallels: small circles at fixed latitude, three per hemisphere.
  for (var k = 0; k < parallels; k++) {
    final lambda = -math.pi / 2 + (k + 1) * math.pi / (parallels + 1);
    final sinL = math.sin(lambda), cosL = math.cos(lambda);
    final pts = <Vec3>[];
    for (var s = 0; s <= kShellParallelSegments; s++) {
      final psi = s * 2 * math.pi / kShellParallelSegments;
      pts.add(centre +
          Vec3(radius * cosL * math.cos(psi), radius * sinL,
              radius * cosL * math.sin(psi)));
    }
    emit(pts);
  }

  return ShellLattice(far: far, near: near);
}

/// A hollow sphere of [radius] centred on [centre], its graticule split into a
/// far and a near half by the camera's forward direction.
///
/// Only meaningful while the camera is outside the sphere; callers gate on
/// [shellFade] before constructing one.
class UniverseShell {
  UniverseShell({
    required this.centre,
    required this.radius,
    required Vec3 forward,
  }) : lattice = buildShellLattice(
          centre: centre,
          radius: radius,
          forward: forward,
        );

  final Vec3 centre;
  final double radius;
  final ShellLattice lattice;

  /// The shell's limb radius in pixels, or [double.infinity] when the eye is at
  /// or inside the sphere.
  double limbRadius(Camera3D camera, Size2 viewport) => limbScreenRadius(
        radius: radius,
        distance: (camera.eye - centre).length,
        viewport: viewport,
        fovDegrees: camera.fovDegrees,
      );

  /// Draws the far half. Call *before* the star field.
  void paintFarHalf(
    Canvas canvas, {
    required Camera3D camera,
    required Size2 viewport,
    required double fade,
  }) {
    _paintFill(canvas, camera, viewport, fade, alphaScale: 0.05);
    _paintLattice(canvas, camera, viewport, fade, lattice.far);
  }

  /// Draws the near half. Call *after* the star field.
  void paintNearHalf(
    Canvas canvas, {
    required Camera3D camera,
    required Size2 viewport,
    required double fade,
  }) {
    _paintLattice(canvas, camera, viewport, fade, lattice.near);
    _paintFill(canvas, camera, viewport, fade, alphaScale: 0.04);
    _paintLimb(canvas, camera, viewport, fade);
  }

  void _paintLattice(
    Canvas canvas,
    Camera3D camera,
    Size2 viewport,
    double fade,
    List<List<Vec3>> runs,
  ) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = StarColors.cyan.withValues(alpha: 0.16 * fade);
    for (final run in runs) {
      if (run.length < 2) continue;
      final path = Path();
      var started = false;
      for (final p in run) {
        final pr = camera.project(p, viewport);
        if (!pr.visible) {
          started = false;
          continue;
        }
        if (started) {
          path.lineTo(pr.screen.dx, pr.screen.dy);
        } else {
          path.moveTo(pr.screen.dx, pr.screen.dy);
          started = true;
        }
      }
      canvas.drawPath(path, stroke);
    }
  }

  /// A faint disc of "glass" inside the limb. The far half is drawn before the
  /// stars and the near half after, which gives the globe a body without
  /// washing the star field out — hence the deliberately tiny alphas.
  void _paintFill(
    Canvas canvas,
    Camera3D camera,
    Size2 viewport,
    double fade, {
    required double alphaScale,
  }) {
    final alpha = alphaScale * fade;
    if (alpha <= 0) return;
    final limb = limbRadius(camera, viewport);
    if (!limb.isFinite) return;
    final projectedCentre = camera.project(centre, viewport);
    if (!projectedCentre.visible) return;
    final rect = Rect.fromCircle(center: projectedCentre.screen, radius: limb);
    canvas.drawCircle(
      projectedCentre.screen,
      limb,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            StarColors.violet.withValues(alpha: alpha * 0.6),
            StarColors.deepNavy.withValues(alpha: alpha),
            StarColors.cyan.withValues(alpha: alpha * 1.4),
          ],
          stops: const <double>[0.0, 0.72, 1.0],
        ).createShader(rect),
    );
  }

  /// The silhouette itself, so the sphere reads as an edge even when the fill
  /// is almost invisible.
  void _paintLimb(
    Canvas canvas,
    Camera3D camera,
    Size2 viewport,
    double fade,
  ) {
    final limb = limbRadius(camera, viewport);
    if (!limb.isFinite) return;
    final projectedCentre = camera.project(centre, viewport);
    if (!projectedCentre.visible) return;
    canvas.drawCircle(
      projectedCentre.screen,
      limb,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = StarColors.cyan.withValues(alpha: 0.22 * fade),
    );
  }
}
