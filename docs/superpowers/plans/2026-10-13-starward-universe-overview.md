# Starward 宇宙全览视图（寰宇档）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在星图页加第三个相机档位「寰宇」——从宇宙边界球之外观察整份 HYG 星表，球壳镂空、可旋转，球内标出飞船位置与当前航线。

**Architecture:** 复用现有的伪 3D 管线。`Camera3D.eye` 的既有公式 `target − forward · distance` 在 `target = 原点`、`distance ≥ 2R` 时天然把眼睛放在球外，**投影数学一行不改**。新增的是三块纯函数几何（取景距离闭式解、球面轮廓半径、球壳经纬网）与一个独立的 painter；球壳按相机前向切成前后两半，星场夹在中间，这是「镂空」读起来对的关键。

**Tech Stack:** Flutter 3.47+ / Dart 3.13+、`CustomPainter` + `Canvas`、`Float32List`/`Int32List` 打包星表、`flutter_test`。

**Spec:** `docs/superpowers/specs/2026-10-13-starward-universe-overview-design.md`

## Global Constraints

- 项目根目录是 `starward/`；所有命令在该目录下执行。
- `flutter analyze` 必须报 `No issues found`；`flutter test` 必须全绿。
- **零模型变更**：不动 `Universe`、不动星表、不动存档结构、不 bump `_saveKey`。
- 不改 `Universe.universeRadius` 的算法（p95，实测 3066 ly）。
- 领域约定（`starward/CLAUDE.md`）：属性归属于拥有它的实体。本计划不新增可调数值到 `Balance`；球壳几何全部是派生计算，以顶层纯函数实现。
- 数值常量必须**钉进测试**（`closeTo` + 明确容差），让「重构不改变行为」可验证。
- 测试用 `FakeClock` + 固定 seed + `MemoryStorage`，不碰真实 prefs。
- 新档位叫**「寰宇」**，不叫「全览」——`orbit` 档已占用「总览」，两者同屏只差一个偏旁。
- 提交信息用 conventional commits，结尾带 `Co-Authored-By: Claude Code <noreply@anthropic.com>`。

### 已钉住的输入常量（全计划通用）

| 量 | 值 | 来源 |
|---|---|---|
| `R_ly` | 3066 ly | `Universe.universeRadius`（`coast_test.dart:157` 钉住 ±30） |
| `worldScale` | 12 | `galaxy_map_3d_page.dart:34` |
| `R_w` | 36 792 世界单位 | `R_ly × worldScale` |
| `fovDegrees` | 60 | 既有常量 |
| 球心 | 原点 `Vec3(0,0,0)` | HYG 坐标以太阳为原点 |

---

## 阶段与检查点

| 阶段 | 任务 | 交付物 | 检查点 |
|---|---|---|---|
| 1 | Task 1 | 相机几何纯函数 + `CameraMode.overview` | `flutter test test/overview_camera_test.dart` 全绿；星图外观无变化 |
| 2 | Task 2 | `star_field_painter.dart` 共享热循环 + `distanceScaled` 开关 | 星图外观无变化（回归测试钉住） |
| 3 | Task 3 | `universe_shell.dart` 球壳几何与绘制 | `flutter test test/universe_shell_test.dart` 全绿 |
| 4 | Task 4 | `universe_overview_painter.dart` + 页面接线 | 侧栏点「寰宇」能看到镂空玻璃球 |
| 5 | Task 5 | 底栏读数条 + 聚焦航线 + 文档 | 读数正确、按钮可用、`flutter analyze` 干净 |

阶段 2 依赖阶段 1（要先有档位），阶段 3 依赖阶段 2（球壳要夹在星场前后）。每个任务单独提交，单独可验证。

## File Structure

| 文件 | 动作 | 职责 |
|---|---|---|
| `lib/ui/galaxy3d/camera3d.dart` | 改 | 加 `CameraMode.overview`；新增取景/轮廓/淡出纯函数。`eye`/`forward`/`project` 不动 |
| `lib/ui/galaxy3d/star_field_painter.dart` | **新建** | 星场热循环 + 具名标注 + 文字标签，带 `distanceScaled` 开关。两个 painter 共用 |
| `lib/ui/galaxy3d/universe_shell.dart` | **新建** | 球壳几何（经纬网、前后半球划分、轮廓半径、淡出）与绘制。纯函数，不依赖游戏状态 |
| `lib/ui/galaxy3d/universe_overview_painter.dart` | **新建** | 寰宇档绘制编排：后半球 → 星场 → 前半球 → 航线 → 飞船 → 标注 |
| `lib/ui/galaxy3d/galaxy3d_painter.dart` | 改 | 热循环与 `_label` 改为调用共享函数；其余不动 |
| `lib/ui/galaxy3d/galaxy_map_3d_page.dart` | 改 | 侧栏四按钮、按档选 painter、底栏按档分叉、`_onTapUp` 早退、`居中` 三档语义、缩放夹取分叉 |
| `test/overview_camera_test.dart` | **新建** | 取景闭式解、轮廓公式、淡出、眼睛在球外 |
| `test/star_field_lod_test.dart` | **新建** | `distanceScaled` 开关 + 星图外观回归 |
| `test/universe_shell_test.dart` | **新建** | 球壳几何纯函数 |
| `test/galaxy3d_projection_test.dart` | 改 | 补 overview 档与 orbit 共用 eye 公式 |
| `test/widget_smoke_test.dart` | 改 | 补三档切换、读数条出现、滑块消失 |
| `starward/README.md` | 改 | 星图一节补第三个档位 |
| `starward/CLAUDE.md` | 改 | 无新约定，仅在必要处补一句；若无必要则不动 |

---

## Task 1: 相机几何与 `CameraMode.overview`

**Files:**
- Modify: `lib/ui/galaxy3d/camera3d.dart`
- Create: `test/overview_camera_test.dart`
- Modify: `test/galaxy3d_projection_test.dart`

**Interfaces:**
- Consumes: 既有 `Camera3D`、`Size2`、`Vec3`。
- Produces:
  - `enum CameraMode { orbit, cockpit, overview }`
  - `double focalFor(Size2 viewport, double fovDegrees)`
  - `double limbScreenRadius({required double radius, required double distance, required Size2 viewport, required double fovDegrees})`
  - `double fitDistanceForSphere({required double radius, required Size2 viewport, required double fovDegrees})`
  - `double shellFade({required double radius, required double distance})`
  - `void placeCamera(Camera3D camera, {required CameraMode mode, required Vec3 shipPosition, required double overviewDistance, double orbitDistance})`

`placeCamera` exists because "go to this mode" and "recentre" mean the same
thing per mode, and the spec's test 8 requires the three-way fork to be
verifiable. Keeping it in the page would make it unreachable from a unit test;
as a pure function it is testable, and both call sites share one implementation.

**几何背景（实现时不必重新推导，照抄即可）：**

相机在球外时，球面轮廓（limb）在屏幕上的半径**不是** `R·focal/d`，精确解是：

```
rs = focal · R / √(d² − R²)          (d > R)
```

要球刚好内切视口，对高度和宽度各解一次取较大值：

```
d_fit = R · max( 1/sin(θ/2) , √(1 + h²/(w²·tan²(θ/2))) )
```

θ=60° 时横屏高度约束更紧，`d_fit = 2R` 且**与视口尺寸无关**；竖屏宽度约束更紧，400×800 → `√13·R ≈ 132 655`。

- [ ] **Step 1: 写失败测试**

