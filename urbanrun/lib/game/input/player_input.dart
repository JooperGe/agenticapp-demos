import '../model/geometry.dart';
import '../projection/iso_projection.dart';

class PlayerInput {
  final Set<String> _held = <String>{};
  bool _interactionConsumedForPress = false;

  Point2 get screenDirection {
    var x = 0.0;
    var y = 0.0;
    if (_isHeld('a') || _isHeld('arrowleft')) x -= 1;
    if (_isHeld('d') || _isHeld('arrowright')) x += 1;
    if (_isHeld('w') || _isHeld('arrowup')) y -= 1;
    if (_isHeld('s') || _isHeld('arrowdown')) y += 1;
    return Point2(x, y);
  }

  bool get running =>
      _isHeld('shift') || _isHeld('shiftleft') || _isHeld('shiftright');

  void press(String key) {
    final normalized = key.toLowerCase();
    if (_held.add(normalized) && normalized == 'e') {
      _interactionConsumedForPress = false;
    }
  }

  void keyDown(String key) => press(key);

  void release(String key) {
    _held.remove(key.toLowerCase());
  }

  void keyUp(String key) => release(key);

  Point2 groundDirection(IsoProjection projection) {
    final screen = screenDirection;
    if (screen.length == 0) return screen;
    return projection.screenToWorld(screen).normalized();
  }

  bool consumeInteraction() {
    if (!_isHeld('e') || _interactionConsumedForPress) return false;
    _interactionConsumedForPress = true;
    return true;
  }

  void clear() {
    _held.clear();
    _interactionConsumedForPress = false;
  }

  bool _isHeld(String key) => _held.contains(key);
}
