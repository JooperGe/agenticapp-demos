import 'dart:math' as math;

/// An immutable two-dimensional point or vector.
class Point2 {
  const Point2(this.x, this.y);

  final double x;
  final double y;

  Point2 operator +(Point2 other) => Point2(x + other.x, y + other.y);

  Point2 operator -(Point2 other) => Point2(x - other.x, y - other.y);

  Point2 scaled(double factor) => Point2(x * factor, y * factor);

  double get length => math.sqrt(x * x + y * y);

  Point2 normalized() {
    final magnitude = length;
    if (magnitude == 0) {
      return this;
    }
    return scaled(1 / magnitude);
  }

  @override
  bool operator ==(Object other) {
    return other is Point2 && other.x == x && other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point2($x, $y)';
}
