// lib/services/metrics/zscore_service.dart
//
// ✅ เวอร์ชันใหม่: ไม่ใช้ CSV / ไม่แบ่งอายุ / ไม่ใช้ Z-score / ไม่ใช้ช่วงอ้างอิง
// - คำนวณเฉพาะ RAW Index: index = (-H) + C + (-Blank) + (-COTL)
// - ไม่จัดระดับ (level) อีกต่อไป และไม่แสดงช่วง μ±σ (ทั้งหมดเป็น NaN)
// - คงเมธอด/คลาสที่ไฟล์อื่นเรียกใช้อยู่ (ensureLoaded, computeRaw, compute)
//   โดย compute() จะ proxy ไปใช้ raw index เพื่อให้โค้ดเดิมยังคอมไพล์ได้

/// -----------------------------
/// ผลสำหรับ RAW INDEX (ไม่เทียบเกณฑ์)
/// -----------------------------
class RawIndexResult {
  /// index(raw) = -H + C - Blank - COTL
  final double index;

  /// ช่อง z* ถูกยกเลิกแล้ว → ตั้งเป็น NaN เพื่อให้โค้ดเดิมไม่พัง
  final double zH;
  final double zC;
  final double zBlank;
  final double zCotl;

  /// ไม่จัดระดับ (ไม่มี baseline)
  final String level;

  /// ค่าอ้างอิง (ยกเลิก) → NaN ทั้งหมด
  final double mu;     // μ
  final double sigma;  // σ
  final double lowCut; // μ−σ (เดิม) → NaN
  final double highCut; // μ+σ (เดิม) → NaN

  const RawIndexResult({
    required this.index,
    required this.zH,
    required this.zC,
    required this.zBlank,
    required this.zCotl,
    required this.level,
    required this.mu,
    required this.sigma,
    required this.lowCut,
    required this.highCut,
  });
}

/// -----------------------------
/// (คงไว้ให้คอมไพล์ผ่าน) — ในเวอร์ชันนี้ zSum = raw index
/// -----------------------------
class ZScoreResult {
  final double zH;     // NaN
  final double zC;     // NaN
  final double zBlank; // NaN
  final double zCotl;  // NaN
  final double zSum;   // ใช้ raw index แทน
  final String level;  // 'ไม่จัดระดับ (ไม่มี baseline)'

  // ค่าช่วงอ้างอิง (ยกเลิก) → NaN
  final double? zsumMean;
  final double? zsumSd;
  final double? lowCut;
  final double? highCut;

  const ZScoreResult({
    required this.zH,
    required this.zC,
    required this.zBlank,
    required this.zCotl,
    required this.zSum,
    required this.level,
    this.zsumMean,
    this.zsumSd,
    this.lowCut,
    this.highCut,
  });
}

/// ==============================================
/// ZScoreService (singleton) — ตอนนี้เหลือบทบาท “RawIndexService”
/// ==============================================
class ZScoreService {
  static final ZScoreService instance = ZScoreService._();
  ZScoreService._();

  /// compatibility: บางจอเรียก ensureLoaded(); ให้เป็น no-op
  Future<void> ensureLoaded() async {
    // ไม่มีอะไรต้องโหลดแล้ว
    return;
  }

  /// ============== RAW ==============
  /// Index(raw) = -H + C - Blank - COTL
  /// ไม่จัดระดับ และไม่ใช้ช่วงอ้างอิง
  Future<RawIndexResult> computeRaw({
    required String templateKey, // คงไว้ตาม signature เดิม
    required int age,            // ไม่ใช้แล้ว
    required double h,
    required double c,
    required double blank,
    required double cotl,
  }) async {
    final idx = (-h) + c + (-blank) + (-cotl);

    return const RawIndexResult(
      index: 0, // placeholder, จะถูกแทนด้านล่าง
      zH: double.nan,
      zC: double.nan,
      zBlank: double.nan,
      zCotl: double.nan,
      level: 'ไม่จัดระดับ (ไม่มี baseline)',
      mu: double.nan,
      sigma: double.nan,
      lowCut: double.nan,
      highCut: double.nan,
    )._withIndex(idx);
  }

  /// ============== (เดิม) Z-sum ==============
  /// proxy ไปที่ RAW:
  /// - zSum = raw index
  /// - z* = NaN
  /// - level = 'ไม่จัดระดับ (ไม่มี baseline)'
  Future<ZScoreResult> compute({
    required String templateKey,
    required int age,
    required double h,
    required double c,
    required double blank,
    required double cotl,
    double bandK = 1.0, // ไม่ใช้แล้ว
  }) async {
    final raw = await computeRaw(
      templateKey: templateKey,
      age: age,
      h: h,
      c: c,
      blank: blank,
      cotl: cotl,
    );

    return ZScoreResult(
      zH: double.nan,
      zC: double.nan,
      zBlank: double.nan,
      zCotl: double.nan,
      zSum: raw.index,
      level: raw.level,
      zsumMean: raw.mu,     // NaN
      zsumSd: raw.sigma,    // NaN
      lowCut: raw.lowCut,   // NaN
      highCut: raw.highCut, // NaN
    );
  }
}

/// --------- private ext: helper ใส่ค่า index ย้อนหลังแบบ immutability ---------
extension on RawIndexResult {
  RawIndexResult _withIndex(double idx) => RawIndexResult(
        index: idx,
        zH: zH,
        zC: zC,
        zBlank: zBlank,
        zCotl: zCotl,
        level: level,
        mu: mu,
        sigma: sigma,
        lowCut: lowCut,
        highCut: highCut,
      );
}
