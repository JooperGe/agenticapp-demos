import 'package:flutter_test/flutter_test.dart';
import 'package:urbanrun/game/model/exploration_progress.dart';
import 'package:urbanrun/game/model/scene_model.dart';

void main() {
  test('counts unique visited buildings and ignores the street', () {
    final progress = ExplorationProgress(total: 2);

    progress.visit(SceneId.coffeeShop);
    progress.visit(SceneId.coffeeShop);

    expect(progress.visitedCount, 1);
    expect(progress.complete, isFalse);

    progress.visit(SceneId.convenienceStore);
    progress.visit(SceneId.street);

    expect(progress.visitedCount, 2);
    expect(progress.complete, isTrue);
  });

  test('completes only when every enterable interior is visited', () {
    final progress = ExplorationProgress(total: 8);
    const interiors = <SceneId>[
      SceneId.coffeeShop,
      SceneId.convenienceStore,
      SceneId.officeA,
      SceneId.officeB,
      SceneId.residentialA,
      SceneId.residentialB,
      SceneId.cornerShopA,
      SceneId.cornerShopB,
    ];

    for (var i = 0; i < interiors.length; i++) {
      expect(progress.complete, isFalse, reason: 'not complete before all 8');
      progress.visit(interiors[i]);
      expect(progress.visitedCount, i + 1);
    }

    expect(progress.visitedCount, 8);
    expect(progress.complete, isTrue);
  });
}
