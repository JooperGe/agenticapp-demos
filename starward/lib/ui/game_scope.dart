import 'package:flutter/widgets.dart';

import '../state/game_controller.dart';

/// Exposes the single [GameController] to the widget tree and rebuilds
/// dependents when it notifies. Keeps us dependency-free (no provider package)
/// while still giving `GameScope.of(context)` ergonomics.
class GameScope extends InheritedNotifier<GameController> {
  const GameScope({
    super.key,
    required GameController controller,
    required super.child,
  }) : super(notifier: controller);

  static GameController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<GameScope>();
    assert(scope != null, 'GameScope not found in widget tree');
    return scope!.notifier!;
  }

  /// Read the controller without subscribing to rebuilds — use in callbacks.
  static GameController read(BuildContext context) {
    final scope =
        context.getInheritedWidgetOfExactType<GameScope>();
    assert(scope != null, 'GameScope not found in widget tree');
    return scope!.notifier!;
  }
}
