import 'dart:math' as math;

import '../core/vec3.dart';
import 'galaxy_data.dart';
import 'hyg_catalog.dart';
import 'models/planet.dart';

/// Bump when the generation algorithm or star catalogue changes in a way that
/// would move planets. Baked into every planet id (`p<version>-<star>-<n>`) so
/// a future server and clients always agree on which planet is which, and old
/// data can be migrated rather than silently mismatched.
const int kUniverseVersion = 1;

/// The procedural universe: every real star system in the HYG catalogue can
/// host game planets, generated deterministically from the star's stable id.
/// Nothing is stored — planets are regenerated identically on demand, so the
/// whole universe costs ~zero bytes beyond the already-bundled star catalogue.
///
/// A handful of hand-authored "hero" planets are injected at real anchor stars.
class Universe {
  Universe(this.stars, {this.extraGalaxies = const <HygStars>[]}) {
    _buildHeroes();
  }

  final HygStars stars;

  /// Additional (fictional) galaxies placed elsewhere in the sky. Treated just
  /// like the real catalogue for rendering, planet generation and lookups.
  final List<HygStars> extraGalaxies;

  // heroId -> authored content; hygId -> hero; heroId -> host hygId.
  final Map<String, Planet> _heroById = <String, Planet>{};
  final Map<int, Planet> _heroByStar = <int, Planet>{};
  final Map<String, int> _heroStar = <String, int>{};

  static const Map<String, String> _heroAnchors = <String, String>{
    'haven': 'Sol',
    'ashen-reach': 'Sirius',
    'azure-veil': 'Procyon',
    'ithara': 'Vega',
    'cinder-halo': 'Altair',
    'verdant-drift': 'Fomalhaut',
  };

  void _buildHeroes() {
    for (final p in GalaxyData.heroes()) {
      _heroById[p.id] = p;
      final starName = _heroAnchors[p.id];
      final named = starName == null ? null : stars.named[starName];
      if (named != null) {
        _heroByStar[named.id] = p;
        _heroStar[p.id] = named.id;
      }
    }
  }

  // --- Generation ----------------------------------------------------------

  math.Random _rngFor(int a, [int b = 0]) =>
      math.Random((a * 1000003 + b * 97 + 17) ^ (kUniverseVersion * 0x9E3779B1));

  /// How many procedural planets a star hosts (0..3), deterministic by id.
  int planetCountForStar(int hygId) {
    final r = _rngFor(hygId).nextDouble();
    if (r < 0.55) return 0;
    if (r < 0.80) return 1;
    if (r < 0.93) return 2;
    return 3;
  }

  /// All planets around one star (by catalogue index): its hero, if any, plus
  /// its procedural worlds.
  List<Planet> planetsForStarIndex(int index) {
    final hygId = stars.starId[index];
    final starPos = stars.positionOfIndex(index);
    return _planetsForStar(hygId, starPos);
  }

  /// All planets of a star identified by its stable id, across the real
  /// catalogue and extra galaxies. Empty if the star isn't found.
  List<Planet> planetsAtStar(int hygId) {
    final pos = _posById(hygId);
    if (pos == null) return const <Planet>[];
    return _planetsForStar(hygId, pos);
  }

  /// A human label for a star by id — its proper name if it has one, else a
  /// catalogue designation.
  String starLabel(int hygId) {
    for (final s in <HygStars>[stars, ...extraGalaxies]) {
      for (final n in s.named.values) {
        if (n.id == hygId) return n.name;
      }
    }
    return '恒星系 SW-$hygId';
  }

  List<Planet> _planetsForStar(int hygId, Vec3 starPos) {
    final out = <Planet>[];
    final hero = _heroByStar[hygId];
    if (hero != null) {
      out.add(hero.copyWith(positionLy: starPos + _heroOffset(hygId)));
    }
    final n = planetCountForStar(hygId);
    for (var k = 0; k < n; k++) {
      out.add(_genPlanet(hygId, starPos, k));
    }
    return out;
  }

  Vec3 _heroOffset(int hygId) {
    final rng = _rngFor(hygId, 777);
    return _spherePoint(rng, 1.4, 2.6);
  }

