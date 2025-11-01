// lib/services/metrics/cotl_cv.dart
//
// วัด “การระบายออกนอกเส้น (COTL)” ด้วยวงแหวนด้านนอกชิดเส้น ~3 มม.
// - ต้องส่ง **mask_out** (ขาว=นอก, ดำ=ใน) เข้ามา
// - คัด “สีจริง” ด้วย S สูง / V มืด / เอาพาสเทล และตัดกระดาษ + เส้นเทมเพลตออก
// - ปรับ guard ให้รูปขาวล้วน/ดำล้วนได้ 0 หรือ 1 ที่เหมาะสม

import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:math' as math;

/// ---------- พารามิเตอร์ ----------
const int _S_COLORED_MIN = 26; // สีสด
const int _V_BRIGHT_MIN = 80; // สว่าง (ช่วยแบ่งพื้นหลัง)
const int _V_DARK_MAX = 172; // มืดมาก (ดินสอ/หมึก)
const int _S_NEARWHITE = 15; // ใกล้กระดาษ
const int _V_NEARWHITE = 242;

const double _INNER_PORTION = 0.75; // ส่วนวงแหวนด้านใน (เอียงน้ำหนัก)
const double _INNER_WEIGHT = 0.90; // น้ำหนักความผิดชิดเส้น

// snap guards
const double _SNAP_RALL = 0.94;
const double _SNAP_RINNER = 0.96;
const double _SNAP_POST = 0.965;

cv.Mat _rectK(int k) => cv.getStructuringElement(0, (k, k));
cv.Mat _ellipK(int k) => cv.getStructuringElement(2, (k, k));

cv.Mat _bin(cv.Mat m) {
  if (m.channels > 1) m = cv.cvtColor(m, cv.COLOR_BGR2GRAY);
  return cv.threshold(m, 127.0, 255.0, cv.THRESH_BINARY).$2;
}

/// ตรวจให้แน่ใจว่าเป็น mask_out (ขาว=นอก)
cv.Mat _ensureMaskOut(cv.Mat maskOutMaybe) {
  cv.Mat m = _bin(maskOutMaybe);
  final int h = m.rows, w = m.cols;
  final int s = (math.min(h, w) * 0.1).round().clamp(8, 64);
  final rois = <cv.Mat>[
    m.rowRange(0, s).colRange(0, s),
    m.rowRange(0, s).colRange(w - s, w),
    m.rowRange(h - s, h).colRange(0, s),
    m.rowRange(h - s, h).colRange(w - s, w),
  ];
  int white = 0, total = 0;
  for (final r in rois) {
    white += cv.countNonZero(r);
    total += r.rows * r.cols;
  }
  final double ratio = white / total;
  if (ratio < 0.5) m = cv.bitwiseNOT(m); // กลับขั้วให้เป็น mask_out
  return m;
}

/// บีบ mask_out ให้ “ชิดเส้นใน” ขึ้นเล็กน้อย
cv.Mat _tightenMaskOut(cv.Mat maskOut) {
  final cv.Mat inside = cv.bitwiseNOT(maskOut);
  final cv.Mat expandedInside = cv.dilate(inside, _ellipK(2));
  return cv.bitwiseNOT(expandedInside);
}

class _RingBands {
  final cv.Mat all, inner;
  _RingBands(this.all, this.inner);
}

