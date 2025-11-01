// lib/services/metrics/smart_index.dart

/// ตัวถ่วงน้ำหนักคะแนนรวมจาก Z-score ของแต่ละมิเตอร์
/// แนวคิด:
/// - H (Entropy) และ C (Complexity) เป็นสัญญาณทักษะเชิงบวก → น้ำหนักสูง
/// - Blank = พื้นที่ว่างในเส้น (มากไปไม่ดี) → น้ำหนักติดลบ
/// - COTL = ระบายออกนอกเส้น (มากไปไม่ดี) → น้ำหนักติดลบ
///
/// index = wH*zH + wC*zC - wBlank*zBlank - wCotl*zCotl
/// (สังเกตว่าเราลงลบให้กับตัวที่แย่โดยตรง เพื่อให้อ่านค่า index สูง=ดี)
class SmartIndex {
  double wH;
  double wC;
  double wBlank;
  double wCotl;

  /// ค่าน้ำหนักเริ่มต้นสมดุล (รวม ~1.0)
  /// - H/C เด่นกว่าหน่อย
  /// - Blank/COTL กดลงพอเหมาะ
  SmartIndex({
    this.wH = 0.32,
    this.wC = 0.28,
    this.wBlank = 0.22,
    this.wCotl = 0.18,
  });

  /// คำนวณคะแนนรวมจาก Z ของแต่ละตัวชี้วัด
  double indexFromZ({
    required double zH,
    required double zC,
    required double zBlank,
    required double zCotl,
  }) {
    // บาง baseline อาจมีค่า Z วิ่งแรงมาก → กัน overshoot เล็กน้อย
    final zzH = _clip(zH, -3.5, 3.5);
    final zzC = _clip(zC, -3.5, 3.5);
    final zzB = _clip(zBlank, -3.5, 3.5);
    final zzT = _clip(zCotl, -3.5, 3.5);

    // Blank/COTL เป็น “ยิ่งมากยิ่งแย่” → หักออก
    final idx = (wH * zzH) + (wC * zzC) - (wBlank * zzB) - (wCotl * zzT);
    return idx;
  }

  /// แปลง index เป็นระดับข้อความ (ไทย) เพื่อโชว์บน UI และใช้ทำ “ดาว”
  /// เกณฑ์:
  ///   <= -2       → ต่ำมากกว่ามาตรฐาน
  ///   (-2, -1]    → ต่ำกว่ามาตรฐาน
  ///   (-1, 1)     → อยู่ในเกณฑ์มาตรฐาน
  ///   [1, 2]      → สูงกว่ามาตรฐาน
  ///   > 2         → สูงมากกว่ามาตรฐาน
  String levelFromIndex(double index) {
    if (index <= -2.0) return 'ต่ำมากกว่ามาตรฐาน';
    if (index <= -1.0) return 'ต่ำกว่ามาตรฐาน';
    if (index < 1.0) return 'อยู่ในเกณฑ์มาตรฐาน';
    if (index <= 2.0) return 'สูงกว่ามาตรฐาน';
    return 'สูงมากกว่ามาตรฐาน';
  }

  static double _clip(double x, double lo, double hi) =>
      x < lo ? lo : (x > hi ? hi : x);
}
