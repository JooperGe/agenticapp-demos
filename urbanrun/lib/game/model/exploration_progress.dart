import 'scene_model.dart';

class ExplorationProgress {
  ExplorationProgress({this.total = 8}) : assert(total > 0);

  /// Number of enterable interiors that must be visited to be [complete].
  final int total;

  final Set<SceneId> _visitedBuildings = <SceneId>{};

  void visit(SceneId id) {
    if (id != SceneId.street) {
      _visitedBuildings.add(id);
    }
  }

  int get visitedCount => _visitedBuildings.length;

  bool get complete => visitedCount >= total;
}
