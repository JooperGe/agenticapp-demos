import 'engine.dart';

/// The player's vessel.
///
/// The hull is deliberately thin: it carries identity and a fitted [Engine],
/// and nothing else. Voyage cost and duration are read off the engine, so
/// refitting is a matter of swapping that one field — the ship, the player
/// state, and the journey rules all stay as they are.
class Ship {
  const Ship({
    required this.id,
    required this.name,
    required this.engine,
  });

  final String id;
  final String name;

  /// The fitted power source. See [withEngine] to change it.
  final Engine engine;

  /// Fits [engine], leaving the hull untouched. Returns a new [Ship] — a refit
  /// is a value change, not a mutation, so the old ship stays valid for anyone
  /// still holding it.
  Ship withEngine(Engine engine) =>
      Ship(id: id, name: name, engine: engine);

  /// The ship every new save starts with.
  static const Ship standard = Ship(
    id: 'ship.standard',
    name: '标准探索艇',
    engine: Engine.standard,
  );

  factory Ship.fromJson(Map<String, dynamic> json) => Ship(
        id: json['id'] as String,
        name: json['name'] as String,
        engine: Engine.fromJson(json['engine'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'engine': engine.toJson(),
      };
}