  Planet _genPlanet(int hygId, Vec3 starPos, int k) {
    final rng = _rngFor(hygId, k + 1);
    final type = _pickType(rng);
    final color = _pickColor(type, rng);
    final pos = starPos + _spherePoint(rng, 0.6, 2.6);
    final id = 'p$kUniverseVersion-$hygId-$k';
    return Planet(
      id: id,
      name: _genName(rng),
      designation: 'SW-$hygId-${k + 1}',
      type: type,
      coordinateX: 0,
      coordinateY: 0,
      seedColor: color,
      description: _descFor(type),
      intel: _intelFor(type),
      pointsOfInterest: _genPois(id, type, rng),
      positionLy: pos,
    );
  }

  // --- Lookup / queries ----------------------------------------------------

  /// Regenerates a planet from its id (hero or procedural). Null if the host
  /// star is not in the catalogue (e.g. a stale id from an older version).
  Planet? planetById(String id) {
    final hero = _heroById[id];
    if (hero != null) {
      final starId = _heroStar[id];
      final starPos = starId == null ? null : stars.positionOfId(starId);
      if (starId == null || starPos == null) return hero; // ultimate fallback
      return hero.copyWith(positionLy: starPos + _heroOffset(starId));
    }
    // Procedural: p<version>-<hygId>-<k>
    final parts = id.split('-');
    if (parts.length != 3) return null;
    final hygId = int.tryParse(parts[1]);
    final k = int.tryParse(parts[2]);
    if (hygId == null || k == null) return null;
    final starPos = _posById(hygId);
    if (starPos == null) return null;
    return _genPlanet(hygId, starPos, k);
  }

  /// Resolves a star's position by its stable id across the real catalogue and
  /// any extra galaxies.
  Vec3? _posById(int id) {
    final p = stars.positionOfId(id);
    if (p != null) return p;
    for (final g in extraGalaxies) {
      final q = g.positionOfId(id);
      if (q != null) return q;
    }
    return null;
  }

  /// The planets within [radiusLy] of [posLy], nearest first, capped at [cap].
  /// Used to populate the map / selection around the player without ever
  /// materialising the whole universe.
  List<Planet> planetsNear(Vec3 posLy, double radiusLy, {int cap = 80}) {
    final r2 = radiusLy * radiusLy;
    final found = <Planet>[];
    void scan(HygStars set) {
      for (var i = 0; i < set.count; i++) {
        final sx = set.xyz[i * 3] - posLy.x;
        final sy = set.xyz[i * 3 + 1] - posLy.y;
        final sz = set.xyz[i * 3 + 2] - posLy.z;
        if (sx * sx + sy * sy + sz * sz > r2) continue;
        found.addAll(_planetsForStar(
            set.starId[i], set.positionOfIndex(i)));
      }
    }

    scan(stars);
    for (final g in extraGalaxies) {
      scan(g);
    }
    found.sort((a, b) =>
        (a.pos - posLy).length.compareTo((b.pos - posLy).length));
    if (found.length > cap) return found.sublist(0, cap);
    return found;
  }

  /// A random drift coordinate near a random real star (in the Milky Way) that
  /// *has* at least one planet, so a new player always wakes up with somewhere
  /// to go nearby.
  Vec3 randomSpawn(math.Random rng) => _spawnNearStarIn(stars, rng);

  /// Picks one galaxy at random (the real Milky Way or any extra galaxy), then
  /// a random position within it near a planet-hosting star.
  Vec3 spawnInRandomGalaxy(math.Random rng) {
    final sets = <HygStars>[stars, ...extraGalaxies];
    final set = sets[rng.nextInt(sets.length)];
    return _spawnNearStarIn(set, rng);
  }

  /// Shared helper: a drift point just off a random planet-hosting star within
  /// [set].
  Vec3 _spawnNearStarIn(HygStars set, math.Random rng) {
    for (var attempt = 0; attempt < 64; attempt++) {
      final i = rng.nextInt(set.count);
      final hygId = set.starId[i];
      if (planetCountForStar(hygId) == 0 && !_heroByStar.containsKey(hygId)) {
        continue;
      }
      return set.positionOfIndex(i) + _spherePoint(rng, 1.5, 3.0);
    }
    // Extremely unlikely fallback: just offset from the set's first star.
    return set.positionOfIndex(0) + _spherePoint(rng, 2, 6);
  }