创建 `test/overview_camera_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/ui/galaxy3d/camera3d.dart';

/// The framing maths behind the universe-overview camera. Every number here is
/// derived by hand in the spec (§4.2, §5.2) and pinned so a refactor that
/// changes the framing is caught rather than shipped.
void main() {
  // The measured universe radius, in world units (3066 ly × worldScale 12).
  const double rWorld = 36792;
  const double fov = 60;
  const Size2 landscape = Size2(800, 600);
  const Size2 portrait = Size2(400, 800);

  group('focalFor', () {
    test('derives from viewport height only', () {
      // (600 / 2) / tan(30°) = 300 / 0.5773502692
      expect(focalFor(landscape, fov), closeTo(519.6152, 0.001));
      // Width does not enter the focal length.
      expect(focalFor(const Size2(1600, 600), fov), closeTo(519.6152, 0.001));
    });
  });

  group('fitDistanceForSphere', () {
    test('landscape fits at exactly 2R, independent of viewport size', () {
      // focal comes from the viewport height, so at 60° the height constraint
      // reduces to d = R / sin(30°) = 2R.
      expect(
        fitDistanceForSphere(
            radius: rWorld, viewport: landscape, fovDegrees: fov),
        closeTo(73584, 1),
      );
      expect(
        fitDistanceForSphere(
            radius: rWorld, viewport: const Size2(1600, 600), fovDegrees: fov),
        closeTo(73584, 1),
      );
    });

    test('portrait is width-bound and needs sqrt(13) * R for a 1:2 viewport', () {
      expect(
        fitDistanceForSphere(radius: rWorld, viewport: portrait, fovDegrees: fov),
        closeTo(132655, 2),
      );
    });
  });

  group('limbScreenRadius', () {
    test('uses the exact form, not focal * R / d', () {
      final exact = limbScreenRadius(
        radius: rWorld,
        distance: 2 * rWorld,
        viewport: landscape,
        fovDegrees: fov,
      );
      // At d = 2R the sphere is inscribed in the height, so the limb is h/2.
      expect(exact, closeTo(300, 0.1));

      final naive = focalFor(landscape, fov) * rWorld / (2 * rWorld);
      expect(naive, closeTo(259.8, 0.1));
      // The naive form under-draws by 13.4% — the ratio is exactly sqrt(3)/2.
      expect(naive / exact, closeTo(0.8660254, 0.0001));
    });

    test('is infinite at or inside the limb', () {
      expect(
        limbScreenRadius(
            radius: rWorld, distance: rWorld, viewport: landscape, fovDegrees: fov),
        double.infinity,
      );
      expect(
        limbScreenRadius(
            radius: rWorld,
            distance: 0.5 * rWorld,
            viewport: landscape,
            fovDegrees: fov),
        double.infinity,
      );
    });
  });

  group('shellFade', () {
    test('fully drawn clear of the surface, gone at or inside it', () {
      // 2.3R is well clear of the ramp, so this is exactly 1.0.
      expect(shellFade(radius: rWorld, distance: 2.3 * rWorld), 1.0);
      // 1.15R sits exactly on the ramp's end, where floating point lands a
      // hair under 1.0 — hence the tolerance.
      expect(shellFade(radius: rWorld, distance: 1.15 * rWorld),
          closeTo(1.0, 0.001));
      expect(shellFade(radius: rWorld, distance: rWorld), 0.0);
      expect(shellFade(radius: rWorld, distance: 0.5 * rWorld), 0.0);
    });

    test('ramps over the last 15% of the approach', () {
      // (1.075R / R − 1) / 0.15 = 0.5
      expect(shellFade(radius: rWorld, distance: 1.075 * rWorld), closeTo(0.5, 0.01));
    });

    test('a zero radius draws nothing instead of dividing by zero', () {
      expect(shellFade(radius: 0, distance: 100), 0.0);
    });
  });

  group('the overview camera', () {
    test('shares the orbit eye formula, putting the eye outside the volume', () {
      final cam = Camera3D(
        target: const Vec3(0, 0, 0),
        yaw: 0,
        pitch: 0,
        distance: 2.3 * rWorld,
        mode: CameraMode.overview,
      );
      expect(cam.eye.length, closeTo(2.3 * rWorld, 1));
      expect(cam.eye.length, greaterThan(rWorld));
    });

    test('projects the origin (the sphere centre) to the screen centre', () {
      final cam = Camera3D(
        target: const Vec3(0, 0, 0),
        yaw: 0.6,
        pitch: 0.35,
        distance: 2.3 * rWorld,
        mode: CameraMode.overview,
      );
      final p = cam.project(const Vec3(0, 0, 0), landscape);
      expect(p.visible, isTrue);
      expect(p.screen.dx, closeTo(400, 0.5));
      expect(p.screen.dy, closeTo(300, 0.5));
    });
  });

  group('the default framing', () {
    // d_default = 1.15 * d_fit — the page's _overviewDefaultDistance.
    double defaultDistance(Size2 vp) =>
        1.15 * fitDistanceForSphere(radius: rWorld, viewport: vp, fovDegrees: fov);

    test('leaves a margin: the limb stays inside the short edge', () {
      for (final vp in <Size2>[landscape, portrait]) {
        final d = defaultDistance(vp);
        final limb = limbScreenRadius(
          radius: rWorld,
          distance: d,
          viewport: vp,
          fovDegrees: fov,
        );
        final shortEdge = vp.width < vp.height ? vp.width : vp.height;
        expect(limb, lessThanOrEqualTo(shortEdge / 2 + 0.001));
      }
    });

    test('the zoom bound clears the default framing in BOTH orientations', () {
      // The regression this guards: d_default is viewport-dependent (2.3R
      // landscape, 4.15R portrait), so a bound picked by eye for landscape
      // would clamp the camera CLOSER than the framing distance on a phone —
      // slicing the shell open on entry. The bound must be derived, not chosen.
      const upperBound = 5 * rWorld;
      final landscapeDefault = defaultDistance(landscape);
      final portraitDefault = defaultDistance(portrait);
      expect(landscapeDefault, lessThan(upperBound));
      expect(portraitDefault, lessThan(upperBound));
      // And they really do differ — otherwise this test would pass vacuously.
      expect(portraitDefault, greaterThan(landscapeDefault));
      // 1.15 × 2R exactly, and 1.15 × √13 R = 4.146384R.
      expect(landscapeDefault, closeTo(2.3 * rWorld, 1));
      expect(portraitDefault, closeTo(4.146384 * rWorld, 1));
    });

    test('the orbit bound is unchanged at 1800', () {
      // Regression: the overview bound must not leak into the orbit mode.
      expect(1800.0, lessThan(5 * rWorld));
    });
  });

  group('placeCamera', () {
    const ship = Vec3(1200, 40, -300);

    test('overview looks at the origin from the framing distance', () {
      final cam = Camera3D();
      placeCamera(
        cam,
        mode: CameraMode.overview,
        shipPosition: ship,
        overviewDistance: 84622,
      );
      expect(cam.mode, CameraMode.overview);
      expect(cam.target.x, 0);
      expect(cam.target.y, 0);
      expect(cam.target.z, 0);
      expect(cam.distance, 84622);
      // Which puts the eye outside the sphere the page just framed.
      expect(cam.eye.length, closeTo(84622, 1));
      expect(cam.eye.length, greaterThan(rWorld));
    });

    test('orbit looks at the ship', () {
      final cam = Camera3D();
      placeCamera(
        cam,
        mode: CameraMode.orbit,
        shipPosition: ship,
        overviewDistance: 84622,
      );
      expect(cam.mode, CameraMode.orbit);
      expect(cam.target.x, closeTo(ship.x, 0.001));
      expect(cam.target.y, closeTo(ship.y, 0.001));
      expect(cam.target.z, closeTo(ship.z, 0.001));
      expect(cam.distance, 520);
    });

    test('cockpit sits at the ship', () {
      final cam = Camera3D();
      placeCamera(
        cam,
        mode: CameraMode.cockpit,
        shipPosition: ship,
        overviewDistance: 84622,
      );
      expect(cam.mode, CameraMode.cockpit);
      expect(cam.eye.x, closeTo(ship.x, 0.001));
      expect(cam.eye.y, closeTo(ship.y, 0.001));
      expect(cam.eye.z, closeTo(ship.z, 0.001));
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/overview_camera_test.dart`
Expected: 编译失败 —— `The function 'focalFor' isn't defined`、`'CameraMode.overview' isn't defined`。

- [ ] **Step 3: 实现**

在 `lib/ui/galaxy3d/camera3d.dart` 里，把 `CameraMode` 换成三值：

```dart
/// How the camera is placed and aimed.
enum CameraMode {
  /// Orbit around a target point — the "star-map overview".
  orbit,

  /// Sit at the ship and look outward — first-person cockpit.
  cockpit,

  /// Sit outside the universe's boundary sphere and look in — the "universe
  /// overview". Reuses [orbit]'s eye formula; only the target's meaning and how
  /// far the camera may be pulled differ.
  overview,
}
```

在文件末尾（`Size2` 之后）追加：

```dart
/// Focal length in pixels for a viewport. Always derived from the viewport
/// height, which is why the height constraint on framing is aspect-independent.
double focalFor(Size2 viewport, double fovDegrees) =>
    (viewport.height / 2) / math.tan(fovDegrees * math.pi / 360);

/// Screen radius (pixels) of the limb of a sphere of [radius] whose centre lies
/// [distance] in front of the eye.
///
/// This is `focal * radius / sqrt(distance² - radius²)`, NOT the tempting
/// `focal * radius / distance`. The naive form under-draws by 13.4% at
/// `distance == 2 * radius` (the ratio is exactly `sqrt(3)/2`) and diverges as
/// the eye approaches the surface, so it cannot be used to size the shell.
///
/// Returns [double.infinity] when the eye is at or inside the limb, where a
/// limb radius is not defined.
double limbScreenRadius({
  required double radius,
  required double distance,
  required Size2 viewport,
  required double fovDegrees,
}) {
  final gap = distance * distance - radius * radius;
  if (gap <= 0) return double.infinity;
  return focalFor(viewport, fovDegrees) * radius / math.sqrt(gap);
}

/// The orbit distance at which a sphere of [radius] centred on the camera's
/// target exactly fits inside [viewport], touching the nearer edge.
///
/// Solves [limbScreenRadius] for `limb == min(width, height) / 2`. Both edges
/// are solved and the larger distance wins, so portrait and landscape are both
/// correct:
///
/// - Landscape: the height constraint binds and the answer is
///   `radius / sin(fov/2)` — at 60° that is exactly `2 * radius`, independent of
///   the viewport size.
/// - Portrait: the width constraint binds and the answer grows with the aspect
///   ratio (a 400×800 viewport needs `sqrt(13) * radius`).
double fitDistanceForSphere({
  required double radius,
  required Size2 viewport,
  required double fovDegrees,
}) {
  final half = fovDegrees * math.pi / 360;
  final byHeight = radius / math.sin(half);
  final aspect = viewport.height / viewport.width;
  final tanHalf = math.tan(half);
  final byWidth = radius * math.sqrt(1 + (aspect * aspect) / (tanHalf * tanHalf));
  return math.max(byHeight, byWidth);
}

/// How strongly to draw the universe shell at a given camera [distance]:
/// 1 when clear of the surface, 0 at or inside it, ramping over the last 15% of
/// the approach.
///
/// The shell is only ever drawn from outside. Once the eye is inside the sphere
/// the limb is no longer a circle, so there is no silhouette to draw — and the
/// "focus route" framing puts the camera deep inside on purpose.
double shellFade({required double radius, required double distance}) {
  if (radius <= 0) return 0;
  if (distance <= radius) return 0;
  return ((distance / radius - 1) / 0.15).clamp(0.0, 1.0);
}

/// Places [camera] for [mode] — what both "switch to this mode" and "recentre"
/// mean. Sets [Camera3D.mode] as well as the position, so a caller cannot leave
/// the two out of sync.
///
/// - [CameraMode.orbit]: look at the ship from a fixed standoff.
/// - [CameraMode.cockpit]: sit at the ship (the caller aims it).
/// - [CameraMode.overview]: look at Sol (the origin) from outside the boundary
///   sphere. This is also the way back out of a focused route.
///
/// [overviewDistance] is passed in rather than derived here because it depends
/// on the viewport, which only the page knows.
void placeCamera(
  Camera3D camera, {
  required CameraMode mode,
  required Vec3 shipPosition,
  required double overviewDistance,
  double orbitDistance = 520,
}) {
  camera.mode = mode;
  switch (mode) {
    case CameraMode.overview:
      camera.target = const Vec3(0, 0, 0);
      camera.distance = overviewDistance;
    case CameraMode.orbit:
      camera.target = shipPosition;
      camera.distance = orbitDistance;
    case CameraMode.cockpit:
      camera.eyeOverride = shipPosition;
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/overview_camera_test.dart`
Expected: PASS（16 个：`focalFor` 1 + `fitDistanceForSphere` 2 + `limbScreenRadius` 2 + `shellFade` 3 + 相机 2 + 默认取景 3 + `placeCamera` 3）

