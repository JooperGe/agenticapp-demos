/// What a ledger entry is for.
///
/// The enum *name* is the save key — see [energyTxTypeFromName] — so members may
/// be added but never renamed.
enum EnergyTxType {
  travelCost,
  trainingReward,
  explorationReward,
  braking,

  /// A powered drift's continuous draw. One entry per leg, booked when the leg
  /// ends — on a turn, on a brake, or when the tank runs dry.
  cruiseCost,

  /// A heading correction, priced by the angle turned.
  turn,

  /// The flat fee that brings a dormant engine back online.
  activation,
}

EnergyTxType energyTxTypeFromName(String name) =>
    EnergyTxType.values.firstWhere((t) => t.name == name,
        orElse: () => EnergyTxType.travelCost);

/// A single immutable entry in the energy ledger. [amount] is signed:
/// negative for costs, positive for rewards.
class EnergyTransaction {
  const EnergyTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.createdAt,
    this.relatedObjectId,
  });

  final String id;
  final EnergyTxType type;
  final int amount;
  final DateTime createdAt;
  final String? relatedObjectId;

  factory EnergyTransaction.fromJson(Map<String, dynamic> json) =>
      EnergyTransaction(
        id: json['id'] as String,
        type: energyTxTypeFromName(json['type'] as String),
        amount: json['amount'] as int,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        relatedObjectId: json['relatedObjectId'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.name,
        'amount': amount,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'relatedObjectId': relatedObjectId,
      };
}
