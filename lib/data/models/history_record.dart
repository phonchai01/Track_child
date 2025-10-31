// lib/data/models/history_record.dart
class HistoryRecord {
  final String id; // ใช้ now.millisecondsSinceEpoch.toString()
  final DateTime createdAt; // เวลาบันทึก
  final String profileKey; // ✅ เพิ่มสำหรับแยกโปรไฟล์
  final String templateKey; // 'Fish' | 'Pencil' | 'IceCream' (หรือไทย)
  final int age;
  final double h;
  final double c;
  final double blank;
  final double cotl;

  // Z ระบุไว้เพื่อแสดง/วิเคราะห์เพิ่มเติม
  final double zH;
  final double zC;
  final double zBlank;
  final double zCotl;
  final double zSum;

  final String level; // 'ต่ำกว่ามาตรฐาน' | ...
  final String? imagePath; // path รูป preview (optional)

  HistoryRecord({
    required this.id,
    required this.createdAt,
    required this.profileKey,
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
    this.imagePath,
  });

  /// ✅ แปลงเป็น Map สำหรับบันทึก JSON/SQLite
  Map<String, dynamic> toMap() => {
    'id': id,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'profileKey': profileKey, // ✅ เพิ่ม
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
    'zSum': zSum,
    'level': level,
    'imagePath': imagePath,
  };

  /// ✅ โหลดจาก Map (ไฟล์/DB)
  factory HistoryRecord.fromMap(Map<String, dynamic> m) => HistoryRecord(
    id: m['id']?.toString() ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['createdAt'] as num?)?.toInt() ?? 0,
    ),
    profileKey: m['profileKey']?.toString() ?? '', // ✅ ดึงกลับ
    templateKey: m['templateKey']?.toString() ?? '',
    age: (m['age'] as num?)?.toInt() ?? 0,
    h: (m['h'] as num?)?.toDouble() ?? 0,
    c: (m['c'] as num?)?.toDouble() ?? 0,
    blank: (m['blank'] as num?)?.toDouble() ?? 0,
    cotl: (m['cotl'] as num?)?.toDouble() ?? 0,
    zH: (m['zH'] as num?)?.toDouble() ?? 0,
    zC: (m['zC'] as num?)?.toDouble() ?? 0,
    zBlank: (m['zBlank'] as num?)?.toDouble() ?? 0,
    zCotl: (m['zCotl'] as num?)?.toDouble() ?? 0,
    zSum: (m['zSum'] as num?)?.toDouble() ?? 0,
    level: m['level']?.toString() ?? '-',
    imagePath: m['imagePath']?.toString(),
  );
}