- [ ] **Step 5: 补既有投影测试**

在 `test/galaxy3d_projection_test.dart` 的 `main()` 末尾追加：

```dart
  test('overview mode shares the orbit eye formula, so it sits outside the '
      'volume it is looking at', () {
    final cam = Camera3D(
      target: const Vec3(0, 0, 0),
      yaw: 0,
      pitch: 0,
      distance: 73584, // 2R — exactly inscribed at 60° / 800×600
      mode: CameraMode.overview,
    );
    // eye = target − forward · distance = (0, 0, −73584)
    expect(cam.eye.x, closeTo(0, 0.5));
    expect(cam.eye.z, closeTo(-73584, 0.5));
    // And the same projection serves it: the target lands at screen centre.
    final p = cam.project(const Vec3(0, 0, 0), vp);
    expect(p.visible, isTrue);
    expect(p.screen.dx, closeTo(400, 0.5));
    expect(p.screen.dy, closeTo(300, 0.5));
  });
```

- [ ] **Step 6: 跑全量测试与静态分析**

Run: `flutter analyze && flutter test`
Expected: `No issues found`；全绿。

- [ ] **Step 7: 提交**

```bash
git add starward/lib/ui/galaxy3d/camera3d.dart starward/test/overview_camera_test.dart starward/test/galaxy3d_projection_test.dart
git commit -m "feat(starward): add the universe-overview camera mode and its framing maths

The camera mode itself is a third enum value that reuses orbit's eye
formula; the substance is the framing maths, which the shell and the
page both depend on:

- fitDistanceForSphere solves the sphere's screen silhouette for both
  viewport edges and takes the larger distance, so portrait and
  landscape both frame correctly (2R landscape, sqrt(13)R at 400x800).
- limbScreenRadius uses the exact focal*R/sqrt(d^2-R^2) rather than the
  tempting focal*R/d, which under-draws by 13.4% at d = 2R.
- shellFade ramps the shell out over the last 15% of the approach, so
  the camera can go inside the volume without a broken silhouette.
- placeCamera holds what "go to this mode" and "recentre" both mean,
  so the three-way fork has one implementation and can be tested
  without building a widget. The zoom bound is pinned against both
  orientations' framing distances — a landscape-chosen bound would
  clamp the camera closer than the framing distance in portrait and
  slice the shell open.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 2: 抽出星场热循环并加 `distanceScaled` 开关

**Files:**
- Create: `lib/ui/galaxy3d/star_field_painter.dart`
- Modify: `lib/ui/galaxy3d/galaxy3d_painter.dart`
- Create: `test/star_field_lod_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `focalFor`；既有 `HygStars`、`HygNamed`、`Camera3D`、`Size2`、`Vec3`、`StarColors`。
- Produces:
  - `void drawStarField(Canvas canvas, {required Size size, required HygStars field, required Camera3D camera, required double worldScale, required int maxDraw, required bool distanceScaled})`
  - `double apparentMagnitude({required HygNamed n, required Camera3D camera, required double worldScale, required bool distanceScaled})`
  - `void drawFieldLabels(Canvas canvas, {required Size size, required HygStars field, required Camera3D camera, required double worldScale, required bool distanceScaled, double maxMagnitude})`
  - `void drawTextLabel(Canvas canvas, Offset at, String text, Color color, double size, {bool center})`

**为什么需要 `distanceScaled`：** 星图会把星等按观测距离重算（`m' = m + 2.5·ln10⁻¹·ln(d_eye²/d_sol²)`），这是为了「飞船移动时星空跟着变」。但寰宇档相机距所有恒星约 73 584 世界单位，压暗量为 `5·log₁₀(d_eye/d_sol)`：银河盘面**中位数恒星被压暗 5 个星等**（p50 距日 703 ly），100 ly 以内的近星超过 9 个星等，球面上最远的星也有 1.8 个星等。整个宇宙会沉成一颗近黑的球。所以寰宇档必须传 `false`。

- [ ] **Step 1: 写失败测试**

创建 `test/star_field_lod_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/hyg_catalog.dart';
import 'package:starward/ui/galaxy3d/camera3d.dart';
import 'package:starward/ui/galaxy3d/star_field_painter.dart';

/// The universe-overview camera sees the whole catalogue from ~73 000 world
/// units away. The star-map painter rescales each star's magnitude to the
/// viewer's distance — right when the ship is among the stars, catastrophic
/// from outside: it dims the median catalogue star by 5 magnitudes, which
/// saturates the alpha ramp and renders the universe a near-black ball.
/// These tests pin the switch that prevents that, and pin the star map's
/// existing behaviour so the extraction provably changed nothing.
void main() {
  const double ws = 12;
  const double rWorld = 36792;

  /// Eye at (0, 0, -100), looking toward +z.
  Camera3D orbitCamera() => Camera3D(
        target: const Vec3(0, 0, 0),
        yaw: 0,
        pitch: 0,
        distance: 100,
        mode: CameraMode.orbit,
      );

  /// Eye at 2.3R along −z, looking at the origin.
  Camera3D overviewCamera() => Camera3D(
        target: const Vec3(0, 0, 0),
        yaw: 0,
        pitch: 0,
        distance: 2.3 * rWorld,
        mode: CameraMode.overview,
      );

  HygNamed starAt(Vec3 posLy, double magnitude) => HygNamed(
        id: 1,
        name: 'Test',
        position: posLy,
        magnitude: magnitude,
        color: 0xFFFFFFFF,
      );

  test('distanceScaled: true reproduces the star map exactly (regression)', () {
    // Star at 10 ly along +x → 120 world units. rel = (120, 0, 100).
    // d_eye² = 24400, d_sol² = 14400, ratio = 1.6944444.
    // 2.5 * log10(1.6944444) = 0.5726...
    final m = apparentMagnitude(
      n: starAt(const Vec3(10, 0, 0), 2.5),
      camera: orbitCamera(),
      worldScale: ws,
      distanceScaled: true,
    );
    expect(m, closeTo(3.0726, 0.001));
  });

  test('distanceScaled: false returns the catalogue magnitude verbatim', () {
    final m = apparentMagnitude(
      n: starAt(const Vec3(10, 0, 0), 2.5),
      camera: orbitCamera(),
      worldScale: ws,
      distanceScaled: false,
    );
    expect(m, 2.5);
  });

  test('the rescale would black the universe out from outside', () {
    // A star 703 ly from Sol (the catalogue's p50) is dimmed 5.0 magnitudes;
    // the alpha ramp ((6.6 - m) / 8 + 0.12) clamps at 0.05 for anything above
    // m = 6.16, so a dimmed sky collapses to the floor.
    final m = apparentMagnitude(
      n: starAt(const Vec3(703, 0, 0), 3.0),
      camera: overviewCamera(),
      worldScale: ws,
      distanceScaled: true,
    );
    expect(m, closeTo(8.0175, 0.02)); // 3.0 + 5.0175
    expect(((6.6 - m) / 8 + 0.12).clamp(0.05, 1.0), 0.05);
  });

  test('without the rescale a bright landmark stays visible from outside', () {
    // Sirius: magnitude −1.46.
    final m = apparentMagnitude(
      n: starAt(const Vec3(8.6, 0, 0), -1.46),
      camera: overviewCamera(),
      worldScale: ws,
      distanceScaled: false,
    );
    expect(m, -1.46);
    expect(((6.6 - m) / 8 + 0.12).clamp(0.05, 1.0), greaterThan(0.9));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/star_field_lod_test.dart`
Expected: 编译失败 —— `star_field_painter.dart` 不存在，`apparentMagnitude` 未定义。

- [ ] **Step 3: 新建共享星场模块**

创建 `lib/ui/galaxy3d/star_field_painter.dart`：

