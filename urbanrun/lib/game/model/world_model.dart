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
        Entrance(
          id: 'coffee-shop',
          position: Point2(6.75, 4),
          radius: 0.7,
          targetScene: SceneId.coffeeShop,
          targetSpawn: Point2(2, 6),
          returnPosition: Point2(6.75, 4),
          safeReturnPosition: Point2(7.5, 4),
        ),
        Entrance(
          id: 'convenience-store',
          position: Point2(13.75, 11),
          radius: 0.7,
          targetScene: SceneId.convenienceStore,
          targetSpawn: Point2(2, 6),
          returnPosition: Point2(13.75, 11),
          safeReturnPosition: Point2(14.5, 11),
        ),
      ],
    );
    const coffeeShop = SceneModel(
      id: SceneId.coffeeShop,
      bounds: Bounds2(0, 0, 10, 8),
      spawn: Point2(2, 6),
      obstacles: <Obstacle>[
        Obstacle(Bounds2(2, 1, 4, 3)),
        Obstacle(Bounds2(6, 1, 8, 3)),
        Obstacle(Bounds2(4, 5, 6, 6)),
      ],
      entrances: <Entrance>[
        Entrance(
          id: 'coffee-shop-exit',
          position: Point2(1, 6),
          radius: 0.7,
          targetScene: SceneId.street,
          targetSpawn: Point2(6.75, 4),
          returnPosition: Point2(6.75, 4),
        ),
      ],
    );
    const convenienceStore = SceneModel(
      id: SceneId.convenienceStore,
      bounds: Bounds2(0, 0, 10, 8),
      spawn: Point2(2, 6),
      obstacles: <Obstacle>[
        Obstacle(Bounds2(1, 1, 3, 5)),
        Obstacle(Bounds2(5, 1, 7, 5)),
        Obstacle(Bounds2(8, 2, 9, 4)),
      ],
      entrances: <Entrance>[
        Entrance(
          id: 'convenience-store-exit',
          position: Point2(1, 6),
          radius: 0.7,
          targetScene: SceneId.street,
          targetSpawn: Point2(13.75, 11),
          returnPosition: Point2(13.75, 11),
        ),
      ],
    );
    return const WorldModel(
      scenes: <SceneId, SceneModel>{
        SceneId.street: street,
        SceneId.coffeeShop: coffeeShop,
        SceneId.convenienceStore: convenienceStore,
      },
    );
  }
}
