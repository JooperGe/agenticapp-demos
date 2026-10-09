import 'geometry.dart';
import 'scene_model.dart';

class WorldModel {
  const WorldModel({required this.scenes});

  final Map<SceneId, SceneModel> scenes;

  factory WorldModel.demo() {
    const street = SceneModel(
      id: SceneId.street,
      bounds: Bounds2(0, 0, 24, 24),
      spawn: Point2(1.5, 1.5),
      obstacles: <Obstacle>[
        Obstacle(Bounds2(2, 2, 6, 6)),
        Obstacle(Bounds2(9, 2, 13, 6)),
        Obstacle(Bounds2(16, 2, 20, 6)),
        Obstacle(Bounds2(2, 9, 6, 13)),
        Obstacle(Bounds2(16, 9, 20, 13)),
        Obstacle(Bounds2(2, 16, 6, 20)),
        Obstacle(Bounds2(9, 16, 13, 20)),
        Obstacle(Bounds2(16, 16, 20, 20)),
      ],
      entrances: <Entrance>[
        // (2,2,6,6) coffee shop - right edge faces the vertical road.
        Entrance(
          id: 'coffee-shop',
          position: Point2(6.75, 4),
          radius: 0.7,
          targetScene: SceneId.coffeeShop,
          targetSpawn: Point2(2, 6),
          returnPosition: Point2(6.75, 4),
          safeReturnPosition: Point2(7.3, 4),
        ),
        // (9,2,13,6) convenience store - bottom edge faces the horizontal road.
        Entrance(
          id: 'convenience-store',
          position: Point2(11, 6.75),
          radius: 0.7,
          targetScene: SceneId.convenienceStore,
          targetSpawn: Point2(2, 6),
          returnPosition: Point2(11, 6.75),
          safeReturnPosition: Point2(11, 7.6),
        ),
        // (16,2,20,6) office A - left edge faces the vertical road.
        Entrance(
          id: 'office-a',
          position: Point2(15.25, 4),
          radius: 0.7,
          targetScene: SceneId.officeA,
          targetSpawn: Point2(2, 6),
          returnPosition: Point2(15.25, 4),
          safeReturnPosition: Point2(14.6, 4),
        ),
        // (2,9,6,13) residential A - right edge faces the vertical road.
        Entrance(
          id: 'residential-a',
          position: Point2(6.75, 11),
          radius: 0.7,
          targetScene: SceneId.residentialA,
          targetSpawn: Point2(2, 6),
          returnPosition: Point2(6.75, 11),
          safeReturnPosition: Point2(7.3, 11),
        ),
        // (16,9,20,13) residential B - left edge faces the vertical road.
        Entrance(
          id: 'residential-b',
          position: Point2(15.25, 11),
          radius: 0.7,
          targetScene: SceneId.residentialB,
          targetSpawn: Point2(2, 6),
          returnPosition: Point2(15.25, 11),
          safeReturnPosition: Point2(14.6, 11),
        ),
        // (2,16,6,20) corner shop A - right edge faces the vertical road.
        Entrance(
          id: 'corner-shop-a',
          position: Point2(6.75, 18),
          radius: 0.7,
          targetScene: SceneId.cornerShopA,
          targetSpawn: Point2(2, 6),
          returnPosition: Point2(6.75, 18),
          safeReturnPosition: Point2(7.3, 18),
        ),
        // (9,16,13,20) office B - top edge faces the horizontal road.
        Entrance(
          id: 'office-b',
          position: Point2(11, 15.25),
          radius: 0.7,
          targetScene: SceneId.officeB,
          targetSpawn: Point2(2, 6),
          returnPosition: Point2(11, 15.25),
          safeReturnPosition: Point2(11, 14.6),
        ),
        // (16,16,20,20) corner shop B - left edge faces the vertical road.
        Entrance(
          id: 'corner-shop-b',
          position: Point2(15.25, 18),
          radius: 0.7,
          targetScene: SceneId.cornerShopB,
          targetSpawn: Point2(2, 6),
          returnPosition: Point2(15.25, 18),
          safeReturnPosition: Point2(14.6, 18),
        ),
      ],
    );
    return const WorldModel(
      scenes: <SceneId, SceneModel>{
        SceneId.street: street,
        SceneId.coffeeShop: _coffeeShop,
        SceneId.convenienceStore: _convenienceStore,
        SceneId.officeA: _officeA,
        SceneId.officeB: _officeB,
        SceneId.residentialA: _residentialA,
        SceneId.residentialB: _residentialB,
        SceneId.cornerShopA: _cornerShopA,
        SceneId.cornerShopB: _cornerShopB,
      },
    );
  }
}

// --- Interior layout templates -------------------------------------------
// Interiors are drawn from illustrated room images whose furniture is baked
// in, so the floor is left fully walkable (no collision obstacles). The named
// templates are kept as hooks in case a procedural interior needs furniture
// collision again.

