import 'models/planet.dart';

/// Hand-authored "hero" planets with rich, curated content. Everything else in
/// the universe is generated procedurally by [Universe] from the real star
/// catalogue; these are the few worlds that get bespoke stories. Each is
/// anchored to a real star system (see Universe's hero-anchor map).
class GalaxyData {
  GalaxyData._();

  /// Legacy home id (now just one of the hero worlds, anchored to Sol).
  static const String homeId = 'haven';

  /// The hand-authored hero planets, injected into the universe at their
  /// anchor stars.
  static List<Planet> heroes() => const <Planet>[
        _haven,
        _ashenReach,
        _azureVeil,
        _ithara,
        _hero4,
        _hero5,
      ];

  // --- Hero planets --------------------------------------------------------

  static const Planet _haven = Planet(
    id: homeId,
    name: '港湾中枢',
    designation: 'SW-000',
    type: PlanetType.civilization,
    coordinateX: 0,
    coordinateY: 0,
    seedColor: 0xFF7FE3E0,
    description: '你启程的地方。一座漂浮在恒星余晖中的宁静空间站，所有远征都从这里出发。',
    intel: '补给充足，适合作为所有航线的起点。',
    featured: true,
  );

  static const Planet _ashenReach = Planet(
    id: 'ashen-reach',
    name: '灰烬之境',
    designation: 'SW-017',
    type: PlanetType.dead,
    coordinateX: 210,
    coordinateY: -140,
    seedColor: 0xFF8A94A6,
    description: '一颗沉默的灰蓝色岩石行星，遥远的恒星只投下微弱的光。空旷、安静，却有一种壮丽的孤独。',
    intel: '地表探测到异常矿物信号与疑似人造结构的轮廓。',
    featured: true,
    pointsOfInterest: <PointOfInterest>[
      PointOfInterest(
        id: 'ashen-ridge',
        label: '扫描裂谷地貌',
        discoveryType: 'terrain',
        discoveryTitle: '玄武岩裂谷',
        discoveryDescription: '一道贯穿地表数公里的古老裂谷，谷壁的层理记录着这颗星球冷却凝固的漫长岁月。',
        x: 0.26,
        y: 0.62,
      ),
      PointOfInterest(
        id: 'ashen-mineral',
        label: '采集矿物样本',
        discoveryType: 'mineral',
        discoveryTitle: '幽蓝晶簇',
        discoveryDescription: '一簇在真空中仍泛着冷光的晶体，内部封存着微量的未知放射性元素。',
        x: 0.68,
        y: 0.55,
      ),
      PointOfInterest(
        id: 'ashen-ruin',
        label: '调查异常轮廓',
        discoveryType: 'ruin',
        discoveryTitle: '无名者的方碑',
        discoveryDescription: '半埋在尘土中的黑色方碑，表面的刻痕既非自然形成，也无法与任何已知文明对应。',
        x: 0.5,
        y: 0.3,
      ),
    ],
  );

  static const Planet _azureVeil = Planet(
    id: 'azure-veil',
    name: '蓝雾星',
    designation: 'SW-042',
    type: PlanetType.alive,
    coordinateX: -260,
    coordinateY: 180,
    seedColor: 0xFF8EE6B0,
    description: '笼罩在青绿色薄雾中的生命星球。发光的植被沿着水域生长，空气里漂浮着微弱的孢子。',
    intel: '大气含氧，探测到活跃的生物电信号。',
    featured: true,
    pointsOfInterest: <PointOfInterest>[
      PointOfInterest(
        id: 'veil-grove',
        label: '观察发光林',
        discoveryType: 'flora',
        discoveryTitle: '夜光蕨林',
        discoveryDescription: '一整片随呼吸般明灭的蕨类植物，它们用光而非声音彼此交流。',
        x: 0.3,
        y: 0.52,
      ),
      PointOfInterest(
        id: 'veil-pool',
        label: '靠近青色水域',
        discoveryType: 'lifeform',
        discoveryTitle: '潮汐游群',
        discoveryDescription: '水面下成群游动的半透明生物，它们的身体会折射出整片天空的颜色。',
        x: 0.62,
        y: 0.68,
      ),
      PointOfInterest(
        id: 'veil-spore',
        label: '追踪漂浮孢子',
        discoveryType: 'lifeform',
        discoveryTitle: '远行孢子',
        discoveryDescription: '一种能借助星风离开大气层的孢子，也许生命正是以这种方式在星海间旅行。',
        x: 0.48,
        y: 0.28,
      ),
    ],
  );

