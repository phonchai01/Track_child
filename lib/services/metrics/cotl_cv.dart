// lib/services/metrics/cotl_cv.dart
//
// COTL (Color Outside The Line) : ค่าการระบาย “นอกเส้น”
// แนวคิด:
// 1) รับ mask_out (ขาว=นอก, ดำ=ใน) แล้วทำให้ชิดเส้นเล็กน้อย (tighten)
// 2) สร้าง “วงแหวนตรวจ” รอบเส้นด้านนอก 2 ชั้น: ringAll และ ringInnerBias
// 3) หา pixel ที่เป็น “สี/ลายเส้น” โดยมองทุกเฉดสี + กราไฟท์/ดำ
//    และอิงกระดาษจริง (paper-aware) เพื่อตัดกระดาษออกให้เกลี้ยง
// 4) นับสัดส่วนสีที่ตกในวงแหวน แล้ว bias น้ำหนักชั้นในมากกว่าชั้นนอก
//
// หมายเหตุ: โค้ดนี้ไม่พึ่งสีเฉพาะ—ครอบคลุมทุกเฉด (อิ่ม/ซีด/กราไฟท์)
// และกันเส้นเทมเพลต (outline) ออกให้

import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// ================= Tunables (ปรับเบา ๆ ได้) =================

/// สี/ความสว่างพื้นฐาน
const int _S_COLORED_MIN = 26; // S >= 26 ≈ มีสีจริง
const int _V_BRIGHT_MIN = 80; // V >= 80  ≈ สว่างพอ (พาสเทล/สีซีด)

/// ใกล้ขาว (ไว้ตัดกระดาษ): เราจะคำนวณแบบ dynamic จากกระดาษจริง แต่ตั้ง min/max ไว้
const int _NEARWHITE_MIN = 235;
const int _NEARWHITE_MAX = 252;

/// แหวนด้านนอก (อิงสัดส่วนจากด้านสั้นของภาพ)
const double _RING_OFFSET_FRAC = 0.0025; // ระยะถอยจากเส้น
const double _RING_THICK_FRAC = 0.0075; // ความหนาวงแหวน
const int _RING_OFFSET_MIN = 1, _RING_OFFSET_MAX = 8;
const int _RING_THICK_MIN = 1, _RING_THICK_MAX = 12;

/// ให้ความสำคัญกับชั้นในของแหวนมากกว่า (บริเวณที่ “หลุดเส้น” จริง)
const double _INNER_PORTION = 0.75; // สัดส่วนความหนาที่เป็น inner band
const double _INNER_WEIGHT = 0.90; // น้ำหนักตอนผสม rInner vs rAll

/// เกณฑ์ snap เป็น 1.0 (กันกรณีวงแหวนถูกทาท่วม)
const double _SNAP_RALL = 0.94;
const double _SNAP_RINNER = 0.96;
const double _SNAP_POST_BLEND = 0.965;

/// ===================== Helpers =====================

cv.Mat _rectK(int k) => cv.getStructuringElement(cv.MORPH_RECT, (k, k));
cv.Mat _ellipK(int k) => cv.getStructuringElement(cv.MORPH_ELLIPSE, (k, k));

cv.Mat _bin(cv.Mat m) {
  if (m.channels > 1) m = cv.cvtColor(m, cv.COLOR_BGR2GRAY);
  return cv.threshold(m, 127.0, 255.0, cv.THRESH_BINARY).$2;
}

/// รับ **mask_out** (ขาว=นอก, ดำ=ใน) — เช็ค 4 มุมแล้วกลับขั้วถ้าจำเป็น
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
  if ((white / total) < 0.5) m = cv.bitwiseNOT(m); // คว่ำให้เป็น mask_out
  return m;
}