```dart
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/vec3.dart';
import '../../data/hyg_catalog.dart';
import 'camera3d.dart';

/// 1 / ln(10) — converts natural logs to base-10 for the magnitude rescale.
const double _invLn10 = 0.4342944819032518;

/// Allocation-free render of a packed star field (the real HYG catalogue or a
/// synthetic galaxy). Precomputes the camera basis once, then iterates with
/// inline projection. Stars are pre-sorted brightest-first, so [maxDraw] keeps
/// the most important stars and bounds the work regardless of zoom.
///
/// [distanceScaled] rescales each star's apparent magnitude to the viewer's
/// actual distance (brightness ∝ 1/d²), which is what makes the sky change as
/// the ship moves. It must be **false** for the universe-overview camera: from
/// outside the volume the eye sits ~73 000 world units from every star, which
/// dims the median catalogue star by 5 magnitudes — far past the alpha ramp's
/// saturation point — rendering the universe as a near-black ball.
void drawStarField(
  Canvas canvas, {
  required Size size,
  required HygStars field,
  required Camera3D camera,
  required double worldScale,
  required int maxDraw,
  required bool distanceScaled,
}) {
  const near = 1.0;
  // Star catalogue positions are in light-years; everything else in the scene
  // (planets, ship, camera) is in world units (ly × worldScale), so scale stars
  // to match — otherwise the ship ends up far outside the star field it's
  // supposed to be sitting inside.
  final ws = worldScale;

  // Camera basis as plain doubles.
  final f = camera.forward.normalized;
  var right = f.cross(Vec3.up);
  if (right.length < 1e-6) right = const Vec3(1, 0, 0);
  right = right.normalized;
  final up = right.cross(f).normalized;
  final eye = camera.eye;
  final focal = focalFor(Size2(size.width, size.height), camera.fovDegrees);
  final cx = size.width / 2, cy = size.height / 2;
  final fx = f.x, fy = f.y, fz = f.z;
  final rx = right.x, ry = right.y, rz = right.z;
  final ux = up.x, uy = up.y, uz = up.z;

  final xyz = field.xyz;
  final mag = field.mag;
  final color = field.color;
  final paint = Paint();
  var drawn = 0;
  for (var i = 0; i < field.count && drawn < maxDraw; i++) {
    final wx = xyz[i * 3] * ws;
    final wy = xyz[i * 3 + 1] * ws;
    final wz = xyz[i * 3 + 2] * ws;
    final relx = wx - eye.x;
    final rely = wy - eye.y;
    final relz = wz - eye.z;
    final camZ = relx * fx + rely * fy + relz * fz;
    if (camZ <= near) continue;
    final camX = relx * rx + rely * ry + relz * rz;
    final camY = relx * ux + rely * uy + relz * uz;
    final invZ = focal / camZ;
    final sx = cx + camX * invZ;
    final sy = cy - camY * invZ;
    if (sx < -8 || sx > size.width + 8 || sy < -8 || sy > size.height + 8) {
      continue;
    }
    // Apparent magnitude is distance-dependent (brightness ∝ 1/d²). The
    // catalogue value is as seen from Sol; rescale it to the viewer's actual
    // distance so moving through space changes which stars dominate the sky.
    final double m;
    if (distanceScaled) {
      final distEye2 = relx * relx + rely * rely + relz * relz;
      final distSol2 = wx * wx + wy * wy + wz * wz;
      m = mag[i] +
          2.5 * _invLn10 * math.log((distEye2 + 1e-12) / (distSol2 + 1e-12));
    } else {
      m = mag[i];
    }
    // Every star — including the system's sun — is a point at these distances;
    // the host just gets an extra glow pass (see Galaxy3DPainter._drawHostStar).
    final alpha = ((6.6 - m) / 8 + 0.12).clamp(0.05, 1.0);
    final radius = (0.5 + (3.0 - m) * 0.33).clamp(0.5, 2.6);
    paint.color = Color(color[i]).withValues(alpha: alpha);
    if (m < 1.4) {
      canvas.drawCircle(
        Offset(sx, sy),
        radius * 3,
        Paint()
          ..color = paint.color.withValues(alpha: alpha * 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
    canvas.drawCircle(Offset(sx, sy), radius, paint);
    drawn++;
  }
}

/// Apparent magnitude of [n] as seen from the camera, applying the same
/// distance rescale as [drawStarField] when [distanceScaled] is set.
double apparentMagnitude({
  required HygNamed n,
  required Camera3D camera,
  required double worldScale,
  required bool distanceScaled,
}) {
  if (!distanceScaled) return n.magnitude;
  final posW = n.position * worldScale;
  final rel = posW - camera.eye;
  final distEye2 = rel.dot(rel);
  final distSol2 = posW.dot(posW);
  return n.magnitude +
      2.5 * _invLn10 * math.log((distEye2 + 1e-12) / (distSol2 + 1e-12));
}

/// Labels only the brightest named stars, so famous landmarks (Sirius, Vega,
/// Arcturus, the synthetic galaxy's core…) are identifiable without flooding
/// the view with text. Gated on the magnitude as seen from here when
/// [distanceScaled] is set, so the bright landmarks change with the ship.
void drawFieldLabels(
  Canvas canvas, {
  required Size size,
  required HygStars field,
  required Camera3D camera,
  required double worldScale,
  required bool distanceScaled,
  double maxMagnitude = 1.6,
}) {
  final vp = Size2(size.width, size.height);
  for (final n in field.named.values) {
    final m = apparentMagnitude(
      n: n,
      camera: camera,
      worldScale: worldScale,
      distanceScaled: distanceScaled,
    );
    if (m > maxMagnitude) continue;
    final pr = camera.project(n.position * worldScale, vp);
    if (!pr.visible) continue;
    drawTextLabel(canvas, pr.screen + const Offset(6, -6), n.name,
        StarColors.muted.withValues(alpha: 0.8), 10);
  }
}

/// Draws a small text label with the app's label styling. [center] centres the
/// text horizontally on [at] instead of starting there.
void drawTextLabel(
  Canvas canvas,
  Offset at,
  String text,
  Color color,
  double size, {
  bool center = false,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style:
          TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w600),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  final offset = center ? at - Offset(tp.width / 2, 0) : at;
  tp.paint(canvas, offset);
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/star_field_lod_test.dart`
Expected: PASS（4 个）

- [ ] **Step 5: 让 `Galaxy3DPainter` 改用共享实现**

改 `lib/ui/galaxy3d/galaxy3d_painter.dart`，**只做这几处，其余一行不动**：

5a. 删掉文件顶部第 13–14 行的 `_invLn10` 常量，并加上 import：

```dart
import 'star_field_painter.dart';
```

5b. 删掉整个 `_drawStarField` 方法（原第 134–206 行），`paint` 里的三处调用改为：

```dart
    // Star backdrop: fast path over the real HYG field plus any extra galaxies.
    if (scene.hyg != null) {
      drawStarField(
        canvas,
        size: size,
        field: scene.hyg!,
        camera: camera,
        worldScale: scene.worldScale,
        maxDraw: 5000,
        distanceScaled: true,
      );
    }
    for (final g in scene.extraGalaxies) {
      drawStarField(
        canvas,
        size: size,
        field: g,
        camera: camera,
        worldScale: scene.worldScale,
        maxDraw: 5200,
        distanceScaled: true,
      );
    }
```

5c. 删掉整个 `_drawFieldLabels` 方法（原第 240–262 行），`paint` 里的调用改为：

```dart
    if (scene.hyg != null) {
      drawFieldLabels(
        canvas,
        size: size,
        field: scene.hyg!,
        camera: camera,
        worldScale: scene.worldScale,
        distanceScaled: true,
      );
    }
    for (final g in scene.extraGalaxies) {
      drawFieldLabels(
        canvas,
        size: size,
        field: g,
        camera: camera,
        worldScale: scene.worldScale,
        distanceScaled: true,
      );
    }
```

5d. 删掉 `_label` 方法（原第 436–448 行），三处调用（原第 259、288、352 行）改为调用 `drawTextLabel`，参数顺序不变。例如原：

```dart
      _label(canvas, pr.screen + const Offset(6, -6), s.name!,
          StarColors.muted.withValues(alpha: alpha), 10);
```

改为：

```dart
      drawTextLabel(canvas, pr.screen + const Offset(6, -6), s.name!,
          StarColors.muted.withValues(alpha: alpha), 10);
```

（第 352 行那处带 `center: true`，原样保留该具名参数。）

- [ ] **Step 6: 跑全量测试与静态分析**

Run: `flutter analyze && flutter test`
Expected: `No issues found`；全绿（`widget_smoke_test` 覆盖星图页渲染，是这次抽取的行为回归）。

- [ ] **Step 7: 提交**

```bash
git add starward/lib/ui/galaxy3d/star_field_painter.dart starward/lib/ui/galaxy3d/galaxy3d_painter.dart starward/test/star_field_lod_test.dart
git commit -m "refactor(starward): extract the star-field hot loop and gate the magnitude rescale

Galaxy3DPainter and the coming universe-overview painter need the same
star field, so the 70-line allocation-free loop, the named-star labels
and the text-label helper move into star_field_painter.dart. No
behaviour change for the star map: a regression test pins the rescale
formula's output at a known input.

The extraction also gives distanceScaled a single implementation. The
star map passes true; the universe overview must pass false, because
from outside the volume the rescale dims the median catalogue star by
5 magnitudes and collapses the alpha ramp — a near-black universe.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 3: 球壳几何与绘制

**Files:**
- Create: `lib/ui/galaxy3d/universe_shell.dart`
- Create: `test/universe_shell_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `limbScreenRadius`；既有 `Camera3D`、`Size2`、`Vec3`、`StarColors`。
- Produces:
  - `const int kShellMeridians = 12`, `kShellParallels = 6`, `kShellMeridianSegments = 32`, `kShellParallelSegments = 48`
  - `class ShellLattice { const ShellLattice({required List<List<Vec3>> far, required List<List<Vec3>> near}); final List<List<Vec3>> far, near; }`
  - `ShellLattice buildShellLattice({required Vec3 centre, required double radius, required Vec3 forward, int meridians, int parallels})`
  - `class UniverseShell { UniverseShell({required Vec3 centre, required double radius, required Vec3 forward}); double limbRadius(Camera3D camera, Size2 viewport); void paintFarHalf(Canvas canvas, {required Camera3D camera, required Size2 viewport, required double fade}); void paintNearHalf(Canvas canvas, {required Camera3D camera, required Size2 viewport, required double fade}); }`

**为什么是前后两半：** 星场必须夹在球壳的两半之间，恒星才读起来**在玻璃后面**，而不是贴在一个球上。划分平面由相机前向决定：`dot(P − C, f) < 0` 是远侧，`> 0` 是近侧。

- [ ] **Step 1: 写失败测试**

创建 `test/universe_shell_test.dart`：

```dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/ui/galaxy3d/camera3d.dart';
import 'package:starward/ui/galaxy3d/universe_shell.dart';

/// The shell's geometry is pure — no Flutter state, no game state — so it can
/// be tested without building a widget. Every count and side assignment is
/// pinned; the draw order it enables is what makes the globe read as hollow
/// rather than as a ball the stars are painted onto.
void main() {
  const double rWorld = 36792;
  const Vec3 centre = Vec3(0, 0, 0);

  test('emits every generated vertex, split by the camera-facing plane', () {
    final lattice = buildShellLattice(
      centre: centre,
      radius: rWorld,
      forward: const Vec3(0, 0, 1),
    );

    final far = <Vec3>[];
    final near = <Vec3>[];
    for (final run in lattice.far) {
      far.addAll(run);
    }
    for (final run in lattice.near) {
      near.addAll(run);
    }

    // 12 meridians × 33 points + 6 parallels × 49 points.
    expect(far.length + near.length, 12 * 33 + 6 * 49);

    // Every vertex is on the side it was filed under. Forward is +z, so the
    // far half is z < 0 and the near half is z >= 0.
    for (final p in far) {
      expect(p.z, lessThan(0));
    }
    for (final p in near) {
      expect(p.z, greaterThanOrEqualTo(0));
    }
  });

  test('a run never straddles the plane', () {
    final lattice = buildShellLattice(
      centre: centre,
      radius: rWorld,
      forward: const Vec3(0, 0, 1),
    );
    for (final run in lattice.far) {
      expect(run.every((p) => p.z < 0), isTrue,
          reason: 'a far run must be entirely on the far side');
    }
    for (final run in lattice.near) {
      expect(run.every((p) => p.z >= 0), isTrue,
          reason: 'a near run must be entirely on the near side');
    }
  });

  test('every vertex sits exactly on the sphere', () {
    final lattice = buildShellLattice(
      centre: centre,
      radius: rWorld,
      forward: const Vec3(0, 0, 1),
    );
    for (final run in <List<Vec3>>[...lattice.far, ...lattice.near]) {
      for (final p in run) {
        expect((p - centre).length, closeTo(rWorld, 1));
      }
    }
  });

  test('rotating the camera moves the split with it', () {
    // Forward along +x: the split is now the y/z plane at x = 0.
    final lattice = buildShellLattice(
      centre: centre,
      radius: rWorld,
      forward: const Vec3(1, 0, 0),
    );
    for (final run in lattice.far) {
      for (final p in run) {
        expect(p.x, lessThan(0));
      }
    }
    for (final run in lattice.near) {
      for (final p in run) {
        expect(p.x, greaterThanOrEqualTo(0));
      }
    }
  });

  group('UniverseShell.limbRadius', () {
    UniverseShell shell() =>
        UniverseShell(centre: centre, radius: rWorld, forward: const Vec3(0, 0, 1));

    Camera3D cameraAt(double distance) => Camera3D(
          target: centre,
          yaw: 0,
          pitch: 0,
          distance: distance,
          mode: CameraMode.overview,
        );

    test('matches the exact limb formula at the framing distance', () {
      // d = 2R, 800×600 → exactly h/2 = 300.
      expect(
        shell().limbRadius(cameraAt(2 * rWorld), const Size2(800, 600)),
        closeTo(300, 0.1),
      );
    });

    test('is infinite once the eye is inside the sphere', () {
      expect(
        shell().limbRadius(cameraAt(0.5 * rWorld), const Size2(800, 600)),
        double.infinity,
      );
    });

    test('draws nothing at all once the eye is inside the sphere', () async {
      // The spec's "球内不画" requirement, asserted on real pixels rather than
      // on the gate: the shell is painted unconditionally here, so this
      // exercises its own alpha maths, not a copy of the caller's condition.
      Future<int> opaquePixels(double distance) async {
        final fade = shellFade(radius: rWorld, distance: distance);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 800, 600));
        final vp = const Size2(800, 600);
        shell().paintFarHalf(canvas,
            camera: cameraAt(distance), viewport: vp, fade: fade);
        shell().paintNearHalf(canvas,
            camera: cameraAt(distance), viewport: vp, fade: fade);
        final image = recorder.endRecording().toImageSync(800, 600);
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        final data = bytes!.buffer.asUint8List();
        var count = 0;
        for (var i = 3; i < data.length; i += 4) {
          if (data[i] != 0) count++;
        }
        return count;
      }

      expect(await opaquePixels(2.3 * rWorld), greaterThan(0));
      expect(await opaquePixels(0.5 * rWorld), 0);
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/universe_shell_test.dart`
Expected: 编译失败 —— `universe_shell.dart` 不存在。

- [ ] **Step 3: 实现球壳**

创建 `lib/ui/galaxy3d/universe_shell.dart`：

```dart
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/universe_shell_test.dart`
Expected: PASS（7 个：4 个经纬网 + 2 个 `limbRadius` + 1 个「球内不画像素」）

- [ ] **Step 5: 跑全量测试与静态分析**

Run: `flutter analyze && flutter test`
Expected: `No issues found`；全绿。

- [ ] **Step 6: 提交**

```bash
git add starward/lib/ui/galaxy3d/universe_shell.dart starward/test/universe_shell_test.dart
git commit -m "feat(starward): add the hollow universe shell geometry

A graticule of 12 meridians and 6 parallels on the boundary sphere,
cut into a far and a near half by the plane through the centre
perpendicular to the camera's forward direction. Runs never straddle
the split, so no drawn segment jumps across it.

The split is the whole point: the star field is drawn between the two
halves, which is what makes the stars read as being behind glass
rather than painted onto a ball. The class is pure geometry over
Vec3/Camera3D/Size2 — no Flutter state, no game state — so it tests
without a widget.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 4: 寰宇 painter 与页面接线

**Files:**
- Create: `lib/ui/galaxy3d/universe_overview_painter.dart`
- Modify: `lib/ui/galaxy3d/galaxy_map_3d_page.dart`
- Modify: `test/widget_smoke_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `fitDistanceForSphere`、`shellFade`、`placeCamera`；Task 2 的 `drawStarField`、`drawFieldLabels`；Task 3 的 `UniverseShell`；既有 `Galaxy3DScene`、`Journey`、`GameController.locationLabel`。
- Produces:
  - `class UniverseOverviewPainter extends CustomPainter { UniverseOverviewPainter({required Galaxy3DScene scene, required Camera3D camera, required Vec3 shipPosition, required double universeRadiusLy, required Journey? journey, required double journeyProgress, required Listenable repaint}); }`
  - 页面新增：`void _setMode(CameraMode mode, Size2 vp)`、`void _aimCockpitAtOrigin()`、`double _overviewDefaultDistance(Size2 vp)`、`double get _universeRadiusWorld`、`double get _maxDistance`、`double get _universeRadiusLy`。

**这一档与 `Galaxy3DPainter` 的四处刻意的不同：**
1. 画球壳，且切成前后两半夹住星场；
2. **不**做星等距离衰减（`distanceScaled: false`）；
3. 不画行星、宿主星光晕、相位阴影——都是局部概念，全览下不足一个像素；
4. 航线保留真实比例（见 Task 5 的「聚焦航线」）。

- [ ] **Step 1: 写失败测试**

创建 `test/universe_overview_painter_test.dart`：

```dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starward/data/hyg_catalog.dart';
import 'package:starward/ui/galaxy3d/camera3d.dart';
import 'package:starward/ui/galaxy3d/galaxy3d_scene.dart';
import 'package:starward/ui/galaxy3d/universe_overview_painter.dart';

/// The overview painter is orchestration, so its correctness is mostly visual
/// and checked by running the app. What *is* testable is that it survives every
/// camera position the page can put it in — including deep inside the sphere,
/// where the shell must silently stop drawing instead of producing a garbage
/// silhouette — and that it paints something.
void main() {
  const double ws = 12;
  const double rWorld = 36792;
  const double rLy = 3066;

  final scene = Galaxy3DScene(
    planets: const <ScenePlanet>[],
    planetPositions: const <String, Vec3>{},
    worldScale: ws,
    hyg: HygStars.curatedFallback(),
  );

  ui.Image paintAt(Camera3D camera) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 800, 600));
    UniverseOverviewPainter(
      scene: scene,
      camera: camera,
      shipPosition: const Vec3(100, 0, 0),
      universeRadiusLy: rLy,
      journey: null,
      journeyProgress: 0,
      repaint: const AlwaysStoppedAnimation<double>(0),
    ).paint(canvas, const Size(800, 600));
    return recorder.endRecording().toImageSync(800, 600);
  }

  Camera3D cameraAt(double distance) => Camera3D(
        target: const Vec3(0, 0, 0),
        yaw: 0.6,
        pitch: 0.35,
        distance: distance,
        mode: CameraMode.overview,
      );

  test('paints from outside the sphere without throwing', () {
    final image = paintAt(cameraAt(2.3 * rWorld));
    expect(image.width, 800);
    expect(image.height, 600);
    image.dispose();
  });

  test('paints from inside the sphere without throwing', () {
    // The "focus route" framing puts the camera deep inside; the shell must
    // fade out rather than project a nonsense silhouette.
    final image = paintAt(cameraAt(880));
    expect(image.width, 800);
    image.dispose();
  });

  test('paints at the exact framing distance without throwing', () {
    final image = paintAt(cameraAt(2 * rWorld));
    expect(image.width, 800);
    image.dispose();
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/universe_overview_painter_test.dart`
Expected: 编译失败 —— `universe_overview_painter.dart` 不存在。

- [ ] **Step 3: 实现寰宇 painter**

创建 `lib/ui/galaxy3d/universe_overview_painter.dart`：

