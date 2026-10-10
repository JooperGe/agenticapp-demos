# Starward · 星际漫游

一款治愈系宇宙探索 MVP：现实中的运动为飞船补充能量，飞船带你穿越星海，抵达并探索一颗颗星球。

打开 App → 查看星图 → 选择星球 → 消耗能量出发 → 观看航行 → 抵达 → 探索发现 → 记入日志 → 返回星图，开始下一次远征。

## 运行 / 构建 / 测试

```bash
# 获取依赖
flutter pub get

# 运行（优先 Android；也可 iOS）
flutter run

# 静态检查（应为 No issues found）
flutter analyze

# 运行测试
flutter test

# 构建 Android 调试包 / 发布包
flutter build apk --debug
flutter build apk --release
```

环境：Flutter 3.47+ / Dart 3.13+。依赖仅 `flame`（航行与星图的实时绘制）与 `shared_preferences`（本地持久化）。

## 架构

分层清晰，UI 不直接读写存储，全部经由状态控制器。

- `lib/core/` — `theme.dart`（深空视觉语言、颜色、面板样式）、`balance.dart`（**所有可调数值集中于此**：能量成本、航行时长、奖励、距离分级）。
- `lib/data/` — 领域层：
  - `models/` 不可变数据模型（Planet / Journey / PlayerState / DiscoveryRecord / EnergyTransaction / TrainingSession），均带 JSON 序列化。
  - `storage/` `StorageBackend` 抽象接口 + `PrefsStorage`（设备）/`MemoryStorage`（测试），**为未来云端同步预留替换点**。
  - `galaxy_data.dart` 固定星图种子数据（5 颗手工设计的英雄星球 + 36 颗以常量种子确定性生成的背景星球，共 41 颗；每次启动完全一致，绝不重随机）。
  - `game_repository.dart` 整存整取一份 JSON 存档。
- `lib/state/game_controller.dart` — `ChangeNotifier`，承载全部规则：能量原子扣除、单一进行中航行、基于时间戳的航行进度、抵达重算、探索完成与奖励、训练一次性领取。可注入时钟（`clock`）便于测试。
- `lib/ui/` — 页面层：
  - `shell/` 底部四标签导航（星图 / 航行 / 发现 / 训练）。
  - `galaxy/` 可拖拽缩放的星图 + 星球详情面板。
  - `journey/` 自动航行氛围页。
  - `exploration/` 三种差异化星球探索场景（死寂 / 生命 / 文明）。
  - `training/` 分步训练课程与能量补给。
  - `discovery/` 探索日志收藏册。
  - `widgets/` 复用组件：`PlanetDisc`（程序化星球）、`StarfieldBackground`（星场）、`StarPanel`/`EnergyBadge`/`StarLabels`。

状态注入用轻量的 `GameScope`（`InheritedNotifier`），不引入额外状态管理依赖。注意：通过 `Navigator.push` 打开的全屏路由（探索、训练流程）需重新包一层 `GameScope`。

## 航行状态逻辑

进度完全由时间戳推导，不依赖常驻计时器：

```
progress  = clamp((now - departure) / (arrival - departure), 0, 1)
remaining = max(arrival - now, 0)
```

因此退出 App、进入后台、甚至被系统杀死后重启，航行都会继续并在重新打开时恢复正确状态（`GameController.init()` 会在加载存档后调用 `_reconcileJourney()` 补算抵达）。同一时间最多一条进行中的航行，能量在校验全部通过后才原子扣除，杜绝重复扣费与负数。

测试用航行时长（见 `balance.dart`，非最终平衡数值）：短途 ~1.5 分、中途 7 分、长途 25 分。

## 3D 星图与真实星表（HYG）

「星图」页为伪 3D 实现：天体带真实三维坐标，经透视相机投影到 2D 画布（`lib/ui/galaxy3d/`），支持拖动旋转、双指缩放、总览/座舱双视角、以及按飞行器"传感器范围"解析星球（千人千面的接口）。

背景星空接入了**完整 HYG 星表**（Hipparcos/Yale/Gliese，约 11 万颗真实恒星，CC BY-SA 4.0）：

- 原始数据：`github.com/astronexus/HYG-Database`（`hygdata_v41.csv`，约 32MB，不入库）。
- 预处理工具：`tool/build_hyg.dart` 解析 CSV → 丢弃无视差星 → 轴向对齐（北天极朝上）→ 秒差距转光年 → B-V 色指数转 RGB → 按星等从亮到暗排序 → 输出紧凑二进制。
- 产物（已入库，约 2.1MB）：`assets/stars/hyg.bin`（每星 20 字节）+ `assets/stars/hyg_named.json`（461 颗具名星，用于标注与锚定）。
- 运行时：`lib/data/hyg_catalog.dart` 读入 `Float32List`/`Int32List` 定长数组；渲染走免分配、亮度优先、绘制上限（5000）的快路径，保证帧率。
- 重新生成：`dart run tool/build_hyg.dart /path/to/hygdata_v41.csv`

几颗手工英雄星球锚定在真实星系附近（港湾中枢→太阳、灰烬之境→天狼星、伊瑟拉→织女星等），坐标与现实星空一致。

## 视觉素材说明

所有星球、星场、探索场景均为**程序化绘制**（`CustomPainter` + 渐变 + 噪声），不依赖任何远程图片，完全离线可用，且同一星球每次渲染一致。后续若接入位图美术，只需替换 `PlanetDisc` 等绘制组件的实现，调用点无需改动（模块化、可替换）。

## 测试覆盖

`test/` 下的测试覆盖核心逻辑：
- `journey_test.dart` — 时间戳进度、clamp、重启后抵达恢复、单一航行约束。
- `energy_test.dart` — 扣费准确、余额不足拦截、永不为负、交易记账、训练奖励一次性。
- `exploration_test.dart` — 发现去重、探索完成与一次性奖励、重启后状态持久。
- `widget_smoke_test.dart` — 四个标签页整体可构建、可切换。

## 未来扩展

- 存储接口已抽象，可替换为云端后端实现多端同步。
- 二维星图坐标可扩展为三维。
- 背景星球目前为通用内容，可逐步补充手工设计的目的地。
