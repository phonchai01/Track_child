// lib/services/metrics/cotl_cv.dart
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// ---------- Tunables (ค่านี้พอเหมาะกับสแกนกระดาษทั่วไป) ----------
const int _S_COLORED_MIN = 35; // S >= 25 ถือว่ามีสี
const int _V_BRIGHT_MIN = 80; // Gray >= 70 ถือว่าสว่าง
const int _V_DARK_MAX = 80; // Gray <= 95 ถือว่ามืด (ดินสอ/ปากกา)
const int _S_NEARWHITE = 15; // S ใกล้ขาว
const int _V_NEARWHITE = 240; // Gray ใกล้ขาว

cv.Mat _rectK(int k) => cv.getStructuringElement(0 /*RECT*/, (k, k));
cv.Mat _ellipK(int k) => cv.getStructuringElement(2 /*ELLIPSE*/, (k, k));

/// ทำให้แน่ใจว่า 255 = "ภายในเส้น"
cv.Mat _ensureInsideIsWhite(cv.Mat inLineMask) {
  cv.Mat m = inLineMask;
  if (m.channels > 1) m = cv.cvtColor(m, cv.COLOR_BGR2GRAY);
  m = cv.threshold(m, 127.0, 255.0, 0 /*BINARY*/).$2;

  final total = (m.rows * m.cols).toDouble();
  final ratioWhite = cv.countNonZero(m) / total;
  // ถ้าดูเหมือนกลับขั้ว ให้กลับ
  if (ratioWhite < 0.35 || ratioWhite > 0.90) {
    m = cv.bitwiseNOT(m);
    print('🔄 flip inside-mask: insideWhiteRatio(before)=$ratioWhite');
  }
  return m;
}

/// สร้าง "แหวนรอบนอก" แบบบาง ด้วย morphological gradient + clamp ความหนา
cv.Mat _buildOuterBand(cv.Mat inside) {
  final int minSide = inside.rows < inside.cols ? inside.rows : inside.cols;

  // กำหนดความหนาเป้าหมาย ~ 0.6% ของด้านสั้น (กันบาง/หนาเกิน)
  final int target = (minSide * 0.004).round().clamp(2, 8);
  // gradient = dilate - erode → แหวนบางที่ขอบนอก-ใน
  final cv.Mat grad = cv.morphologyEx(inside, 3 /*MORPH_GRADIENT*/, _ellipK(3));
  // ขยาย/หดเพื่อให้ได้ความหนาใกล้ target
  cv.Mat band = grad;
  if (target > 3) {
    band = cv.dilate(band, _ellipK(target - 1));
  }

  // ไม่ให้อยู่ทับในเส้น: band = band & !inside
  final cv.Mat notInside = cv.bitwiseNOT(inside);
  final cv.Mat out = cv.Mat.zeros(band.rows, band.cols, band.type);
  band.copyTo(out, mask: notInside);

  // ทำความสะอาดนิดหน่อย
  return cv.morphologyEx(out, 1 /*OPEN*/, _rectK(3));
}

/// รวมด้วย mask (and)
cv.Mat _maskAnd(cv.Mat a, cv.Mat b) {
  final out = cv.Mat.zeros(a.rows, a.cols, a.type);
  a.copyTo(out, mask: b);
  return out;
}

/// รวมแบบ binary OR
cv.Mat _maskOr(cv.Mat a, cv.Mat b) {
  final add = cv.add(a, b);
  return cv.threshold(add, 1.0, 255.0, 0 /*BINARY*/).$2;
}

/// นิยาม "พิกเซลมีสี" (ผสม S สูง + สว่าง) OR (มืดมาก) แล้วตัดกระดาษขาว
cv.Mat _coloredMask(cv.Mat grayMed, cv.Mat sat) {
  final cv.Mat sGt = cv.threshold(sat, _S_COLORED_MIN.toDouble(), 255.0, 0).$2;
  final cv.Mat vBright = cv
      .threshold(grayMed, _V_BRIGHT_MIN.toDouble(), 255.0, 0)
      .$2;
  final cv.Mat bySat = _maskAnd(sGt, vBright);

  final cv.Mat vDark = cv
      .threshold(grayMed, _V_DARK_MAX.toDouble(), 255.0, 1 /*INV*/)
      .$2;
  final cv.Mat coloredPre = _maskOr(bySat, vDark);

  final cv.Mat sNearW = cv
      .threshold(sat, _S_NEARWHITE.toDouble(), 255.0, 1 /*INV*/)
      .$2;
  final cv.Mat vNearW = cv
      .threshold(grayMed, _V_NEARWHITE.toDouble(), 255.0, 0 /*BIN*/)
      .$2;
  final cv.Mat nearWhite = _maskAnd(sNearW, vNearW);
  return _maskAnd(coloredPre, cv.bitwiseNOT(nearWhite));
}

