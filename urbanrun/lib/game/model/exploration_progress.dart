import 'scene_model.dart';

class ExplorationProgress {
  final Set<SceneId> _visitedBuildings = <SceneId>{};

  void visit(SceneId id) {
    if (id != SceneId.street) {
      _visitedBuildings.add(id);
    }
  }

  int get visitedCount => _visitedBuildings.length;

  bool get complete => visitedCount >= 2;
}