/// ดันขอบ mask_out ให้ชิดเส้นในเล็กน้อย (ลดการไปทับเส้น)
cv.Mat _tightenMaskOut(cv.Mat maskOut) {
  final cv.Mat inside = cv.bitwiseNOT(maskOut); // ขาว=ใน
  final cv.Mat expandedInside = cv.dilate(inside, _ellipK(2));
  return cv.bitwiseNOT(expandedInside); // กลับเป็น mask_out
}

/// ---------- สร้างวงแหวนรอบเส้นด้านนอก ----------
class _RingBands {
  final cv.Mat ringAll; // วงแหวนเต็มความหนา
  final cv.Mat ringInnerBias; // เฉพาะชั้นใน (ชิดเส้น)
  _RingBands(this.ringAll, this.ringInnerBias);
}

_RingBands _outerRingsFromMaskOut(
  cv.Mat maskOut, {
  int? offsetPx,
  int? thickPx,
}) {
  final int minSide = math.min(maskOut.rows, maskOut.cols);

  final int baseOff = (minSide * _RING_OFFSET_FRAC).round().clamp(
    _RING_OFFSET_MIN,
    _RING_OFFSET_MAX,
  );
  final int baseThk = (minSide * _RING_THICK_FRAC).round().clamp(
    _RING_THICK_MIN,
    _RING_THICK_MAX,
  );

  final int off = offsetPx ?? baseOff;
  final int thk = thickPx ?? baseThk;
  final int thkInner = math.max(
    _RING_THICK_MIN,
    (thk * _INNER_PORTION).round(),
  );

  // mask_out ขาว=นอก → ใช้ ERODE ยุบ “นอก” ถอยเข้าไปจากเส้น
  final cv.Mat erOff = cv.erode(maskOut, _ellipK(off));
  final cv.Mat erOffThk = cv.erode(maskOut, _ellipK(off + thk));
  final cv.Mat erOffThin = cv.erode(maskOut, _ellipK(off + thkInner));

  // ringAll = erOff AND NOT(erOffThk)
  final cv.Mat not2 = cv.bitwiseNOT(erOffThk);
  final cv.Mat ringAll = cv.Mat.zeros(maskOut.rows, maskOut.cols, maskOut.type);
  erOff.copyTo(ringAll, mask: not2);

  // ringInnerBias = erOff AND NOT(erOffThin)
  final cv.Mat notThin = cv.bitwiseNOT(erOffThin);
  final cv.Mat ringInner = cv.Mat.zeros(
    maskOut.rows,
    maskOut.cols,
    maskOut.type,
  );
  erOff.copyTo(ringInner, mask: notThin);

  // กันเส้นหนา/เอียง โดยไม่ให้นับทับ outline ด้านใน
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

  // เปิดรูเล็ก ๆ
  return _RingBands(
    cv.morphologyEx(safeAll, cv.MORPH_OPEN, _rectK(3)),
    cv.morphologyEx(safeInner, cv.MORPH_OPEN, _rectK(3)),
  );
}

/// ---------- Quantile ของ V (0..255) ภายใน mask ----------
int _quantileInMask(cv.Mat gray8, cv.Mat maskBin, double q) {
  int lo = 0, hi = 255, ans = 255;
  final int area = cv.countNonZero(maskBin);
  if (area <= 0) return 255;
  while (lo <= hi) {
    final int mid = (lo + hi) >> 1;
    final cv.Mat inv = cv
        .threshold(gray8, mid.toDouble(), 255.0, cv.THRESH_BINARY_INV)
        .$2;
    final cv.Mat masked = cv.Mat.zeros(gray8.rows, gray8.cols, gray8.type);
    inv.copyTo(masked, mask: maskBin);
    final int cnt = cv.countNonZero(masked); // จำนวน <= mid
    if (cnt >= (area * q).round()) {
      ans = mid;
      hi = mid - 1;
    } else {
      lo = mid + 1;
    }
  }
  return ans;
}