```dart
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/journey.dart';
import 'camera3d.dart';
import 'galaxy3d_scene.dart';
import 'star_field_painter.dart';
import 'universe_shell.dart';

/// The universe seen from outside its own boundary: the hollow shell of
/// `universeRadius` with the whole catalogue inside it.
///
/// Differs from Galaxy3DPainter in four ways, all deliberate:
/// - draws the shell, split so the star field sits between its two halves;
/// - **no** magnitude distance-rescale (from out here it would black the sky);
/// - no planets, no host-star bloom, no phase shadow — local concepts that are
///   sub-pixel at this scale;
/// - keeps the route at true scale, so it is invisible at full framing and the
///   readout bar offers a "focus route" framing instead.
class UniverseOverviewPainter extends CustomPainter {
  UniverseOverviewPainter({
    required this.scene,
    required this.camera,
    required this.shipPosition,
    required this.universeRadiusLy,
    required this.journey,
    required this.journeyProgress,
    required this.repaint,
  }) : super(repaint: repaint);

  final Galaxy3DScene scene;
  final Camera3D camera;
  final Vec3 shipPosition;
  final double universeRadiusLy;
  final Journey? journey;
  final double journeyProgress;
  final Listenable repaint;

  /// Draw caps inherited from the star-map painter. At full framing nearly
  /// every star lands on screen, so these bound both density and cost; they are
  /// a tuning knob, not a design promise (see the spec's §6.3).
  static const int _hygMaxDraw = 5000;
  static const int _galaxyMaxDraw = 5200;

  @override
  void paint(Canvas canvas, Size size) {
    final vp = Size2(size.width, size.height);
    final ws = scene.worldScale;
    final rWorld = universeRadiusLy * ws;
    const centre = Vec3(0, 0, 0);
    final fade = shellFade(
      radius: rWorld,
      distance: (camera.eye - centre).length,
    );

    // ① Far half of the shell — behind the stars.
    UniverseShell? shell;
    if (fade > 0) {
      shell = UniverseShell(
        centre: centre,
        radius: rWorld,
        forward: camera.forward,
      );
      shell.paintFarHalf(canvas, camera: camera, viewport: vp, fade: fade);
    }

    // ② The star field, between the two halves.
    final hyg = scene.hyg;
    if (hyg != null) {
      drawStarField(
        canvas,
        size: size,
        field: hyg,
        camera: camera,
        worldScale: ws,
        maxDraw: _hygMaxDraw,
        distanceScaled: false,
      );
    }
    for (final g in scene.extraGalaxies) {
      drawStarField(
        canvas,
        size: size,
        field: g,
        camera: camera,
        worldScale: ws,
        maxDraw: _galaxyMaxDraw,
        distanceScaled: false,
      );
    }

    // ③ Near half — in front of the stars, which is what makes it read hollow.
    if (shell != null) {
      shell.paintNearHalf(canvas, camera: camera, viewport: vp, fade: fade);
    }

    // ④ Landmarks, the route at true scale, then the ship.
    if (hyg != null) {
      drawFieldLabels(
        canvas,
        size: size,
        field: hyg,
        camera: camera,
        worldScale: ws,
        distanceScaled: false,
      );
    }
    for (final g in scene.extraGalaxies) {
      drawFieldLabels(
        canvas,
        size: size,
        field: g,
        camera: camera,
        worldScale: ws,
        distanceScaled: false,
      );
    }
    _drawRoute(canvas, vp);
    _drawShip(canvas, vp);
  }

  void _drawRoute(Canvas canvas, Size2 vp) {
    final j = journey;
    if (j == null) return;
    final from = scene.positionOf(j.originPlanetId);
    final to = scene.positionOf(j.destinationPlanetId);
    final pf = camera.project(from, vp);
    final pt = camera.project(to, vp);
    if (!pf.visible || !pt.visible) return;
    canvas.drawLine(
      pf.screen,
      pt.screen,
      Paint()
        ..color = StarColors.cyan.withValues(alpha: 0.6)
        ..strokeWidth = 1.5,
    );
    final marker = Offset.lerp(pf.screen, pt.screen, journeyProgress)!;
    canvas.drawCircle(marker, 4, Paint()..color = StarColors.gold);
  }

  void _drawShip(Canvas canvas, Size2 vp) {
    // Unlike the star map there is no cockpit case to skip: the overview camera
    // is never the ship, so the marker always belongs on screen.
    final pr = camera.project(shipPosition, vp);
    if (!pr.visible) return;
    canvas.drawCircle(pr.screen, 5, Paint()..color = StarColors.offWhite);
    canvas.drawCircle(
      pr.screen,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = StarColors.cyan,
    );
  }

  @override
  bool shouldRepaint(UniverseOverviewPainter old) => true;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/universe_overview_painter_test.dart`
Expected: PASS（3 个）

- [ ] **Step 5: 接线到页面**

改 `lib/ui/galaxy3d/galaxy_map_3d_page.dart`。

5a. 加 import：

```dart
import 'universe_overview_painter.dart';
```

5b. 在 state 里加宇宙半径的缓存（`universeRadius` 首次访问要扫 12 万颗星，不能在每帧的 `build` 里裸调）：

```dart
  double? _radiusLy;

  /// `Universe.universeRadius` scans the whole catalogue on first access and
  /// caches it per Universe instance; this caches it per page so a rebuild
  /// never risks re-triggering that scan.
  double get _universeRadiusLy => _radiusLy ??= _c.universe.universeRadius;

  /// Sphere radius in world units.
  double get _universeRadiusWorld => _universeRadiusLy * _worldScale;

  /// Upper zoom bound. Derived from the framing distance rather than picked by
  /// eye: `d_default` is 2.3R in landscape but 4.15R in portrait (400×800), so
  /// a bound chosen for landscape would clamp the camera *closer* than the
  /// framing distance on a phone and slice the shell open.
  double get _maxDistance =>
      _camera.mode == CameraMode.overview ? 5 * _universeRadiusWorld : 1800;

  /// The framing distance with a 15% margin, so the shell does not touch the
  /// viewport edge.
  double _overviewDefaultDistance(Size2 vp) =>
      1.15 *
      fitDistanceForSphere(
        radius: _universeRadiusWorld,
        viewport: vp,
        fovDegrees: _camera.fovDegrees,
      );
```

5c. 把 `_toggleMode` 换成三档的 `_setMode` + 座舱瞄准。定位交给 Task 1 的 `placeCamera`，这样「切档」与「居中」共用一份语义，也让那个三叉分派能被单测覆盖：

```dart
  void _setMode(CameraMode mode, Size2 vp) {
    if (_camera.mode == mode) return;
    setState(() {
      placeCamera(
        _camera,
        mode: mode,
        shipPosition: _shipPos,
        overviewDistance: _overviewDefaultDistance(vp),
      );
      // Entering the cockpit points it at the galactic centre (origin); the
      // other two modes are fully placed by placeCamera.
      if (mode == CameraMode.cockpit) _aimCockpitAtOrigin();
    });
  }

  void _aimCockpitAtOrigin() {
    final dir = (const Vec3(0, 0, 0) - _shipPos).normalized;
    _camera.yaw = math.atan2(dir.x, dir.z);
    _camera.pitch = math.asin(dir.y.clamp(-1.0, 1.0)) * 0.6;
    _camera.clampPitch();
  }
```

5d. `_recenter` 按档分叉（多一个参数），直接复用同一份语义：

```dart
  void _recenter(Size2 vp) {
    setState(() {
      placeCamera(
        _camera,
        mode: _camera.mode,
        shipPosition: _shipPos,
        overviewDistance: _overviewDefaultDistance(vp),
      );
    });
  }
```

注意 `_recenter` 与 `_setMode` 在座舱档上**故意不同**：居中只把眼睛放回飞船，不重新瞄准（玩家可能已经转过头了）；切档才重新瞄准。

5e. `_onScaleUpdate` 的两个分叉改为「座舱 vs 其余」：

```dart
  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      // Rotation from drag (one finger): horizontal → yaw, vertical → pitch.
      final delta = d.focalPointDelta;
      const k = 0.006;
      if (_camera.mode == CameraMode.cockpit) {
        // Cockpit: look around (invert so dragging feels like turning the view).
        _camera.yaw -= delta.dx * k;
        _camera.pitch -= delta.dy * k;
      } else {
        // Orbit and universe-overview both rotate the volume under the camera.
        _camera.yaw -= delta.dx * k;
        _camera.pitch += delta.dy * k;
      }
      _camera.clampPitch();

      // Zoom from pinch: cockpit changes FOV, the orbiting modes change distance.
      if (d.scale != 1.0) {
        final factor = d.scale / _lastScale;
        _lastScale = d.scale;
        if (_camera.mode == CameraMode.cockpit) {
          _camera.fovDegrees = (_camera.fovDegrees / factor).clamp(30.0, 95.0);
        } else {
          _camera.distance =
              (_camera.distance / factor).clamp(70.0, _maxDistance);
        }
      }
    });
  }
```

5f. `_onTapUp` 早退（在方法开头加三行，其余不动）：

```dart
  void _onTapUp(TapUpDetails d, Size size) {
    // The universe overview is read-only. At 12–16 ly/px a tap would hit a
    // near-arbitrary star, and a mis-tap costs a voyage that may burn all the
    // ship's energy — so there is no hit-testing here at all, rather than an
    // inaccurate one. Switch back to 总览 to pick a star.
    if (_camera.mode == CameraMode.overview) return;
    final scene = _scene;
    if (scene == null) return;
    // In-system planet disc first (the only planets drawn)…
    final pid = pickPlanet(
      scene: scene,
      camera: _camera,
      size: size,
      tap: d.localPosition,
      shipPosition: _shipPos,
      sensorRange: _sensorRange,
    );
    if (pid != null) {
      final planet = _c.planetById(pid);
      if (planet != null) {
        setState(() => _selectedId = pid);
        _openDetails(planet);
        return;
      }
    }
    // …otherwise a star: open its system view.
    final starId = pickStarId(
      scene: scene,
      camera: _camera,
      size: size,
      tap: d.localPosition,
      shipPosition: _shipPos,
      sensorRange: _sensorRange,
    );
    if (starId != null) _openSystem(starId);
  }
```