/// วงแหวน ~ 3mm: ประมาณเป็นสัดส่วนของด้านสั้น (เทียบ ~300dpi → 3mm ≅ 35px @900px)
_RingBands _outerRings(cv.Mat maskOut) {
  final int minSide = math.min(maskOut.rows, maskOut.cols);
  final int off = (minSide * 0.033).round().clamp(1, 40); // ~3mm
  final int thk = (minSide * 0.016).round().clamp(1, 20); // วงแหวนบาง
  final int thkInner = math.max(1, (thk * _INNER_PORTION).round());

  // erode mask_out = ยุบจากขอบนอกเข้ามา
  final cv.Mat erOff = cv.erode(maskOut, _ellipK(off));
  final cv.Mat erOffThk = cv.erode(maskOut, _ellipK(off + thk));
  final cv.Mat erOffThin = cv.erode(maskOut, _ellipK(off + thkInner));

  // ringAll = erOff AND NOT(erOffThk)
  final cv.Mat ringAll = cv.Mat.zeros(maskOut.rows, maskOut.cols, maskOut.type);
  erOff.copyTo(ringAll, mask: cv.bitwiseNOT(erOffThk));

  // ringInner = erOff AND NOT(erOffThin)
  final cv.Mat ringInner = cv.Mat.zeros(
    maskOut.rows,
    maskOut.cols,
    maskOut.type,
  );
  erOff.copyTo(ringInner, mask: cv.bitwiseNOT(erOffThin));

  // ตัดเส้นหนา/เอียง
  final cv.Mat outline = cv.morphologyEx(
    cv.bitwiseNOT(maskOut),
    cv.MORPH_GRADIENT,
    _ellipK(2),
  );
  final cv.Mat outlineFat = cv.dilate(outline, _rectK(1));

  final cv.Mat safeAll = cv.Mat.zeros(ringAll.rows, ringAll.cols, ringAll.type);
  final cv.Mat safeInner = cv.Mat.zeros(
    ringInner.rows,
    ringInner.cols,
    ringInner.type,
  );
  ringAll.copyTo(safeAll, mask: cv.bitwiseNOT(outlineFat));
  ringInner.copyTo(safeInner, mask: cv.bitwiseNOT(outlineFat));

  return _RingBands(
    cv.morphologyEx(safeAll, cv.MORPH_OPEN, _rectK(3)),
    cv.morphologyEx(safeInner, cv.MORPH_OPEN, _rectK(3)),
  );
}

/// คัด “สีที่นับเป็นการระบาย”
cv.Mat _coloredMask(cv.Mat gray, cv.Mat sat, cv.Mat maskOut) {
  final cv.Mat sGt = cv
      .threshold(sat, _S_COLORED_MIN.toDouble(), 255.0, cv.THRESH_BINARY)
      .$2;
  final cv.Mat vBright = cv
      .threshold(gray, _V_BRIGHT_MIN.toDouble(), 255.0, cv.THRESH_BINARY)
      .$2;
  final cv.Mat bySat = cv
      .threshold(cv.add(sGt, vBright), 1.0, 255.0, cv.THRESH_BINARY)
      .$2;

  final cv.Mat vDark = cv
      .threshold(gray, _V_DARK_MAX.toDouble(), 255.0, cv.THRESH_BINARY_INV)
      .$2;
  final cv.Mat colored0 = cv
      .threshold(cv.add(bySat, vDark), 1.0, 255.0, cv.THRESH_BINARY)
      .$2;

  // ตัดกระดาษ (ใกล้ขาว)
  final cv.Mat sNearW = cv
      .threshold(sat, _S_NEARWHITE.toDouble(), 255.0, cv.THRESH_BINARY_INV)
      .$2;
  final cv.Mat vNearW = cv
      .threshold(gray, _V_NEARWHITE.toDouble(), 255.0, cv.THRESH_BINARY)
      .$2;
  final cv.Mat nearW = cv
      .threshold(cv.add(sNearW, vNearW), 1.0, 255.0, cv.THRESH_BINARY)
      .$2;

  // ตัดเส้นเทมเพลต
  final cv.Mat inside = cv.bitwiseNOT(maskOut);
  final cv.Mat outline = cv.morphologyEx(inside, cv.MORPH_GRADIENT, _ellipK(2));
  final cv.Mat outlineFat = cv.dilate(outline, _rectK(1));
  final cv.Mat noOutline = cv
      .threshold(outlineFat, 0.0, 255.0, cv.THRESH_BINARY_INV)
      .$2;

  final cv.Mat tmp = cv.Mat.zeros(gray.rows, gray.cols, gray.type);
  colored0.copyTo(tmp, mask: noOutline);
  final cv.Mat colored = cv.Mat.zeros(gray.rows, gray.cols, gray.type);
  tmp.copyTo(colored, mask: cv.bitwiseNOT(nearW));

  // smooth
  final cv.Mat opened = cv.morphologyEx(colored, cv.MORPH_OPEN, _rectK(3));
  final cv.Mat closed = cv.morphologyEx(opened, cv.MORPH_CLOSE, _rectK(3));
  return closed;
}

