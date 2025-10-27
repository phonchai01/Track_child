import 'dart:convert';

class HistoryRecord {
  final String id; // timestamp หรือ uuid
  final DateTime createdAt;
  final String templateKey; // fish / pencil / icecream
  final int age; // อายุ (ปี) ถ้ามี
  final double h; // Entropy
  final double c; // Complexity
  final double blank; // ในเส้น
  final double cotl; // นอกเส้น
  final double zH, zC, zBlank, zCotl; // Z-scores
  final String imagePath; // path รูปที่บันทึก (สำหรับแสดงภายหลัง)

  HistoryRecord({
    required this.id,
    required this.createdAt,
    required this.templateKey,
    required this.age,
    required this.h,
    required this.c,
    required this.blank,
    required this.cotl,
    required this.zH,
    required this.zC,
    required this.zBlank,
    required this.zCotl,
    required this.imagePath,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'templateKey': templateKey,
    'age': age,
    'h': h,
    'c': c,
    'blank': blank,
    'cotl': cotl,
    'zH': zH,
    'zC': zC,
    'zBlank': zBlank,
    'zCotl': zCotl,
    'imagePath': imagePath,
  };

  factory HistoryRecord.fromMap(Map<String, dynamic> m) => HistoryRecord(
    id: m['id'],
    createdAt: DateTime.parse(m['createdAt']),
    templateKey: m['templateKey'],
    age: (m['age'] ?? 0) as int,
    h: (m['h'] as num).toDouble(),
    c: (m['c'] as num).toDouble(),
    blank: (m['blank'] as num).toDouble(),
    cotl: (m['cotl'] as num).toDouble(),
    zH: (m['zH'] as num).toDouble(),
    zC: (m['zC'] as num).toDouble(),
    zBlank: (m['zBlank'] as num).toDouble(),
    zCotl: (m['zCotl'] as num).toDouble(),
    imagePath: m['imagePath'] ?? '',
  );

  String toJson() => jsonEncode(toMap());
  factory HistoryRecord.fromJson(String s) =>
      HistoryRecord.fromMap(jsonDecode(s));
}