/// ใช้พื้นที่นอกเส้นแต่อยู่ไกลจากเส้น/ขอบพอสมควร เพื่ออ้างอิง “หน้ากระดาษจริง”
cv.Mat _paperRefMask(cv.Mat maskOut) {
  cv.Mat bg = cv.erode(maskOut, _ellipK(9));
  bg = cv.erode(bg, _ellipK(5));
  return bg;
}

/// ---------- มาสก์ “สี” ที่นับว่าเป็นการระบาย (paper-aware ครอบคลุมทุกเฉด) ----------
cv.Mat _coloredMask(cv.Mat gray, cv.Mat sat, cv.Mat maskOut) {
  // 1) อ้างอิงกระดาษจริง
  final cv.Mat paperMask = _paperRefMask(maskOut);
  final int paperQ80 = _quantileInMask(
    gray,
    paperMask,
    0.80,
  ); // Q80 ของ V นอกเส้น
  final int dynNearWhite = math.min(
    _NEARWHITE_MAX,
    math.max(_NEARWHITE_MIN, paperQ80 + 6),
  );
  final int dynDarkThr = math.max(40, math.min(200, paperQ80 - 70));

  // 2) สีอิ่ม + สว่างพอ (สำหรับสีเทียน/ปากกา/พาสเทลอ่อน)
  final cv.Mat sGt = cv
      .threshold(sat, _S_COLORED_MIN.toDouble(), 255.0, cv.THRESH_BINARY)
      .$2;
  final cv.Mat vBright = cv
      .threshold(gray, _V_BRIGHT_MIN.toDouble(), 255.0, cv.THRESH_BINARY)
      .$2;
  final cv.Mat bySat = cv
      .threshold(cv.add(sGt, vBright), 1.0, 255.0, cv.THRESH_BINARY)
      .$2;

  // 3) ดำ/กราไฟท์/หมึก (ไม่ต้องพึ่ง S)
  final cv.Mat vDarkDyn = cv
      .threshold(gray, dynDarkThr.toDouble(), 255.0, cv.THRESH_BINARY_INV)
      .$2;

  // รวม “สีอิ่ม” OR “ดำกราไฟท์”
  final cv.Mat coloredPre = cv
      .threshold(cv.add(bySat, vDarkDyn), 1.0, 255.0, cv.THRESH_BINARY)
      .$2;

  // 4) ตัดกระดาษ (ใกล้ขาว) ออกให้หมด
  final cv.Mat sNearW = cv
      .threshold(sat, 15.0, 255.0, cv.THRESH_BINARY_INV)
      .$2; // S ต่ำมาก
  final cv.Mat vNearW = cv
      .threshold(gray, dynNearWhite.toDouble(), 255.0, cv.THRESH_BINARY)
      .$2;
  final cv.Mat nearW = cv
      .threshold(cv.add(sNearW, vNearW), 1.0, 255.0, cv.THRESH_BINARY)
      .$2;

  // 5) กันเส้นเทมเพลตด้านในไม่ให้ถูกนับ
  final cv.Mat inside = cv.bitwiseNOT(maskOut); // ขาว=ใน
  final cv.Mat outline = cv.morphologyEx(inside, cv.MORPH_GRADIENT, _ellipK(2));
  final cv.Mat outlineFat = cv.dilate(outline, _rectK(1));
  final cv.Mat noOutline = cv
      .threshold(outlineFat, 0.0, 255.0, cv.THRESH_BINARY_INV)
      .$2;

  // 6) รวมเงื่อนไข + เปิด/ปิดรูให้เนียน
  final cv.Mat tmp = cv.Mat.zeros(gray.rows, gray.cols, gray.type);
  coloredPre.copyTo(tmp, mask: noOutline);

  final cv.Mat colored = cv.Mat.zeros(gray.rows, gray.cols, gray.type);
  tmp.copyTo(colored, mask: cv.bitwiseNOT(nearW));

  final cv.Mat opened = cv.morphologyEx(colored, cv.MORPH_OPEN, _rectK(3));
  final cv.Mat closed = cv.morphologyEx(opened, cv.MORPH_CLOSE, _rectK(3));
  return closed;
}

