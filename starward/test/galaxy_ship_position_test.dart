import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/game_repository.dart';
import 'package:starward/data/storage/storage_backend.dart';
import 'package:starward/state/game_controller.dart';
import 'package:starward/ui/game_scope.dart';
import 'package:starward/ui/shell/home_shell.dart';
import 'package:starward/ui/widgets/common.dart';

/// The star map must draw the ship where it *is*, not where its drift started.
///
/// `deepSpaceOrigin3D` is the drift anchor: it only ever changes on a launch or
/// an arrival. A coasting ship moves away from it every second, so anything on
/// the map that reads the anchor freezes for the whole coast — which is what the
/// universe-overview readout ("飞船距球心") was doing.
class FakeClock {
  FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

Future<GameController> _boot(FakeClock clock, MemoryStorage storage) async {
  final c = GameController(
    repository: GameRepository(storage),
    clock: clock.call,
    random: math.Random(3),
  );
  await c.init();
  return c;
}

void main() {
  testWidgets('the star map reports the coasting ship, not its drift anchor',
      (tester) async {
    final clock = FakeClock(DateTime(2026));
    final storage = MemoryStorage();

    // The anchor is whatever the spawn strategy picked; read it rather than
    // guessing, then hand the ship a drift straight out from the origin at
    // 1 ly/s so the expected distance is the anchor's plus the elapsed seconds.
    final c1 = await _boot(clock, storage);
    final anchor = c1.deepSpaceOrigin3D!;
    expect(anchor.length, greaterThan(0),
        reason: 'the spawn must not sit on the origin, or "outward" is undefined');

    final raw = await storage.read('starward.save.v2');
    final json = jsonDecode(raw!) as Map<String, dynamic>;
    final player = json['player'] as Map<String, dynamic>;
    final outward = anchor.normalized;
    player['driftVelocityX'] = outward.x;
    player['driftVelocityY'] = outward.y;
    player['driftVelocityZ'] = outward.z;
    player['driftStartedAt'] = clock().millisecondsSinceEpoch;
    await storage.write('starward.save.v2', jsonEncode(json));

    final c = await _boot(clock, storage);
    expect(c.isCoasting, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScope(controller: c, child: const HomeShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // The readout lives in the universe overview, which is the map view that
    // has the scale to show a 144 ly ship at all.
    await tester.tap(find.text('寰宇'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('飞船距球心'), findsOneWidget);
    expect(
      find.text(StarLabels.distance(anchor.length)),
      findsOneWidget,
      reason: 'at t=0 the ship is still at its anchor',
    );

    // Ten seconds of coasting at 1 ly/s straight outward: +10 ly, and under the
    // 20 ly threshold that would trigger a nearby-set rescan.
    clock.advance(const Duration(seconds: 10));
    c.tick();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text(StarLabels.distance(anchor.length + 10)),
      findsOneWidget,
      reason: 'the readout must follow the ship, not the anchor it left behind',
    );
  });
}
