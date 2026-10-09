import 'package:flutter_test/flutter_test.dart';
import 'package:urbanrun/game/model/exploration_progress.dart';
import 'package:urbanrun/game/model/scene_model.dart';

void main() {
  test('counts unique visited buildings and completes at exactly two', () {
    final progress = ExplorationProgress();

    progress.visit(SceneId.coffeeShop);
    progress.visit(SceneId.coffeeShop);

    expect(progress.visitedCount, 1);
    expect(progress.complete, isFalse);

    progress.visit(SceneId.convenienceStore);
    progress.visit(SceneId.street);

    expect(progress.visitedCount, 2);
    expect(progress.complete, isTrue);
  });
}