  static const Planet _ithara = Planet(
    id: 'ithara',
    name: '伊瑟拉',
    designation: 'SW-071',
    type: PlanetType.civilization,
    coordinateX: 150,
    coordinateY: 340,
    seedColor: 0xFFF2C879,
    description: '一座结构奇异的异星都市在暮色中亮起暖金色的灯火，远方矗立着难以理解其用途的宏伟建筑。',
    intel: '接收到有规律的问候信号，文明等级：星际早期。',
    featured: true,
    pointsOfInterest: <PointOfInterest>[
      PointOfInterest(
        id: 'ithara-spire',
        label: '仰望中央尖塔',
        discoveryType: 'civilization',
        discoveryTitle: '织光尖塔',
        discoveryDescription: '一座将恒星光线编织成信息的高塔，整座城市的记忆都储存在它流动的光纹里。',
        x: 0.5,
        y: 0.34,
      ),
      PointOfInterest(
        id: 'ithara-market',
        label: '走近集市灯火',
        discoveryType: 'civilization',
        discoveryTitle: '无声集市',
        discoveryDescription: '居民以颜色的变化进行交易，整条街道像一首缓慢流动的、沉默的乐曲。',
        x: 0.3,
        y: 0.64,
      ),
      PointOfInterest(
        id: 'ithara-envoy',
        label: '回应问候信号',
        discoveryType: 'signal',
        discoveryTitle: '伊瑟拉的问候',
        discoveryDescription: '一段简短的讯息，大意是：“旅人，你走了这么远，愿你带着的光比来时更亮。”',
        x: 0.7,
        y: 0.56,
      ),
    ],
  );

  static const Planet _hero4 = Planet(
    id: 'cinder-halo',
    name: '余烬环',
    designation: 'SW-088',
    type: PlanetType.dead,
    coordinateX: -420,
    coordinateY: -300,
    seedColor: 0xFFF2998A,
    description: '一颗被珊瑚色尘环缠绕的死寂行星，环带中漂浮着上一个时代留下的残骸。',
    intel: '尘环中探测到金属反射信号。',
    featured: true,
    pointsOfInterest: <PointOfInterest>[
      PointOfInterest(
        id: 'cinder-ring',
        label: '扫描尘环残骸',
        discoveryType: 'ruin',
        discoveryTitle: '沉默舰骸',
        discoveryDescription: '一艘早已失去动力的远古飞船残骸，静静环绕着它曾想抵达的星球。',
        x: 0.55,
        y: 0.45,
      ),
      PointOfInterest(
        id: 'cinder-crater',
        label: '勘测撞击坑',
        discoveryType: 'terrain',
        discoveryTitle: '新生陨坑',
        discoveryDescription: '一处边缘仍然锋利的撞击坑，底部的玻璃质地面映出头顶缓慢旋转的尘环。',
        x: 0.35,
        y: 0.62,
      ),
    ],
  );

  static const Planet _hero5 = Planet(
    id: 'verdant-drift',
    name: '翠漂星',
    designation: 'SW-104',
    type: PlanetType.alive,
    coordinateX: 480,
    coordinateY: 120,
    seedColor: 0xFF9FE0C0,
    description: '一颗几乎被海洋覆盖的温柔星球，大陆像漂浮的绿色岛屿散落在粼粼波光之间。',
    intel: '海洋中存在大规模生物发光现象。',
    featured: true,
    pointsOfInterest: <PointOfInterest>[
      PointOfInterest(
        id: 'verdant-isle',
        label: '登陆漂浮岛',
        discoveryType: 'flora',
        discoveryTitle: '随波之林',
        discoveryDescription: '扎根在浮岛上的树木会随着洋流缓慢迁徙，一生都在环游自己的星球。',
        x: 0.4,
        y: 0.5,
      ),
      PointOfInterest(
        id: 'verdant-glow',
        label: '观察海面微光',
        discoveryType: 'lifeform',
        discoveryTitle: '潮光',
        discoveryDescription: '每当夜幕降临，整片海洋会亮起柔和的蓝光，像把星空倒映进了水里。',
        x: 0.64,
        y: 0.66,
      ),
    ],
  );
}