  /// A drift coordinate confined to the Solar System — just off the Sun, within
  /// roughly the Oort-cloud scale (~1 ly). The Sun hosts the 'haven' hero, so
  /// there is always a world right nearby.
  Vec3 spawnInSolarSystem(math.Random rng) {
    final sun = stars.positionOf('Sol') ?? const Vec3(0, 0, 0);
    return sun + _spherePoint(rng, 0.2, 0.9);
  }

  // --- Content templates ---------------------------------------------------

  Vec3 _spherePoint(math.Random rng, double minR, double maxR) {
    final u = rng.nextDouble() * 2 - 1;
    final theta = rng.nextDouble() * math.pi * 2;
    final r = minR + rng.nextDouble() * (maxR - minR);
    final s = math.sqrt(1 - u * u);
    return Vec3(r * s * math.cos(theta), r * u, r * s * math.sin(theta));
  }

  PlanetType _pickType(math.Random rng) {
    final r = rng.nextDouble();
    if (r < 0.50) return PlanetType.dead;
    if (r < 0.85) return PlanetType.alive;
    return PlanetType.civilization;
  }

  int _pickColor(PlanetType type, math.Random rng) {
    List<int> pool;
    switch (type) {
      case PlanetType.dead:
        pool = const <int>[0xFF8A94A6, 0xFF9AA3B5, 0xFFB0A79C, 0xFFF2998A];
        break;
      case PlanetType.alive:
        pool = const <int>[0xFF8EE6B0, 0xFF9FE0C0, 0xFF7FC9A6, 0xFF8ED0E6];
        break;
      case PlanetType.civilization:
        pool = const <int>[0xFFF2C879, 0xFFE8C27A, 0xFFC9A7E8, 0xFF7FE3E0];
        break;
    }
    return pool[rng.nextInt(pool.length)];
  }

  static const List<String> _prefixes = <String>[
    '塞', '维', '诺', '艾', '泽', '卡', '欧', '瑞', '努', '伊', '索', '卢',
    '米', '法', '赫', '提', '娜', '科', '瓦', '乌'
  ];
  static const List<String> _suffixes = <String>[
    '洛斯', '瑞恩', '塔', '尼亚', '德', '斯', '拉', '文', '姆', '西亚',
    '诺斯', '伽', '隆', '忒', '里斯'
  ];

  String _genName(math.Random rng) =>
      _prefixes[rng.nextInt(_prefixes.length)] +
      _suffixes[rng.nextInt(_suffixes.length)];

  String _descFor(PlanetType type) {
    switch (type) {
      case PlanetType.dead:
        return '一颗沉寂的星球，表面覆盖着风化的岩层与尘埃，恒星的光在这里显得格外遥远。';
      case PlanetType.alive:
        return '探测到活跃的生物信号，大气中漂浮着未知的有机物，某种生态正在这里悄然生长。';
      case PlanetType.civilization:
        return '轨道上残留着规律的人造信号，也许曾有、或仍有某个文明在此驻留。';
    }
  }

  String _intelFor(PlanetType type) {
    switch (type) {
      case PlanetType.dead:
        return '远程扫描：无大气、无液态水，地质活动微弱。';
      case PlanetType.alive:
        return '远程扫描：含氧大气，检出生物电活动。';
      case PlanetType.civilization:
        return '远程扫描：捕捉到结构化电磁脉冲。';
    }
  }

  List<PointOfInterest> _genPois(String planetId, PlanetType type, math.Random rng) {
    final pool = _poiPool(type);
    final count = 2 + rng.nextInt(2); // 2 or 3
    final indices = List<int>.generate(pool.length, (i) => i)..shuffle(rng);
    final picks = indices.take(count).toList();
    final out = <PointOfInterest>[];
    for (var i = 0; i < picks.length; i++) {
      final t = pool[picks[i]];
      out.add(PointOfInterest(
        id: '$planetId-poi$i',
        label: t[0],
        discoveryType: t[1],
        discoveryTitle: t[2],
        discoveryDescription: t[3],
        x: 0.22 + rng.nextDouble() * 0.56,
        y: 0.28 + rng.nextDouble() * 0.5,
      ));
    }
    return out;
  }