/// COTL = สัดส่วนพิกเซล "มีสี" ในแหวน *นอกเส้น* (0..1)
Future<double> computeCotl(cv.Mat gray, cv.Mat sat, cv.Mat inLineMask) async {
  // 0) เตรียมพื้นฐาน
  final cv.Mat grayMed = cv.medianBlur(gray, 3);
  final cv.Mat inside = _ensureInsideIsWhite(inLineMask);

  // 1) แหวนรอบนอกแบบบาง
  cv.Mat band = _buildOuterBand(inside);
  int bandArea = cv.countNonZero(band);
  final int total = band.rows * band.cols;

  // ถ้าแหวนใหญ่เกิน (>= 30% ของภาพ) หรือเล็กไป (< 300 px) → ปรับ
  final double bandRatio = bandArea / total;
  if (bandArea < 300 || bandRatio > 0.30) {
    final cv.Mat er = cv.erode(inside, _ellipK(5));
    final cv.Mat grad = cv.morphologyEx(er, 3 /*GRADIENT*/, _ellipK(3));
    band = _maskAnd(grad, cv.bitwiseNOT(inside));
    band = cv.morphologyEx(band, 1 /*OPEN*/, _rectK(3));
    bandArea = cv.countNonZero(band);
  }
  if (bandArea <= 0) {
    print('⚠️ COTL: bandArea=0');
    return 0.0;
  }

  // 2) พิกเซลมีสี และลบ “เส้นขอบ”
  final cv.Mat colored = _coloredMask(grayMed, sat);
  final cv.Mat edges = cv.canny(grayMed, 60, 120);
  final cv.Mat edgesDil = cv.dilate(edges, _rectK(5));
  final cv.Mat edgesInv = cv.threshold(edgesDil, 0.0, 255.0, 1 /*INV*/).$2;

  cv.Mat coloredNoEdge = _maskAnd(colored, edgesInv);
  cv.Mat coloredNear = _maskAnd(coloredNoEdge, band);
  coloredNear = cv.morphologyEx(coloredNear, 1 /*OPEN*/, _rectK(3));

  int coloredNearCount = cv.countNonZero(coloredNear);
  double ratio = coloredNearCount / bandArea;

  // 🔧 Fallback อัตโนมัติ: ถ้าได้ 1.0 ให้ "หดแหวน" + "เข้มเกณฑ์"
  if (ratio >= 0.999) {
    final cv.Mat erInside = cv.erode(inside, _ellipK(7));
    final cv.Mat grad2 = cv.morphologyEx(erInside, 3 /*GRADIENT*/, _ellipK(3));
    band = _maskAnd(grad2, cv.bitwiseNOT(erInside));
    band = cv.morphologyEx(band, 1 /*OPEN*/, _rectK(3));
    bandArea = cv.countNonZero(band);

    // เข้มเกณฑ์สีขึ้นเล็กน้อย: ใช้ vDark อย่างเดียวเป็นหลัก
    final cv.Mat vDark = cv
        .threshold(grayMed, (_V_DARK_MAX - 10).toDouble(), 255.0, 1)
        .$2;
    coloredNear = _maskAnd(vDark, band);
    coloredNear = cv.morphologyEx(coloredNear, 1, _rectK(3));

    coloredNearCount = cv.countNonZero(coloredNear);
    ratio = (bandArea <= 0) ? 0.0 : (coloredNearCount / bandArea);
  }

  // debug log
  final insideRatio = cv.countNonZero(inside) / total;
  print(
    '[COTL] insideRatio=$insideRatio bandArea=$bandArea bandRatio=$bandRatio '
    'colored=$coloredNearCount ratio=$ratio',
  );

  return ratio.clamp(0.0, 1.0);
}
