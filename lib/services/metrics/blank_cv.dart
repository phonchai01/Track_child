// lib/services/metrics/blank_cv.dart
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// --------------------------- Tunables ---------------------------
const int _kEdgeBandPxDefault = 2; // guard เส้นขอบ template
const int _kOpenK = 3; // ทำความสะอาดจุดเล็ก ๆ
const int _kCloseK = 3; // ปิดรูพรุนเล็ก ๆ
const int _kEqHist = 0; // 1=เปิด equalizeHist (ส่วนมากไม่จำเป็น)
const int _kPaperErode = 0; // 0-2 (กันรอยหมึกบางมาก ๆ ติดเป็นกระดาษ)

// คอร์นเนลสี่เหลี่ยม/วงรี
cv.Mat _rectK(int k) => cv.getStructuringElement(0, (k, k)); // MORPH_RECT
cv.Mat _ellipK(int k) => cv.getStructuringElement(2, (k, k)); // MORPH_ELLIPSE

/// แปลงเป็น 8U อย่างปลอดภัย (opencv_dart ไม่มี cv.CV_8U ให้เทียบโดยตรง)
cv.Mat _to8U(cv.Mat m) {
  try {
    // ถ้าเป็น float/int อื่น ๆ จะถูก scale-abs -> 8U
    return cv.convertScaleAbs(m);
  } catch (_) {
    // ถ้าเดิมเป็น 8U อยู่แล้ว จะ throw ในบางกรณี — ส่งกลับตามเดิม
    return m;
  }
}

/// ทำเป็น Binary 0/255
cv.Mat _bin(cv.Mat m) =>
    cv.threshold(_to8U(m), 0.0, 255.0, cv.THRESH_BINARY).$2;

