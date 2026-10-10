import 'dart:convert';

import 'models/discovery_record.dart';
import 'models/energy_transaction.dart';
import 'models/journey.dart';
import 'models/player_state.dart';
import 'models/training_session.dart';
import 'storage/storage_backend.dart';

/// The full persisted snapshot of a save. Everything the game needs to resume
/// is bundled here and written atomically as one JSON blob.
class GameSave {
  const GameSave({
    required this.player,
    required this.activeJourney,
    required this.discoveries,
    required this.energyLedger,
    required this.trainingSessions,
    required this.planetStates,
  });

  final PlayerState player;
  final Journey? activeJourney;
  final List<DiscoveryRecord> discoveries;
  final List<EnergyTransaction> energyLedger;
  final List<TrainingSession> trainingSessions;

  /// Per-planet discovery-state overrides keyed by planet id. Only non-default
  /// states are stored; a missing entry means "undiscovered".
  final Map<String, String> planetStates;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'player': player.toJson(),
        'activeJourney': activeJourney?.toJson(),
        'discoveries': discoveries.map((e) => e.toJson()).toList(),
        'energyLedger': energyLedger.map((e) => e.toJson()).toList(),
        'trainingSessions':
            trainingSessions.map((e) => e.toJson()).toList(),
        'planetStates': planetStates,
      };

  factory GameSave.fromJson(Map<String, dynamic> json) => GameSave(
        player: PlayerState.fromJson(json['player'] as Map<String, dynamic>),
        activeJourney: json['activeJourney'] == null
            ? null
            : Journey.fromJson(json['activeJourney'] as Map<String, dynamic>),
        discoveries: (json['discoveries'] as List<dynamic>)
            .map((e) => DiscoveryRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
        energyLedger: (json['energyLedger'] as List<dynamic>)
            .map((e) => EnergyTransaction.fromJson(e as Map<String, dynamic>))
            .toList(),
        trainingSessions: (json['trainingSessions'] as List<dynamic>)
            .map((e) => TrainingSession.fromJson(e as Map<String, dynamic>))
            .toList(),
        planetStates:
            (json['planetStates'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v as String),
        ),
      );
}

/// Reads and writes [GameSave]s through a [StorageBackend]. The UI never
/// touches storage directly — it goes through the controller which goes
/// through here.
class GameRepository {
  GameRepository(this._storage);

  final StorageBackend _storage;

  // Bump when the save schema or spawn/universe logic changes in a way that
  // should abandon old saves (so the change actually takes effect on existing
  // installs without a manual data-clear).
  static const String _saveKey = 'starward.save.v2';

  Future<GameSave?> load() async {
    final raw = await _storage.read(_saveKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return GameSave.fromJson(json);
    } catch (_) {
      // Corrupt save — treat as a fresh start rather than crashing the app.
      return null;
    }
  }

  Future<void> save(GameSave save) async {
    await _storage.write(_saveKey, jsonEncode(save.toJson()));
  }

  Future<void> clear() => _storage.delete(_saveKey);
}
