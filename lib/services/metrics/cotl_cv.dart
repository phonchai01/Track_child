// lib/services/metrics/cotl_cv.dart
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:math' as math;

/// ================= Tunables (จูนให้ COTL ตอบสนองของจริง) =================
/// สี/ความมืด
const int _S_COLORED_MIN = 26;
const int _V_BRIGHT_MIN  = 80;
const int _V_DARK_MAX    = 172;
const int _S_NEARWHITE   = 15;
const int _V_NEARWHITE   = 242;

/// วงแหวน (แคบลงและชิดเส้นกว่าเดิม)
const double _RING_OFFSET_FRAC = 0.0025;   // เดิม 0.005 → ครึ่งหนึ่ง
const double _RING_THICK_FRAC  = 0.0075;   // เดิม 0.012 → บางลง

/// ขีดจำกัด (px)
const int _RING_OFFSET_MIN = 1,  _RING_OFFSET_MAX = 8;
const int _RING_THICK_MIN  = 1,  _RING_THICK_MAX  = 12;

/// Edge-bias
const double _INNER_PORTION = 0.75;  // เดิม 0.60
const double _INNER_WEIGHT  = 0.90;  // เดิม 0.80

/// เกณฑ์ snap → 1.0
const double _SNAP_RALL        = 0.94;
const double _SNAP_RINNER      = 0.96;
const double _SNAP_POST_BLEND  = 0.965; // รวมแล้วสูงมาก → เด้งเป็น 1.0

// ---------------------------------------------------------------------
// Small helpers
cv.Mat _rectK(int k)  => cv.getStructuringElement(0, (k, k));
cv.Mat _ellipK(int k) => cv.getStructuringElement(2, (k, k));

cv.Mat _bin(cv.Mat m) {
  if (m.channels > 1) m = cv.cvtColor(m, cv.COLOR_BGR2GRAY);
  return cv.threshold(m, 127.0, 255.0, 0 /*BINARY*/).$2;
}

/// รับ **mask_out เท่านั้น** (ขาว=นอก, ดำ=ใน) — เช็ค 4 มุมแล้วกลับขั้วถ้าจำเป็น
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
  for (final r in rois) { white += cv.countNonZero(r); total += r.rows * r.cols; }
  final double ratio = white / total;
  if (ratio < 0.5) m = cv.bitwiseNOT(m); // คว่ำให้เป็น mask_out
  return m;
}

/// ดันขอบ mask_out ให้ “ชิดเส้นใน” มากขึ้นเล็กน้อย (ทำให้วงแหวนไปอยู่ตรงจุดที่สีเลยจริง)
cv.Mat _tightenMaskOut(cv.Mat maskOut) {
  // กลับเป็นด้านใน → ขยายเล็กน้อย → กลับเป็น mask_out
  final cv.Mat inside = cv.bitwiseNOT(maskOut);      // ขาว = พื้นที่ใน
  final cv.Mat expandedInside = cv.dilate(inside, _ellipK(2)); // ขยายด้านในเล็กน้อย
  final cv.Mat tightened = cv.bitwiseNOT(expandedInside);       // กลับเป็น mask_out
  return tightened;
}

/// สร้างวงแหวนด้านนอก (ทั้งวง + โซนชิดเส้น)
class _RingBands {
  final cv.Mat ringAll;
  final cv.Mat ringInnerBias;
  _RingBands(this.ringAll, this.ringInnerBias);
}

_RingBands _outerRingsFromMaskOut(cv.Mat maskOut, {int? offsetPx, int? thickPx}) {
  final int minSide = math.min(maskOut.rows, maskOut.cols);
  final int baseOff = (minSide * _RING_OFFSET_FRAC).round()
      .clamp(_RING_OFFSET_MIN, _RING_OFFSET_MAX);
  final int baseThk = (minSide * _RING_THICK_FRAC).round()
      .clamp(_RING_THICK_MIN, _RING_THICK_MAX);

  final int off = (offsetPx ?? baseOff);
  final int thk = (thickPx  ?? baseThk);
  final int thkInner = math.max(_RING_THICK_MIN, (thk * _INNER_PORTION).round());

  // mask_out ขาว=นอก → ใช้ ERODE ยุบออกจากเส้น
  final cv.Mat erOff     = cv.erode(maskOut, _ellipK(off));
  final cv.Mat erOffThk  = cv.erode(maskOut, _ellipK(off + thk));
  final cv.Mat erOffThin = cv.erode(maskOut, _ellipK(off + thkInner));

  // ringAll = erOff AND NOT(erOffThk)
  final cv.Mat not2 = cv.bitwiseNOT(erOffThk);
  final cv.Mat ringAll = cv.Mat.zeros(maskOut.rows, maskOut.cols, maskOut.type);
  erOff.copyTo(ringAll, mask: not2);

  // ringInnerBias = erOff AND NOT(erOffThin)
  final cv.Mat notThin = cv.bitwiseNOT(erOffThin);
  final cv.Mat ringInner = cv.Mat.zeros(maskOut.rows, maskOut.cols, maskOut.type);
  erOff.copyTo(ringInner, mask: notThin);

  // กันเส้นหนา/เอียง
  final cv.Mat outline    = cv.morphologyEx(cv.bitwiseNOT(maskOut), 3 /*GRADIENT*/, _ellipK(2));
  final cv.Mat outlineFat = cv.dilate(outline, _rectK(1));
  final cv.Mat safeAll    = cv.Mat.zeros(ringAll.rows, ringAll.cols, ringAll.type);
  final cv.Mat safeInner  = cv.Mat.zeros(ringInner.rows, ringInner.cols, ringInner.type);
  ringAll.copyTo(safeAll,    mask: cv.bitwiseNOT(outlineFat));
  ringInner.copyTo(safeInner, mask: cv.bitwiseNOT(outlineFat));

  return _RingBands(
    cv.morphologyEx(safeAll,   1 /*OPEN*/, _rectK(3)),
    cv.morphologyEx(safeInner, 1 /*OPEN*/, _rectK(3)),
  );
}

