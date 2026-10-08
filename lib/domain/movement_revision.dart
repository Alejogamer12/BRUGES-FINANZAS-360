class MovementRevision {
  const MovementRevision({
    required this.movementId,
    required this.changedAt,
    required this.before,
    required this.after,
  });

  final String movementId;
  final DateTime changedAt;
  final Map<String, Object?> before;
  final Map<String, Object?> after;

  Map<String, Object?> toJson() => {
    'movementId': movementId,
    'changedAt': changedAt.toUtc().toIso8601String(),
    'before': before,
    'after': after,
  };

  factory MovementRevision.fromJson(Map<String, Object?> json) {
    return MovementRevision(
      movementId: json['movementId']! as String,
      changedAt: DateTime.parse(json['changedAt']! as String),
      before: Map<String, Object?>.from(json['before']! as Map),
      after: Map<String, Object?>.from(json['after']! as Map),
    );
  }
}