/// หา threshold แบบ “เปอร์เซ็นต์ตรรกะ tail ด้านสว่าง” ภายใต้ mask
int _tailGEQuantile(cv.Mat img8, cv.Mat mask, double q) {
  final area = cv.countNonZero(mask);
  if (area <= 0) return 255;
  int lo = 0, hi = 255, ans = 255;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final bin = cv.threshold(img8, mid.toDouble(), 255.0, cv.THRESH_BINARY).$2;
    final cnt = cv.countNonZero(cv.bitwiseAND(bin, mask));
    final ratio = cnt / area;
    if (ratio >= q) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

class _Params {
  int sMin, vDark, pastel, grow, tPaper;
  _Params(this.sMin, this.vDark, this.pastel, this.grow, this.tPaper);
}

/// สร้างพารามิเตอร์ตั้งต้นตามความสว่างเฉลี่ยของกระดาษ (avgB) และ quantile ของสว่าง (tBright)
_Params _seedParams(double avgB, int tBright, int tMin, int tMax) {
  final tPaper = (avgB < 140)
      ? (tBright + 40).clamp(150, tMax)
      : tBright.clamp(tMin, tMax);
  final sMin = 70; // เริ่มที่ S สูงพอควร
  final vDark = (avgB < 120) ? 135 : 125; // กันเงาดำ/ดินสอเข้ม
  final pastel = (avgB < 120) ? 12 : 16; // อนุโลมพาสเทลเมื่อพื้นมืด
  final grow = (avgB < 120) ? 6 : 8; // เติมให้สีทึบขึ้นเล็กน้อย
  return _Params(sMin, vDark, pastel, grow, tPaper);
}

class _MaskCand {
  final cv.Mat keep; // mask “พื้นที่ภายในเส้นแต่ห่างขอบ” ที่ยอมให้นับสี
  final int area; // พื้นที่ที่ปลอดภัย
  final double avg; // ค่าเฉลี่ยความสว่างใน keep (ประมาณกระดาษจริง)
  final bool inv; // ใช้ด้านกลับหรือไม่
  final int band; // ขนาด band ที่เลือกได้
  _MaskCand(this.keep, this.area, this.avg, this.inv, this.band);
}

/// เตรียม keep-mask โดยลบแถบขอบออก (เลือก bandwidth ที่ให้พื้นที่ดีสุด)
_MaskCand _prepKeep(
  cv.Mat binMask, // ขาว=ภายในเส้น (หรือภายนอก ถ้าส่งแบบกลับ)
  cv.Mat grayMed,
  int defBand, {
  required bool invFlag,
}) {
  final preArea = cv.countNonZero(binMask);
  final tries = <int>[defBand, 1, 0].toSet().toList()..sort();

  cv.Mat best = binMask;
  int bestArea = -1;
  int bestBand = defBand;

  for (final b in tries) {
    final edge = cv.morphologyEx(binMask, cv.MORPH_GRADIENT, _rectK(3));
    final band = (b > 0) ? cv.dilate(edge, _rectK(1 + 2 * b)) : edge;

    // keep = mask & !band (ตัดแถบขอบออกจากภายใน)
    final keep = cv.bitwiseAND(
      binMask,
      cv.threshold(band, 0, 255.0, cv.THRESH_BINARY_INV).$2,
    );
    final a = cv.countNonZero(keep);
    if (a >= preArea * 0.25 && a > bestArea) {
      best = keep;
      bestArea = a;
      bestBand = b;
    }
  }

  // เผื่อกรณีไหน ๆ ไม่ผ่านเงื่อนไข
  if (bestArea < 0) {
    final edge = cv.morphologyEx(binMask, cv.MORPH_GRADIENT, _rectK(3));
    final keep = cv.bitwiseAND(
      binMask,
      cv.threshold(edge, 0, 255.0, cv.THRESH_BINARY_INV).$2,
    );
    best = keep;
    bestArea = cv.countNonZero(keep);
    bestBand = 0;
  }

  final avg = (bestArea > 0) ? cv.mean(grayMed, mask: best).val[0] : 0.0;
  return _MaskCand(best, bestArea, avg, invFlag, bestBand);
}

class _Measure {
  final double paintedRatio; // สัดส่วนที่ทาสีจริงในพื้นที่ปลอดภัย
  final cv.Mat painted; // แผนที่พิกเซลที่ถือว่า “ทาสี”
  _Measure(this.paintedRatio, this.painted);
}

/// ตรวจหาพิกเซลที่ถือว่า “ทาสี” (รวมพาสเทล + กรองเส้น + กรองเงา)
_Measure _measurePainted(
  cv.Mat grayMed,
  cv.Mat satMed,
  cv.Mat keep,
  _Params P,
) {
  // 1) สีสด (S สูง) OR 2) มืดจัด (กันดินสอ/หมึก)
  cv.Mat painted = cv.max(
    cv.threshold(satMed, P.sMin.toDouble(), 255.0, cv.THRESH_BINARY).$2,
    cv.threshold(grayMed, P.vDark.toDouble(), 255.0, cv.THRESH_BINARY_INV).$2,
  );

  // 3) พาสเทลด้วย “Max-White trick”: gray < localMax - allowance
  final localMax = cv.dilate(grayMed, _rectK(31)); // ค่าขาวสูงสุดในบริเวณ
  // allowance = ค่าคงที่ P.pastel (ทำเป็น Mat แล้ว setTo ด้วย Scalar)
  final allow = cv.Mat.zeros(localMax.rows, localMax.cols, localMax.type)
    ..setTo(cv.Scalar.all(P.pastel.toDouble()));

  final target = cv.subtract(localMax, allow); // localMax - allowance

  final pastelHard = cv
      .threshold(
        cv.max(target, cv.Mat.zeros(target.rows, target.cols, target.type)),
        0.0,
        255.0,
        cv.THRESH_BINARY_INV,
      )
      .$2;

  // Gate พาสเทลด้วย S (กันคราบมืด/เงา)
  final sGateThr = (P.sMin * 0.5).clamp(12, 90).toInt();
  final sGate = cv
      .threshold(satMed, sGateThr.toDouble(), 255.0, cv.THRESH_BINARY)
      .$2;
  final pastelMask = cv.bitwiseAND(pastelHard, sGate);

  painted = cv.max(painted, pastelMask);

  // กันเส้น outline ของ template (เอาขอบออก)
  final edges = cv.canny(grayMed, 60, 120);
  final edgesDil = cv.dilate(edges, _rectK(1 + 2 * _kEdgeBandPxDefault));
  final edgesInv = cv.threshold(edgesDil, 0.0, 255.0, cv.THRESH_BINARY_INV).$2;

  // keep เฉพาะในพื้นที่ปลอดภัยและไม่ใช่ขอบ
  painted = cv.bitwiseAND(painted, keep);
  painted = cv.bitwiseAND(painted, edgesInv);

  // ทำความสะอาด
  painted = cv.morphologyEx(painted, cv.MORPH_OPEN, _rectK(_kOpenK));
  if (P.grow > 0) painted = cv.dilate(painted, _rectK(P.grow));

  final pr = cv.countNonZero(painted) / cv.countNonZero(keep);
  return _Measure(pr, painted);
}

/// =========================== Public API ===========================
/// คืนค่า blank (0..1): สัดส่วน "พื้นที่ในรูปที่ยังว่าง" โดยอิงพื้นที่ปลอดภัย (ไม่ชนขอบ)
Future<double> computeBlank(cv.Mat gray, cv.Mat sat, cv.Mat inLineMask) async {
  final gray8 = _to8U(gray);
  var sat8 = _to8U(sat);

  var g = gray8.clone();
  if (_kEqHist == 1) g = cv.equalizeHist(g);
  final grayMed = cv.medianBlur(g, 3);

  if (sat8.rows != gray8.rows || sat8.cols != gray8.cols) {
    sat8 = cv.resize(sat8, (
      gray8.cols,
      gray8.rows,
    ), interpolation: cv.INTER_NEAREST);
  }
  final satMed = cv.medianBlur(sat8, 3);

  // เตรียม keep-inside (เลือกฝั่งที่ดู “เป็นกระดาษจริง”)
  final m0 = _bin(inLineMask); // ขาว=ใน
  final m1 = cv
      .threshold(m0, 0.0, 255.0, cv.THRESH_BINARY_INV)
      .$2; // ขาว=นอก (กลับขั้ว)
  final c0 = _prepKeep(m0, grayMed, _kEdgeBandPxDefault, invFlag: false);
  final c1 = _prepKeep(m1, grayMed, _kEdgeBandPxDefault, invFlag: true);

  final total = gray8.rows * gray8.cols;
  final bad0 = c0.area > total * 0.60 || c0.area < total * 0.05;
  final bad1 = c1.area > total * 0.60 || c1.area < total * 0.05;

  final cand = bad0 && !bad1
      ? c1
      : bad1 && !bad0
      ? c0
      : (c1.avg > c0.avg + 1.0 ||
            ((c1.avg - c0.avg).abs() <= 1.0 && c1.area > c0.area))
      ? c1
      : c0;

  final keep = cand.keep;
  final safeArea = cand.area;
  if (safeArea <= 0) return 1.0; // เผื่อ mask เสีย ให้ถือว่ายังว่างทั้งหมด

  // ค่าพื้นฐานเพื่อกำหนดเกณฑ์กระดาษ
  final avgB = cand.avg;
  final qBright = (avgB < 140) ? 0.55 : 0.42;
  final tBright = _tailGEQuantile(grayMed, keep, qBright);

  // กำหนดช่วง (tMin,tMax) ตามความสว่างรวม ๆ
  int tMin, tMax;
  if (avgB >= 240) {
    tMin = 210;
    tMax = 230;
  } else if (avgB >= 210) {
    tMin = 212;
    tMax = 232;
  } else if (avgB >= 170) {
    tMin = 214;
    tMax = 234;
  } else {
    tMin = 216;
    tMax = 236;
  }

  var P = _seedParams(avgB, tBright, tMin, tMax);
  if (avgB < 100) {
    P.vDark = (P.vDark + 25).clamp(110, 180);
    P.pastel = (P.pastel + 6).clamp(10, 24);
    P.grow = (P.grow - 1).clamp(3, 8);
  }

  // ปรับ Smin อิง s-tail ภายในพื้นที่ปลอดภัย
  final sTail = _tailGEQuantile(satMed, keep, 0.20);
  P.sMin = (sTail * 0.80).clamp(24, 110).toInt();

  // วัด “ทาสีแล้ว” ครั้งที่ 1
  _Measure meas = _measurePainted(grayMed, satMed, keep, P);

  // Auto-tune เบา ๆ (เพื่อดัน paintedRatio ให้อยู่ 65–85%)
  const double lo = 0.65, hi = 0.85;
  for (int it = 0; it < 3; it++) {
    if (meas.paintedRatio >= lo && meas.paintedRatio <= hi) break;

    if (meas.paintedRatio > hi) {
      final over = (meas.paintedRatio - hi).clamp(0.0, 0.30);
      P.sMin = (P.sMin + (14 + 40 * over)).round().clamp(40, 130);
      P.vDark = (P.vDark + (18 + 45 * over)).round().clamp(140, 200);
      P.pastel = (P.pastel + (6 + 16 * over)).round().clamp(14, 28);
      P.grow = (P.grow - 1).clamp(2, 8);
      P.tPaper = (P.tPaper + (10 + 20 * over)).round().clamp(160, 230);
    } else {
      final under = (lo - meas.paintedRatio).clamp(0.0, 0.30);
      P.sMin = (P.sMin - (10 + 30 * under)).round().clamp(10, 100);
      P.vDark = (P.vDark - (15 + 40 * under)).round().clamp(100, 190);
      P.pastel = (P.pastel - (5 + 12 * under)).round().clamp(6, 24);
      P.grow = (P.grow + 1).clamp(2, 10);
      P.tPaper = (P.tPaper - (8 + 18 * under)).round().clamp(140, 230);
    }

    meas = _measurePainted(grayMed, satMed, keep, P);
    // debug
    print(
      'Tune#$it painted=${(meas.paintedRatio * 100).toStringAsFixed(1)}% '
      'Smin=${P.sMin} vDark=${P.vDark} pastel=${P.pastel} '
      'grow=${P.grow} Tpaper=${P.tPaper}',
    );
  }

  // กระดาษจริง = (สว่างมาก) & (ไม่ใช่พื้นที่ทาสี)
  cv.Mat paper = cv
      .threshold(grayMed, P.tPaper.toDouble(), 255.0, cv.THRESH_BINARY)
      .$2;
  paper = cv.bitwiseAND(paper, keep);
  paper = cv.bitwiseAND(paper, cv.bitwiseNOT(meas.painted));
  paper = cv.morphologyEx(paper, cv.MORPH_CLOSE, _rectK(_kCloseK));
  paper = cv.morphologyEx(paper, cv.MORPH_OPEN, _rectK(_kOpenK));
  if (_kPaperErode > 0) paper = cv.erode(paper, _rectK(_kPaperErode));

  final paperCnt = cv.countNonZero(paper);
  final blankPaper = (paperCnt.toDouble() / safeArea).clamp(0.0, 1.0);
  final blankPainted = (1.0 - meas.paintedRatio).clamp(0.0, 1.0);
  final blank = (blankPaper < blankPainted ? blankPaper : blankPainted);

  // debug logs
  print(
    'PaintedDbg: painted=${(meas.paintedRatio * 100).toStringAsFixed(1)}% safeArea=$safeArea',
  );
  print(
    'BlankDbg[AUTO]: area=$safeArea paper=$paperCnt blank=${blank.toStringAsFixed(3)} '
    'avgB=${avgB.toStringAsFixed(1)} Tpaper=${P.tPaper} '
    'Smin=${P.sMin} vDark=${P.vDark} pastel=${P.pastel} grow=${P.grow} '
    'tBright=$tBright sTail=$sTail inverted=${cand.inv} bandPx=${cand.band}',
  );

  return blank;
}

/// helper: กรณีมี bgr อย่างเดียว
Future<double> computeBlankFromBgr(cv.Mat bgr, cv.Mat inLineMask) async {
  final hsv = cv.cvtColor(bgr, cv.COLOR_BGR2HSV);
  final hs = cv.split(hsv) as List<cv.Mat>;
  final sat = hs[1];
  final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
  return computeBlank(gray, sat, inLineMask);
}
