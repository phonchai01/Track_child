class Session {
  final int? id;
  final DateTime createdAt;
  final String templateKey;
  final double h;
  final double dstar;
  final double cotl;
  final double blank;

  Session({
    this.id,
    required this.createdAt,
    required this.templateKey,
    required this.h,
    required this.dstar,
    required this.cotl,
    required this.blank,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'created_at': createdAt.toIso8601String(),
        'template_key': templateKey,
        'h': h,
        'dstar': dstar,
        'cotl': cotl,
        'blank': blank,
      };

  factory Session.fromMap(Map<String, dynamic> m) => Session(
        id: m['id'] as int?,
        createdAt: DateTime.parse(m['created_at'] as String),
        templateKey: m['template_key'] as String,
        h: (m['h'] as num).toDouble(),
        dstar: (m['dstar'] as num).toDouble(),
        cotl: (m['cotl'] as num).toDouble(),
        blank: (m['blank'] as num).toDouble(),
      );
}