/// ===================================================================
/// Public API
Future<double> computeCotl(cv.Mat gray, cv.Mat sat, cv.Mat maskOut) async {
  // เตรียมข้อมูล (ลดนอยส์เล็กน้อย)
  final cv.Mat mOut = _tightenMaskOut(_ensureMaskOut(maskOut));
  final cv.Mat grayMed = cv.medianBlur(gray, 3);

  // วงแหวนรอบเส้นด้านนอก (2 ชั้น)
  _RingBands rings = _outerRingsFromMaskOut(mOut);
  int areaAll = cv.countNonZero(rings.ringAll);
  int areaInner = cv.countNonZero(rings.ringInnerBias);

  // Fallback: ถ้าบาง/เล็กเกิน ลองขยาย 20%
  if (areaAll < 150 || areaInner < 80) {
    final int minSide = math.min(mOut.rows, mOut.cols);
    final int off2 = (minSide * (_RING_OFFSET_FRAC * 1.20)).round().clamp(
      _RING_OFFSET_MIN,
      _RING_OFFSET_MAX,
    );
    final int th2 = (minSide * (_RING_THICK_FRAC * 1.20)).round().clamp(
      _RING_THICK_MIN,
      _RING_THICK_MAX,
    );
    rings = _outerRingsFromMaskOut(mOut, offsetPx: off2, thickPx: th2);
    areaAll = cv.countNonZero(rings.ringAll);
    areaInner = cv.countNonZero(rings.ringInnerBias);
  }
  if (areaAll <= 0) {
    print('⚠️ [COTL] ring area = 0');
    return 0.0;
  }

  // “สีที่นับว่าเป็นการระบาย” (ครอบคลุมทุกเฉด + ตัดกระดาษ/เส้น)
  final cv.Mat colored = _coloredMask(grayMed, sat, mOut);

  // นับบนวงแหวน
  cv.Mat colAll = cv.Mat.zeros(colored.rows, colored.cols, colored.type);
  cv.Mat colInner = cv.Mat.zeros(colored.rows, colored.cols, colored.type);
  colored.copyTo(colAll, mask: rings.ringAll);
  colored.copyTo(colInner, mask: rings.ringInnerBias);

  colAll = cv.morphologyEx(colAll, cv.MORPH_OPEN, _rectK(3));
  colInner = cv.morphologyEx(colInner, cv.MORPH_OPEN, _rectK(3));

  final int hitAll = cv.countNonZero(colAll);
  final int hitInner = cv.countNonZero(colInner);
  final double rAll = (hitAll / areaAll).clamp(0.0, 1.0);
  final double rInner = (hitInner / math.max(1, areaInner)).clamp(0.0, 1.0);

  // snap → 1.0 หากท่วมมากเป็นพิเศษ
  if (rAll >= _SNAP_RALL || rInner >= _SNAP_RINNER) {
    print(
      '[COTL] snap→1.0 (pre-blend) rAll=${rAll.toStringAsFixed(3)} rInner=${rInner.toStringAsFixed(3)}',
    );
    return 1.0;
  }

  // รวมแบบให้น้ำหนักชั้นในมากกว่า
  double ratio = (_INNER_WEIGHT * rInner) + ((1.0 - _INNER_WEIGHT) * rAll);

  // การ์ดสุดท้าย
  if (ratio >= _SNAP_POST_BLEND) {
    print('[COTL] snap→1.0 (post-blend) ratio=${ratio.toStringAsFixed(3)}');
    return 1.0;
  }

  // Debug
  print(
    '[COTL] areaAll=$areaAll areaInner=$areaInner rAll=${rAll.toStringAsFixed(3)} rInner=${rInner.toStringAsFixed(3)} ratio=${ratio.toStringAsFixed(3)}',
  );

  return ratio.clamp(0.0, 1.0);
}