const _cafeLayout = <Obstacle>[];

const _shopLayout = <Obstacle>[];

const _roomLayout = <Obstacle>[];

// Each interior exits back to the street next to its own building. The exit's
// return/safe positions mirror the street entrance that leads here.
const _coffeeShop = SceneModel(
  id: SceneId.coffeeShop,
  bounds: Bounds2(0, 0, 10, 10),
  spawn: Point2(2, 6),
  obstacles: _cafeLayout,
  entrances: <Entrance>[
    Entrance(
      id: 'coffee-shop-exit',
      position: Point2(1, 6),
      radius: 0.7,
      targetScene: SceneId.street,
      targetSpawn: Point2(6.75, 4),
      returnPosition: Point2(6.75, 4),
      safeReturnPosition: Point2(7.3, 4),
    ),
  ],
);

const _convenienceStore = SceneModel(
  id: SceneId.convenienceStore,
  bounds: Bounds2(0, 0, 10, 10),
  spawn: Point2(2, 6),
  obstacles: _shopLayout,
  entrances: <Entrance>[
    Entrance(
      id: 'convenience-store-exit',
      position: Point2(1, 6),
      radius: 0.7,
      targetScene: SceneId.street,
      targetSpawn: Point2(11, 6.75),
      returnPosition: Point2(11, 6.75),
      safeReturnPosition: Point2(11, 7.6),
    ),
  ],
);

const _officeA = SceneModel(
  id: SceneId.officeA,
  bounds: Bounds2(0, 0, 10, 10),
  spawn: Point2(2, 6),
  obstacles: _roomLayout,
  entrances: <Entrance>[
    Entrance(
      id: 'office-a-exit',
      position: Point2(1, 6),
      radius: 0.7,
      targetScene: SceneId.street,
      targetSpawn: Point2(15.25, 4),
      returnPosition: Point2(15.25, 4),
      safeReturnPosition: Point2(14.6, 4),
    ),
  ],
);

const _officeB = SceneModel(
  id: SceneId.officeB,
  bounds: Bounds2(0, 0, 10, 10),
  spawn: Point2(2, 6),
  obstacles: _roomLayout,
  entrances: <Entrance>[
    Entrance(
      id: 'office-b-exit',
      position: Point2(1, 6),
      radius: 0.7,
      targetScene: SceneId.street,
      targetSpawn: Point2(11, 15.25),
      returnPosition: Point2(11, 15.25),
      safeReturnPosition: Point2(11, 14.6),
    ),
  ],
);

const _residentialA = SceneModel(
  id: SceneId.residentialA,
  bounds: Bounds2(0, 0, 10, 10),
  spawn: Point2(2, 6),
  obstacles: _cafeLayout,
  entrances: <Entrance>[
    Entrance(
      id: 'residential-a-exit',
      position: Point2(1, 6),
      radius: 0.7,
      targetScene: SceneId.street,
      targetSpawn: Point2(6.75, 11),
      returnPosition: Point2(6.75, 11),
      safeReturnPosition: Point2(7.3, 11),
    ),
  ],
);

const _residentialB = SceneModel(
  id: SceneId.residentialB,
  bounds: Bounds2(0, 0, 10, 10),
  spawn: Point2(2, 6),
  obstacles: _cafeLayout,
  entrances: <Entrance>[
    Entrance(
      id: 'residential-b-exit',
      position: Point2(1, 6),
      radius: 0.7,
      targetScene: SceneId.street,
      targetSpawn: Point2(15.25, 11),
      returnPosition: Point2(15.25, 11),
      safeReturnPosition: Point2(14.6, 11),
    ),
  ],
);

const _cornerShopA = SceneModel(
  id: SceneId.cornerShopA,
  bounds: Bounds2(0, 0, 10, 10),
  spawn: Point2(2, 6),
  obstacles: _shopLayout,
  entrances: <Entrance>[
    Entrance(
      id: 'corner-shop-a-exit',
      position: Point2(1, 6),
      radius: 0.7,
      targetScene: SceneId.street,
      targetSpawn: Point2(6.75, 18),
      returnPosition: Point2(6.75, 18),
      safeReturnPosition: Point2(7.3, 18),
    ),
  ],
);

const _cornerShopB = SceneModel(
  id: SceneId.cornerShopB,
  bounds: Bounds2(0, 0, 10, 10),
  spawn: Point2(2, 6),
  obstacles: _shopLayout,
  entrances: <Entrance>[
    Entrance(
      id: 'corner-shop-b-exit',
      position: Point2(1, 6),
      radius: 0.7,
      targetScene: SceneId.street,
      targetSpawn: Point2(15.25, 18),
      returnPosition: Point2(15.25, 18),
      safeReturnPosition: Point2(14.6, 18),
    ),
  ],
);