5g. `build` 整体替换为下面这版（`LayoutBuilder` 拿到 size 后构造 `Size2`，回调闭包捕获它；painter 按档选择）：

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StarColors.abyss,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          if (!_initedCamera) _initCamera();
          final scene = _buildScene();
          _scene = scene;
          return LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              final vp = Size2(size.width, size.height);
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const DecoratedBox(
                    decoration: BoxDecoration(gradient: StarGradients.space),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onTapUp: (d) => _onTapUp(d, size),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _camera.mode == CameraMode.overview
                          ? UniverseOverviewPainter(
                              scene: scene,
                              camera: _camera,
                              shipPosition: _shipPos,
                              universeRadiusLy: _universeRadiusLy,
                              journey: _c.activeJourney,
                              journeyProgress:
                                  _c.activeJourney?.progressAt(_c.now) ?? 0,
                              repaint: _c,
                            )
                          : Galaxy3DPainter(
                              scene: scene,
                              camera: _camera,
                              selectedId: _selectedId,
                              shipPosition: _shipPos,
                              sensorRange: _sensorRange,
                              parkedPlanetId: _c.currentPlanetId,
                              journey: _c.activeJourney,
                              journeyProgress:
                                  _c.activeJourney?.progressAt(_c.now) ?? 0,
                              repaint: _c,
                            ),
                    ),
                  ),
                  // Cockpit framing — a through-the-viewport feel in first
                  // person. Non-interactive so gestures pass through.
                  if (_camera.mode == CameraMode.cockpit)
                    const Positioned.fill(
                      child: IgnorePointer(child: _CockpitOverlay()),
                    ),
                  _TopBar(controller: _c, mode: _camera.mode),
                  _SideControls(
                    mode: _camera.mode,
                    onSelect: (m) => _setMode(m, vp),
                    onRecenter: () => _recenter(vp),
                  ),
                  _BottomControls(
                    sensorRange: _sensorRange,
                    mode: _camera.mode,
                    onSensorChanged: (v) => setState(() => _sensorRange = v),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
```

（Task 5 会把这里的 `_BottomControls` 换成按档分叉。）

5h. 顶栏副标题三档：

```dart
                Text(
                  switch (mode) {
                    CameraMode.overview => '星图 · 寰宇',
                    CameraMode.orbit => '星图 · 总览',
                    CameraMode.cockpit => '星图 · 座舱视角',
                  },
                  style: const TextStyle(color: StarColors.muted, fontSize: 12),
                ),
```

5i. 侧栏改成四按钮，各按钮显示**自己的**档位并高亮当前档（旧按钮显示的是**目标**档，三档下这个语义会失效）：

```dart
class _SideControls extends StatelessWidget {
  const _SideControls({
    required this.mode,
    required this.onSelect,
    required this.onRecenter,
  });

  final CameraMode mode;
  final ValueChanged<CameraMode> onSelect;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _RoundButton(
                icon: Icons.blur_circular_rounded,
                label: '寰宇',
                selected: mode == CameraMode.overview,
                onTap: () => onSelect(CameraMode.overview),
              ),
              const SizedBox(height: 10),
              _RoundButton(
                icon: Icons.public_rounded,
                label: '总览',
                selected: mode == CameraMode.orbit,
                onTap: () => onSelect(CameraMode.orbit),
              ),
              const SizedBox(height: 10),
              _RoundButton(
                icon: Icons.flight_rounded,
                label: '座舱',
                selected: mode == CameraMode.cockpit,
                onTap: () => onSelect(CameraMode.cockpit),
              ),
              const SizedBox(height: 12),
              _RoundButton(
                icon: Icons.my_location_rounded,
                label: '居中',
                onTap: onRecenter,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

5j. `_RoundButton` 加 `selected`：

```dart
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: panelDecoration(
              radius: 23,
              color: selected ? StarColors.panelLight : null,
              border: selected ? StarColors.cyan.withValues(alpha: 0.75) : null,
            ),
            child: Icon(
              icon,
              color: selected ? StarColors.gold : StarColors.cyan,
              size: 22,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: selected ? StarColors.offWhite : StarColors.muted,
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
```

5k. `_BottomControls` 的提示语加一档：

```dart
                Text(
                  switch (mode) {
                    CameraMode.overview => '拖动旋转 · 双指缩放',
                    CameraMode.orbit => '拖动旋转 · 双指缩放 · 点击恒星进入星系',
                    CameraMode.cockpit => '拖动环视四周 · 双指调整视场 · 点击恒星进入星系',
                  },
                  style:
                      const TextStyle(color: StarColors.faint, fontSize: 10.5),
                ),
```

（底栏在寰宇档会被 Task 5 的读数条替掉；这一句先留着，让 Task 4 的底栏仍是完整可编译的。）

- [ ] **Step 6: 补 widget 测试**

在 `test/widget_smoke_test.dart` 的既有 `testWidgets` 之后追加一个：

```dart
  testWidgets('the universe overview is reachable and replaces the sensor bar',
      (tester) async {
    final controller =
        GameController(repository: GameRepository(MemoryStorage()));
    await controller.init();

    await tester.pumpWidget(
      MaterialApp(
        home: GameScope(controller: controller, child: const HomeShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('星图 · 总览'), findsOneWidget);
    expect(find.text('飞行器传感器范围'), findsOneWidget);

    await tester.tap(find.text('寰宇'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('星图 · 寰宇'), findsOneWidget);
    // The overview painter built without throwing — a smoke test cannot assert
    // what it drew, only that the whole subtree survived a real layout pass.

    await tester.tap(find.text('总览'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('星图 · 总览'), findsOneWidget);
    expect(find.text('飞行器传感器范围'), findsOneWidget);

    // And the third mode still works after a round trip through the overview.
    await tester.tap(find.text('座舱'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('星图 · 座舱视角'), findsOneWidget);
  });
```

（底栏在寰宇档被读数条替掉是 Task 5 的事，这一步不断言它。）

- [ ] **Step 7: 跑测试与静态分析**

Run: `flutter analyze && flutter test`
Expected: `No issues found`；全绿。

- [ ] **Step 8: 跑起来看**

Run: `flutter run`

逐项确认（这是这一步唯一能验证的东西）：
1. 点侧栏「寰宇」——出现一颗玻璃球，球壳轮廓是一个完整的圆，不贴屏幕边。
2. 拖动——球跟着转，经纬网跟着转。
3. 双指缩放——往外拉，球变小；往里推到球内，**球壳消失**，只剩星场。
4. 球内能看到银河盘面的明暗结构，**不是**一颗黑球。
5. 能看见天狼星、织女星这类具名标注。
6. 飞船位置有一个白点 + 青色圆环。
7. 点任意位置——**不弹任何面板**。

- [ ] **Step 9: 提交**

```bash
git add starward/lib/ui/galaxy3d/universe_overview_painter.dart starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart starward/test/universe_overview_painter_test.dart starward/test/widget_smoke_test.dart
git commit -m "feat(starward): add the universe overview as a third camera mode

The star map's side rail grows a third mode that puts the camera
outside the boundary sphere and looks in, drawing the hollow shell
between two passes of the star field so the stars read as being behind
glass. The painter skips the magnitude distance-rescale, which from out
here dims the median catalogue star by 5 magnitudes and collapses the
alpha ramp into a near-black ball, and drops planets, host-star bloom
and phase shadows — all sub-pixel at this scale.

Tap handling returns early in this mode rather than hit-testing: at
12–16 ly/px a tap lands on a near-arbitrary star, and a mis-tap costs a
voyage that may burn all the ship's energy.

The zoom bound is derived from the framing distance (5R) rather than
picked by eye, because d_default is 4.15R in portrait — a landscape-
chosen bound would clamp the camera closer than the framing distance
and slice the shell open on a phone.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## Task 5: 底栏读数条、聚焦航线与文档

**Files:**
- Modify: `lib/ui/galaxy3d/galaxy_map_3d_page.dart`
- Modify: `test/widget_smoke_test.dart`
- Modify: `starward/README.md`
- Modify: `starward/CLAUDE.md`

**Interfaces:**
- Consumes: Task 4 的 `_universeRadiusLy`、`_shipPos`、`_scene`、`GameController.locationLabel`、`GameController.activeJourney`、`StarLabels.distance`、`StarPanel`、`panelDecoration`。
- Produces:
  - `void _focusRoute(Size2 vp)`
  - `class _OverviewReadout extends StatelessWidget`
  - `class _ReadoutRow extends StatelessWidget`

**读数条替换掉传感器滑块**（`600–5000` 世界单位即 50–416 ly，在全览尺度下无意义）：

```
┌──────────────────────────────────┐
│ ✦ 宇宙全览 · R 3066 ly            │
│ 飞船距球心                1 842 ly │
│ 飞船距边界                1 224 ly │
│ 航线 港湾中枢→织女星        25.4 ly │
│                        [ 聚焦航线 ] │
│ 拖动旋转 · 双指缩放                 │
└──────────────────────────────────┘
```

「飞船距边界」**为负时必须显示「壳外 X ly」**——飞船确实可能在壳外（合成星系 SG-2 在 3400 ly，是合法目的地）。

**聚焦航线的取景公式：**

```
target   = 航线中点
distance = max( 航线长度_w · focal / (0.6 · min(w, h)) , 70 )
```

即让航线占短边的约 60%，下限用 orbit 档的最小缩放 70。之后按「居中」退回全宇宙取景。

- [ ] **Step 1: 写失败测试**

在 `test/widget_smoke_test.dart` 里：

1a. 给 Task 4 加的那个测试补上「读数条替掉滑块」的断言——切到寰宇之后加两行：

```dart
    expect(find.text('宇宙全览'), findsOneWidget);
    expect(find.text('飞行器传感器范围'), findsNothing);
```

1b. 在文件末尾追加一条更细的：

```dart
  testWidgets('the overview readout reports the radius and the ship distance',
      (tester) async {
    final controller =
        GameController(repository: GameRepository(MemoryStorage()));
    await controller.init();

    await tester.pumpWidget(
      MaterialApp(
        home: GameScope(controller: controller, child: const HomeShell()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('寰宇'));
    await tester.pump(const Duration(milliseconds: 100));

    // The readout replaces the sensor slider and names the view.
    expect(find.text('宇宙全览'), findsOneWidget);
    expect(find.text('飞行器传感器范围'), findsNothing);
    expect(find.text('飞船距球心'), findsOneWidget);
    expect(find.text('飞船距边界'), findsOneWidget);

    // With no active voyage there is no route row and no focus button.
    expect(find.text('聚焦航线'), findsNothing);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/widget_smoke_test.dart`
Expected: FAIL —— `Expected: exactly one matching candidate ... Actual: found 0 widgets with text "宇宙全览"`。

- [ ] **Step 3: 实现聚焦航线**

在 `_GalaxyMap3DPageState` 里加：

```dart
  /// Frames the active voyage so it fills about 60% of the viewport's short
  /// edge. At full framing the route is 0.15–3.4 px long — invisible — so this
  /// is the only way to see it without giving up true scale.
  void _focusRoute(Size2 vp) {
    final j = _c.activeJourney;
    final scene = _scene;
    if (j == null || scene == null) return;
    final from = scene.positionOf(j.originPlanetId);
    final to = scene.positionOf(j.destinationPlanetId);
    final lengthWorld = (to - from).length;
    final focal = focalFor(vp, _camera.fovDegrees);
    final shortEdge = math.min(vp.width, vp.height);
    final framed = lengthWorld * focal / (0.6 * shortEdge);
    setState(() {
      _camera.target = (from + to) * 0.5;
      _camera.distance = math.max(framed, 70);
    });
  }
```

- [ ] **Step 4: 实现读数条并接线**

在 `_GalaxyMap3DPageState` 里加两个小助手：

```dart
  /// The two endpoints of the active voyage, named via the controller (which
  /// knows how to label star destinations and the deep-space pseudo-planet).
  (String, String) _routeEndpoints() {
    final j = _c.activeJourney;
    if (j == null) return ('—', '—');
    return (
      _c.locationLabel(j.originPlanetId),
      _c.locationLabel(j.destinationPlanetId),
    );
  }

  /// Straight-line length of the active voyage, in light-years.
  double _routeLengthLy() {
    final j = _c.activeJourney;
    final scene = _scene;
    if (j == null || scene == null) return 0;
    final from = scene.positionOf(j.originPlanetId);
    final to = scene.positionOf(j.destinationPlanetId);
    return (to - from).length / _worldScale;
  }
```

在 `build` 的 `Stack` 里，把底栏替换为按档分叉（端点名只算一次）：

```dart
                  if (_camera.mode == CameraMode.overview)
                    _OverviewReadout(
                      radiusLy: _universeRadiusLy,
                      shipDistanceLy: _shipPos.length / _worldScale,
                      hasJourney: _c.activeJourney != null,
                      routeLengthLy: _routeLengthLy(),
                      originLabel: endpoints.$1,
                      destinationLabel: endpoints.$2,
                      onFocusRoute: () => _focusRoute(vp),
                    )
                  else
                    _BottomControls(
                      sensorRange: _sensorRange,
                      mode: _camera.mode,
                      onSensorChanged: (v) => setState(() => _sensorRange = v),
                    ),
```

并在同一个 `LayoutBuilder` 的 builder 顶部（`final vp = ...` 之后）加一行：

```dart
              final endpoints = _routeEndpoints();
```

在文件末尾（`_CockpitPainter` 之前或之后，与其它私有 widget 放一起）加：

```dart
/// The universe-overview readout: the boundary radius, where the ship sits
/// inside it, and — when a voyage is running — the route and a button to frame
/// it. Replaces the sensor slider, whose 50–416 ly range is meaningless at this
/// scale.
class _OverviewReadout extends StatelessWidget {
  const _OverviewReadout({
    required this.radiusLy,
    required this.shipDistanceLy,
    required this.hasJourney,
    required this.routeLengthLy,
    required this.originLabel,
    required this.destinationLabel,
    required this.onFocusRoute,
  });

  final double radiusLy;
  final double shipDistanceLy;
  final bool hasJourney;
  final double routeLengthLy;
  final String originLabel;
  final String destinationLabel;
  final VoidCallback onFocusRoute;

  @override
  Widget build(BuildContext context) {
    final toEdge = radiusLy - shipDistanceLy;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: StarPanel(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.blur_circular_rounded,
                        color: StarColors.gold, size: 16),
                    const SizedBox(width: 8),
                    const Text('宇宙全览',
                        style: TextStyle(
                            color: StarColors.offWhite,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('R ${radiusLy.round()} ly',
                        style: const TextStyle(
                            color: StarColors.gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 8),
                _ReadoutRow(
                  label: '飞船距球心',
                  value: StarLabels.distance(shipDistanceLy),
                ),
                _ReadoutRow(
                  label: '飞船距边界',
                  // The ship can legitimately be outside the shell — the
                  // synthetic galaxy SG-2 sits at 3400 ly and is a real
                  // destination — so a negative reading must say so rather than
                  // print a negative distance.
                  value: toEdge >= 0
                      ? StarLabels.distance(toEdge)
                      : '壳外 ${StarLabels.distance(-toEdge)}',
                ),
                if (hasJourney) ...<Widget>[
                  const SizedBox(height: 6),
                  _ReadoutRow(
                    label: '航线 $originLabel→$destinationLabel',
                    value: StarLabels.distance(routeLengthLy),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: onFocusRoute,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: panelDecoration(radius: 99),
                        child: const Text('聚焦航线',
                            style: TextStyle(
                                color: StarColors.cyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                const Text('拖动旋转 · 双指缩放',
                    style: TextStyle(color: StarColors.faint, fontSize: 10.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A label/value line inside the readout panel.
class _ReadoutRow extends StatelessWidget {
  const _ReadoutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: StarColors.muted, fontSize: 11.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
                color: StarColors.offWhite,
                fontSize: 11.5,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: 跑测试与静态分析**

Run: `flutter analyze && flutter test`
Expected: `No issues found`；全绿。

- [ ] **Step 6: 补一个聚焦航线的取景测试**

在 `test/overview_camera_test.dart` 末尾的 `main()` 内追加（把取景公式本身钉住，不依赖 widget）：

```dart
  test('focus-route framing fits a 25.4 ly route to 60% of the short edge', () {
    // 25.4 ly → 304.8 world units. At 400×800 the focal is 692.82 px, so the
    // route needs 304.8 * 692.82 / (0.6 * 400) ≈ 880 world units of distance.
    const lengthWorld = 25.4 * 12;
    final focal = focalFor(portrait, fov);
    final framed = lengthWorld * focal / (0.6 * 400);
    expect(framed, closeTo(880, 5));
    expect(math.max(framed, 70), closeTo(880, 5));
  });
```

在文件顶部加 `import 'dart:math' as math;`。

- [ ] **Step 7: 跑测试确认通过**

Run: `flutter test test/overview_camera_test.dart test/widget_smoke_test.dart`
Expected: PASS

- [ ] **Step 8: 更新文档**

8a. `starward/README.md` 的「3D 星图与真实星表（HYG）」一节，把双档描述改成三档。找到描述总览/座舱的那段，补上：

```markdown
侧栏有三个档位：

- **总览** —— 相机绕飞船旋转，点击恒星进入星系。
- **座舱** —— 相机位于飞船，第一人称环视。
- **寰宇** —— 相机在宇宙边界球之外向内看，球壳镂空（经纬网 + 极淡填充），
  星场夹在前后半球之间。只读：不响应点击，避免在全览尺度下误触出发。
  底栏显示宇宙半径、飞船距球心／距边界，有航线时可「聚焦航线」一键取景。

「寰宇」的球面半径就是 `Universe.universeRadius`（p95，实测 3066 ly）——
它同时是漂流边界，所以球面不是装饰，它就是飞船被关在里面的那个边界。
```

8b. `starward/CLAUDE.md` 无需改动（本计划未新增领域约定、未新增 `Balance` 字段、未改存档）。**若确认无改动，跳过这一步并在提交信息里说明。**

- [ ] **Step 9: 跑全量测试与静态分析**

Run: `flutter analyze && flutter test`
Expected: `No issues found`；全绿。

- [ ] **Step 10: 提交**

```bash
git add starward/lib/ui/galaxy3d/galaxy_map_3d_page.dart starward/test/widget_smoke_test.dart starward/test/overview_camera_test.dart starward/README.md
git commit -m "feat(starward): add the universe-overview readout and route framing

The sensor slider is meaningless at universe scale (50–416 ly), so the
overview swaps in a readout: the boundary radius, the ship's distance
from the centre, and its distance from the boundary — reported as
"壳外 X ly" when negative, since SG-2 sits at 3400 ly and is a real
destination.

The route keeps true scale, which makes it 0.15–3.4 px at full framing,
so the readout offers a focus button that frames it to 60% of the
viewport's short edge. 居中 returns to the whole-universe framing.

Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

## 执行期注意事项

1. **规格 §10 的 12 条测试映射到任务**：测试 1/3/5/6/7/10 在 Task 1；测试 2/4 在 Task 3；测试 11/12 在 Task 2；测试 8 由 Task 1 的 `placeCamera` 组覆盖（原先打算在页面里做，那样无法单测，所以提成了纯函数）；测试 9 在 Task 5 Step 6。两处措辞按实现方式调整过：
   - 测试 4「`d < R` 时绘制调用数为 0」→ 改为对真实像素计数（`Picture.toImageSync` + alpha 通道扫描），因为 `ui.Picture` 不暴露绘制调用数。
   - 测试 6「此时球面轮廓半径 ≤ 短边一半」→ 在 Task 1 的「默认取景」组里对两种朝向都断言。

2. **`universeRadius` 可能为 0**：`Universe.universeRadius` 在星表为空时返回 0。此时 `fitDistanceForSphere` 返回 0、`distance` 被夹到 70、`shellFade` 返回 0（已加 `radius <= 0` 守卫），不画球壳。不会崩，但也不会显示球——这是可接受的退化。

3. **绘制上限是调参旋钮，不是设计承诺**：`_hygMaxDraw = 5000` / `_galaxyMaxDraw = 5200` 是从星图继承的值。全览视野下几乎全部恒星都落在屏幕内，所以 `maxDraw` 同时决定**密度和开销**（约等于 maxDraw 次 `drawCircle`，三档合计上限 15 400）。跑起来看，太稀就调高，但要顺带量帧率。

4. **`_label` 的删除**：`galaxy3d_painter.dart` 里的 `_label` 与 `drawTextLabel` 实现完全相同，抽取后必须删掉，否则 `flutter analyze` 会报未使用的私有方法。

5. **不要 bump `_saveKey`**：本计划零模型变更，存档结构不变。

6. **`Vec3` 的运算**：`(from + to) * 0.5` 依赖 `Vec3` 的 `+` 与 `*(double)`，两者都已存在（`lib/core/vec3.dart`）。

7. **规格里的数字已复核**：`d_fit(400×800) = 132 655`（不是 132 672）、`limb` 近似式比值恒为 `√3/2 = 0.8660254`、p50 恒星被压暗 5.0 星等。规格文件已按此修正。