  List<List<String>> _poiPool(PlanetType type) {
    switch (type) {
      case PlanetType.dead:
        return const <List<String>>[
          <String>['扫描裂谷', 'terrain', '幽深峡谷', '一道贯穿地表的古老裂谷，谷壁层理记录着星球冷却凝固的漫长岁月。'],
          <String>['采集矿样', 'mineral', '异色晶簇', '一簇在真空中仍泛着冷光的晶体，内部封存着微量未知元素。'],
          <String>['勘测陨坑', 'terrain', '新生陨坑', '边缘仍然锋利的撞击坑，底部玻璃质地面映出遥远的恒星。'],
          <String>['调查异常', 'ruin', '无名结构', '半埋在尘土中的人造结构残片，无法与任何已知文明对应。'],
          <String>['追踪信号', 'signal', '微弱回响', '一段每隔数小时重复一次的微弱信号，来源不明。'],
        ];
      case PlanetType.alive:
        return const <List<String>>[
          <String>['观察植被', 'flora', '发光林', '随呼吸般明灭的植物群落，它们用光而非声音彼此交流。'],
          <String>['靠近水域', 'lifeform', '潮汐游群', '水面下成群游动的半透明生物，身体折射出整片天空的颜色。'],
          <String>['追踪孢子', 'lifeform', '远行孢子', '一种能借星风离开大气层的孢子——也许生命正以此方式在星海间旅行。'],
          <String>['勘测地表', 'flora', '苔原脉络', '覆盖大陆的苔原随昼夜变换颜色，像星球缓慢的呼吸。'],
          <String>['采集样本', 'lifeform', '微光菌落', '岩缝间的发光菌落，组成了只有在夜里才显现的图案。'],
        ];
      case PlanetType.civilization:
        return const <List<String>>[
          <String>['仰望建筑', 'civilization', '织光高塔', '一座将恒星光线编织成信息的高塔，城市的记忆储存在流动的光纹里。'],
          <String>['走近聚落', 'civilization', '无声集市', '居民以颜色变化进行交易，街道像一首缓慢流动的沉默乐曲。'],
          <String>['回应信号', 'signal', '来自远方的问候', '一段简短讯息，大意是：“旅人，愿你带着的光比来时更亮。”'],
          <String>['扫描遗迹', 'ruin', '沉睡机械', '仍在缓慢运转的古老机械，不知已独自运行了多少个世纪。'],
          <String>['观测轨道', 'signal', '轨道灯环', '环绕星球的人造灯环，按某种无法破译的节律明灭。'],
        ];
    }
  }
}

/// How a new player's first landing coordinate is chosen. A pure function of
/// the universe + an RNG, so landing policies can be added and swapped without
/// touching the controller or re-implementing anything.
typedef SpawnStrategy = Vec3 Function(Universe universe, math.Random rng);

/// The available landing policies.
enum SpawnMode {
  /// Anywhere in the Milky Way, near a random real star that has planets.
  randomUniverse,

  /// Confined to the Solar System (just off the Sun).
  solarSystem,

  /// Inside one randomly chosen galaxy (Milky Way or an extra galaxy).
  randomGalaxy,
}

/// Flip this one line (or inject a strategy into [GameController]) to change
/// where new players start — kept in a single place for easy back-and-forth
/// switching.
const SpawnMode kDefaultSpawnMode = SpawnMode.solarSystem;

/// Registry mapping a [SpawnMode] to its concrete [SpawnStrategy].
class SpawnStrategies {
  SpawnStrategies._();

  static SpawnStrategy of(SpawnMode mode) {
    switch (mode) {
      case SpawnMode.randomUniverse:
        return randomUniverse;
      case SpawnMode.solarSystem:
        return solarSystem;
      case SpawnMode.randomGalaxy:
        return randomGalaxy;
    }
  }

  /// Near a random real star in the Milky Way.
  static Vec3 randomUniverse(Universe u, math.Random rng) => u.randomSpawn(rng);

  /// Restrict the landing to within the Solar System.
  static Vec3 solarSystem(Universe u, math.Random rng) =>
      u.spawnInSolarSystem(rng);

  /// Inside one randomly chosen galaxy, at a random position.
  static Vec3 randomGalaxy(Universe u, math.Random rng) =>
      u.spawnInRandomGalaxy(rng);
}