/// ========== PUBLIC API ==========
Future<double> computeCotl(cv.Mat gray, cv.Mat sat, cv.Mat maskOutMaybe) async {
  // เตรียมสัญญาณ
  final cv.Mat mOut = _tightenMaskOut(_ensureMaskOut(maskOutMaybe));
  final cv.Mat grayMd = cv.medianBlur(gray, 3);

  // วงแหวน
  final rings = _outerRings(mOut);
  final int areaAll = cv.countNonZero(rings.all);
  final int areaInner = cv.countNonZero(rings.inner);
  if (areaAll <= 0) {
    print('⚠️ COTL: ringArea=0');
    return 0.0;
  }

  // สีที่นับเป็นการระบาย
  final cv.Mat colored = _coloredMask(grayMd, sat, mOut);

  // นับบนวงแหวน
  cv.Mat colAll = cv.Mat.zeros(colored.rows, colored.cols, colored.type);
  cv.Mat colInner = cv.Mat.zeros(colored.rows, colored.cols, colored.type);
  colored.copyTo(colAll, mask: rings.all);
  colored.copyTo(colInner, mask: rings.inner);

  colAll = cv.morphologyEx(colAll, cv.MORPH_OPEN, _rectK(3));
  colInner = cv.morphologyEx(colInner, cv.MORPH_OPEN, _rectK(3));

  final int hitAll = cv.countNonZero(colAll);
  final int hitInner = cv.countNonZero(colInner);

  double rAll = (hitAll / areaAll).clamp(0.0, 1.0);
  double rInner = (hitInner / math.max(1, areaInner)).clamp(0.0, 1.0);

  // snap ก่อน blend
  if (rAll >= _SNAP_RALL || rInner >= _SNAP_RINNER) {
    print(
      '[COTL] snap→1.0 pre-blend rAll=${rAll.toStringAsFixed(3)} rInner=${rInner.toStringAsFixed(3)}',
    );
    return 1.0;
  }

  // ผสมแบบชิดเส้นมีน้ำหนักมาก
  double ratio = (_INNER_WEIGHT * rInner) + ((1.0 - _INNER_WEIGHT) * rAll);

  // Guard: รูปมืดเกือบทั้งแผ่น → 1.0
  final int totalPix = grayMd.rows * grayMd.cols;
  final int veryDark = cv.countNonZero(
    cv.threshold(grayMd, 20.0, 255.0, cv.THRESH_BINARY_INV).$2,
  );
  if (veryDark >= (totalPix * 0.95).round()) {
    print('[COTL] snap→1.0 (whole-image very dark)');
    return 1.0;
  }

  // Guard: วงแหวนถูกเติมเกือบเต็มจริงๆ
  if (hitAll >= areaAll - 1 ||
      (areaInner > 0 && hitInner >= areaInner - 1) ||
      rAll >= 0.985 ||
      rInner >= 0.985) {
    print('[COTL] snap→1.0 (hard-guard)');
    return 1.0;
  }

  // รวมแล้วสูงมาก
  if (ratio >= _SNAP_POST) {
    print('[COTL] snap→1.0 post-blend ratio=${ratio.toStringAsFixed(3)}');
    return 1.0;
  }

  // Debug
  print(
    '[COTL] areaAll=$areaAll areaInner=$areaInner rAll=${rAll.toStringAsFixed(3)} rInner=${rInner.toStringAsFixed(3)} ratio=${ratio.toStringAsFixed(3)}',
  );
  return ratio.clamp(0.0, 1.0);
}