/// สีที่นับเป็นการระบาย (ไม่ใช่เส้น/ไม่ใช่กระดาษ)
cv.Mat _coloredMask(cv.Mat gray, cv.Mat sat, cv.Mat maskOut) {
  final cv.Mat sGt     = cv.threshold(sat,  _S_COLORED_MIN.toDouble(), 255.0, 0).$2;
  final cv.Mat vBright = cv.threshold(gray, _V_BRIGHT_MIN.toDouble(), 255.0, 0).$2;
  final cv.Mat bySat   = cv.threshold(cv.add(sGt, vBright), 1.0, 255.0, 0).$2;

  final cv.Mat vDark   = cv.threshold(gray, _V_DARK_MAX.toDouble(), 255.0, 1 /*INV*/).$2;
  final cv.Mat coloredPre = cv.threshold(cv.add(bySat, vDark), 1.0, 255.0, 0).$2;

  // ตัดกระดาษ
  final cv.Mat sNearW  = cv.threshold(sat,  _S_NEARWHITE.toDouble(), 255.0, 1 /*INV*/).$2;
  final cv.Mat vNearW  = cv.threshold(gray, _V_NEARWHITE.toDouble(), 255.0, 0 /*BIN*/).$2;
  final cv.Mat nearW   = cv.threshold(cv.add(sNearW, vNearW), 1.0, 255.0, 0).$2;

  // ตัดเส้นเทมเพลต
  final cv.Mat inside     = cv.bitwiseNOT(maskOut);
  final cv.Mat outline    = cv.morphologyEx(inside, 3 /*GRADIENT*/, _ellipK(2));
  final cv.Mat outlineFat = cv.dilate(outline, _rectK(1));
  final cv.Mat noOutline  = cv.threshold(outlineFat, 0.0, 255.0, 1 /*INV*/).$2;

  final cv.Mat tmp = cv.Mat.zeros(gray.rows, gray.cols, gray.type);
  coloredPre.copyTo(tmp, mask: noOutline);
  final cv.Mat colored = cv.Mat.zeros(gray.rows, gray.cols, gray.type);
  tmp.copyTo(colored, mask: cv.bitwiseNOT(nearW));

  // smooth
  final cv.Mat opened  = cv.morphologyEx(colored, 1 /*OPEN*/,  _rectK(3));
  final cv.Mat closed  = cv.morphologyEx(opened,  3 /*CLOSE*/, _rectK(3));
  return closed;
}

