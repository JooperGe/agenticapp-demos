import 'dart:math' as math;

/// Minimal 3D vector shared by the projection pipeline and the star catalogue.
/// Kept dependency-light (no vector_math) and in core so both data and UI
/// layers can use it without a UI→data or data→UI dependency.
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) =>
      Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);

  double get length => math.sqrt(x * x + y * y + z * z);
  Vec3 get normalized {
    final l = length;
    return l == 0 ? const Vec3(0, 0, 0) : Vec3(x / l, y / l, z / l);
  }

  static const Vec3 up = Vec3(0, 1, 0);
}
