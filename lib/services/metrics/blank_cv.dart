// lib/services/metrics/blank_cv.dart
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// ----------------- Tunable thresholds -----------------
const double _kWhiteThr = 245.0; // กันกระดาษขาวจัด
const int _kMinGray = 60; // ตัดพิกเซลมืด (เส้น/เงา)
const int _kSatThr = 40; // S > 40 ถือว่าเป็น “สีจริง”

cv.Mat _rectK(int k) => cv.getStructuringElement(0, (k, k)); // 0 = MORPH_RECT

/// คำนวณ “สัดส่วนพื้นที่ว่าง (ยังไม่ระบาย)” ภายในเส้น (0..1)
/// - gray: ช่องสีเทา (BGR2GRAY)
/// - sat: ช่อง Saturation (จาก HSV)
/// - inLineMask: mask บริเวณในเส้น (0/255)
Future<double> computeBlank(cv.Mat gray, cv.Mat sat, cv.Mat inLineMask) async {
  final int area = cv.countNonZero(inLineMask);
  if (area <= 0) return 1.0; // ถ้าไม่มีพื้นที่ในเส้นเลย → ถือว่าว่างเต็ม

  // 1) พื้นที่ที่มีสี (S > _kSatThr)
  final cv.Mat satMask = cv
      .threshold(sat, _kSatThr.toDouble(), 255.0, 0)
      .$2; // THRESH_BINARY

  // 2) ไม่ขาวจัด และไม่ดำ (ไม่ใช่เส้น)
  final cv.Mat notWhite = cv
      .threshold(gray, _kWhiteThr, 255.0, 1)
      .$2; // THRESH_BINARY_INV
  final cv.Mat notDark = cv
      .threshold(gray, _kMinGray.toDouble(), 255.0, 0)
      .$2; // THRESH_BINARY

  // 3) colored = satMask AND notWhite AND notDark
  final cv.Mat colored1 = cv.Mat.zeros(
    satMask.rows,
    satMask.cols,
    satMask.type,
  );
  satMask.copyTo(colored1, mask: notWhite);

  final cv.Mat colored = cv.Mat.zeros(
    colored1.rows,
    colored1.cols,
    colored1.type,
  );
  colored1.copyTo(colored, mask: notDark);

  // 4) จำกัดให้นับเฉพาะ “ในเส้น”
  final cv.Mat coloredIn = cv.Mat.zeros(
    colored.rows,
    colored.cols,
    colored.type,
  );
  colored.copyTo(coloredIn, mask: inLineMask);

  // 5) ล้าง noise จุดเล็ก ๆ (MORPH_OPEN)
  final cv.Mat cleaned = cv.morphologyEx(coloredIn, 1, _rectK(3));

  // 6) คำนวณสัดส่วนที่ระบายแล้ว
  final int coloredCount = cv.countNonZero(cleaned);
  final double paintedRatio = (coloredCount / area).clamp(0.0, 1.0);

  // ✅ 7) กลับค่าเป็น “blank” (ว่าง) แทน “painted”
  final double blankRatio = (1.0 - paintedRatio).clamp(0.0, 1.0);

  return blankRatio;
}
