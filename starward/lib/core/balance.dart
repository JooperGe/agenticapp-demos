/// Central game-balance configuration.
///
/// Only numbers that belong to *no single entity* live here — the economy
/// knobs that span the whole game (what a new player starts with, what a
/// discovery pays out).
///
/// Attributes of a thing belong to that thing instead. Voyage cost and
/// duration are properties of the ship's engine, so they live on `Engine`
/// (`lib/data/models/engine.dart`); when a number is about one entity, put it
/// on that entity rather than back in this table, or the entity can never be
/// tuned, upgraded, or replaced on its own.
class Balance {
  Balance._();

  /// Starting energy for a fresh save.
  static const int initialEnergy = 300;

  /// A small bonus granted the first time a planet is fully explored.
  static const int explorationReward = 15;
}