/// ===================================================================
/// Public API
Future<double> computeCotl(cv.Mat gray, cv.Mat sat, cv.Mat maskOut) async {
  // บีบขอบ mask_out ให้ชิดเส้นก่อน
  final cv.Mat mOut    = _tightenMaskOut(_ensureMaskOut(maskOut));
  final cv.Mat grayMed = cv.medianBlur(gray, 3);

  // วงแหวน
  _RingBands rings = _outerRingsFromMaskOut(mOut);
  int areaAll   = cv.countNonZero(rings.ringAll);
  int areaInner = cv.countNonZero(rings.ringInnerBias);

  if (areaAll < 150 || areaInner < 80) {
    final int minSide = math.min(mOut.rows, mOut.cols);
    final int off2 = (minSide * (_RING_OFFSET_FRAC * 1.20)).round()
        .clamp(_RING_OFFSET_MIN, _RING_OFFSET_MAX);
    final int th2  = (minSide * (_RING_THICK_FRAC  * 1.20)).round()
        .clamp(_RING_THICK_MIN, _RING_THICK_MAX);
    rings     = _outerRingsFromMaskOut(mOut, offsetPx: off2, thickPx: th2);
    areaAll   = cv.countNonZero(rings.ringAll);
    areaInner = cv.countNonZero(rings.ringInnerBias);
  }
  if (areaAll <= 0) {
    print('⚠️ COTL: ringArea=0');
    return 0.0;
  }

  // สีที่เป็นการระบาย
  final cv.Mat colored = _coloredMask(grayMed, sat, mOut);

  // นับสีบนวงแหวน
  cv.Mat colAll   = cv.Mat.zeros(colored.rows, colored.cols, colored.type);
  cv.Mat colInner = cv.Mat.zeros(colored.rows, colored.cols, colored.type);
  colored.copyTo(colAll,   mask: rings.ringAll);
  colored.copyTo(colInner, mask: rings.ringInnerBias);

  colAll   = cv.morphologyEx(colAll,   1 /*OPEN*/, _rectK(3));
  colInner = cv.morphologyEx(colInner, 1 /*OPEN*/, _rectK(3));

  int  hitAll   = cv.countNonZero(colAll);
  int  hitInner = cv.countNonZero(colInner);
  double rAll   = (hitAll   / areaAll).clamp(0.0, 1.0);
  double rInner = (hitInner / math.max(1, areaInner)).clamp(0.0, 1.0);

  // snap (ก่อน fallback)
  if (rAll >= _SNAP_RALL || rInner >= _SNAP_RINNER) {
    print('[COTL] snap→1.0 (coverage pre-fallback) rAll=${rAll.toStringAsFixed(3)} rInner=${rInner.toStringAsFixed(3)}');
    return 1.0;
  }

  // ผสมแบบ edge-bias
  double ratio = (_INNER_WEIGHT * rInner) + ((1.0 - _INNER_WEIGHT) * rAll);

  // Fallback เมื่อ ratio ต่ำมาก → อนุโลมเทามืดจัดบนแหวน
  if (ratio <= 0.0) {
    final cv.Mat darker = cv.threshold(grayMed, (_V_DARK_MAX + 10).toDouble(), 255.0, 1).$2;
    final cv.Mat notOutline = cv.threshold(
      cv.dilate(cv.morphologyEx(cv.bitwiseNOT(mOut), 3, _ellipK(2)), _rectK(3)),
      0.0, 255.0, 1 /*INV*/).$2;
    final cv.Mat weak = cv.Mat.zeros(darker.rows, darker.cols, darker.type);
    darker.copyTo(weak, mask: notOutline);

    cv.Mat weakOnRing = cv.Mat.zeros(weak.rows, weak.cols, weak.type);
    weak.copyTo(weakOnRing, mask: rings.ringAll);

    hitAll   = cv.countNonZero(weakOnRing);
    rAll     = (hitAll / areaAll).clamp(0.0, 1.0);
    // rInner คงเดิม (กรณีนี้เดิมเป็น 0 อยู่แล้ว)
    ratio    = (_INNER_WEIGHT * rInner) + ((1.0 - _INNER_WEIGHT) * rAll);
  }

  // ===== FINAL GUARDS (หลัง fallback) =====

  // A) ภาพมืดเกือบทั้งแผ่น
  final int totalPix = grayMed.rows * grayMed.cols;
  final cv.Mat veryDarkMask = cv.threshold(grayMed, 20.0, 255.0, 1 /*INV*/).$2;
  final int veryDarkCount = cv.countNonZero(veryDarkMask);
  if (veryDarkCount >= (totalPix * 0.95).round()) {
    print('[COTL] snap→1.0 (whole-image very dark) dark=$veryDarkCount/$totalPix');
    return 1.0;
  }

  // B) วงแหวนถูกเติมเกือบเต็มจริง ๆ
  if (hitAll >= areaAll - 1 || (areaInner > 0 && hitInner >= areaInner - 1) ||
      rAll >= 0.985 || rInner >= 0.985) {
    print('[COTL] snap→1.0 (hard-guard) '
          'hitAll=$hitAll/$areaAll rAll=${rAll.toStringAsFixed(3)} '
          'hitInner=$hitInner/$areaInner rInner=${rInner.toStringAsFixed(3)}');
    return 1.0;
  }

  // C) รวมแล้วสูงมาก
  if (ratio >= _SNAP_POST_BLEND) {
    print('[COTL] snap→1.0 (post-blend) ratio=${ratio.toStringAsFixed(3)} '
          'rAll=${rAll.toStringAsFixed(3)} rInner=${rInner.toStringAsFixed(3)}');
    return 1.0;
  }

  // ===============================
  print('[COTL] areaAll=$areaAll areaInner=$areaInner '
        'rAll=${rAll.toStringAsFixed(3)} rInner=${rInner.toStringAsFixed(3)} '
        'ratio=${ratio.toStringAsFixed(3)}');
  return ratio.clamp(0.0, 1.0);
}
