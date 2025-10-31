import 'dart:convert';

class HistoryRecord {
  final String id; // timestamp หรือ uuid
  final DateTime createdAt;
  final String templateKey; // fish / pencil / icecream
  final int age; // อายุ (ปี) ถ้ามี

  // raw metrics
  final double h; // Entropy
  final double c; // Complexity
  final double blank; // ในเส้น
  final double cotl; // นอกเส้น

  // Z-scores
  final double zH;
  final double zC;
  final double zBlank;
  final double zCotl;

  // ✅ ฟิลด์ใหม่
  final double zSum; // ดัชนีรวม
  final String level; // การแปลผล เช่น "ปกติ" / "ต่ำ" / "สูง"

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
    required this.zSum,
    required this.level,
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
        'zSum': zSum, // ✅
        'level': level, // ✅
        'imagePath': imagePath,
      };

  factory HistoryRecord.fromMap(Map<String, dynamic> m) => HistoryRecord(
        id: m['id'] ?? '',
        createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
        templateKey: m['templateKey'] ?? '',
        age: (m['age'] ?? 0) is int
            ? m['age']
            : int.tryParse(m['age'].toString()) ?? 0,
        h: (m['h'] ?? 0).toDouble(),
        c: (m['c'] ?? 0).toDouble(),
        blank: (m['blank'] ?? 0).toDouble(),
        cotl: (m['cotl'] ?? 0).toDouble(),
        zH: (m['zH'] ?? 0).toDouble(),
        zC: (m['zC'] ?? 0).toDouble(),
        zBlank: (m['zBlank'] ?? 0).toDouble(),
        zCotl: (m['zCotl'] ?? 0).toDouble(),
        zSum: (m['zSum'] ?? 0).toDouble(), // ✅
        level: m['level'] ?? '-', // ✅
        imagePath: m['imagePath'] ?? '',
      );

  String toJson() => jsonEncode(toMap());
  factory HistoryRecord.fromJson(String s) =>
      HistoryRecord.fromMap(jsonDecode(s));
}
