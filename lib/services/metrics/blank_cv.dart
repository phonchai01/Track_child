// lib/services/metrics/blank_cv.dart
import 'package:opencv_dart/opencv_dart.dart' as cv;

const int _kEdgeBandPxDefault = 2;
const int _kOpenK = 3;
const int _kCloseK = 3;
const int _kEqHist = 0;
const int _kPaperErode = 0;

cv.Mat _rectK(int k) => cv.getStructuringElement(0, (k, k));
cv.Mat _to8U(cv.Mat m) => (m.type == 0) ? m : cv.convertScaleAbs(m);
cv.Mat _bin(cv.Mat m) =>
    cv.threshold(_to8U(m), 0.0, 255.0, cv.THRESH_BINARY).$2;

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

_Params _seedParams(double avgB, int tBright, int tMin, int tMax) {
  final tPaper = (avgB < 140)
      ? (tBright + 40).clamp(150, tMax)
      : tBright.clamp(tMin, tMax);
  final sMin = 70;
  final vDark = (avgB < 120) ? 135 : 125;
  final pastel = (avgB < 120) ? 12 : 16;
  final grow = (avgB < 120) ? 6 : 8;
  return _Params(sMin, vDark, pastel, grow, tPaper);
}

class _MaskCand {
  final cv.Mat keep;
  final int area;
  final double avg;
  final bool inv;
  final int band;
  _MaskCand(this.keep, this.area, this.avg, this.inv, this.band);
}

_MaskCand _prepKeep(
  cv.Mat binMask,
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
  final double paintedRatio;
  final cv.Mat painted;
  _Measure(this.paintedRatio, this.painted);
}

_Measure _measurePainted(
  cv.Mat grayMed,
  cv.Mat satMed,
  cv.Mat keep,
  _Params P,
) {
  // 1) สีสด (S สูง) และ 2) มืดมาก (gray ต่ำ)
  cv.Mat painted = cv.max(
    cv.threshold(satMed, P.sMin.toDouble(), 255.0, cv.THRESH_BINARY).$2,
    cv.threshold(grayMed, P.vDark.toDouble(), 255.0, cv.THRESH_BINARY_INV).$2,
  );

  // 3) พาสเทลแบบ “Max-White” (ใช้ dilate หา local maximum ของความสว่าง)
  final localMax = cv.dilate(grayMed, _rectK(31)); // พิกเซลขาวที่สุดในบริเวณ
  final allow = cv.Mat.zeros(localMax.rows, localMax.cols, localMax.type)
    ..setTo(cv.Scalar.all(P.pastel.toDouble()));
  final target = cv.subtract(localMax, allow);
  final pastelHard = cv
      .threshold(
        cv.max(target, cv.Mat.zeros(target.rows, target.cols, target.type)),
        0.0,
        255.0,
        cv.THRESH_BINARY_INV,
      )
      .$2; // gray < localMax - allowance

  // Gate พาสเทลด้วย S (กันเงาดำ/คราบสกปรก)
  final sGateThr = (P.sMin * 0.5).clamp(12, 90).toInt();
  final sGate = cv
      .threshold(satMed, sGateThr.toDouble(), 255.0, cv.THRESH_BINARY)
      .$2;
  final pastelMask = cv.bitwiseAND(pastelHard, sGate);

  painted = cv.max(painted, pastelMask);

  // Edge guard: ตัดเส้น outline ออก
  final edges = cv.canny(grayMed, 60, 120);
  final edgesDil = cv.dilate(edges, _rectK(1 + 2 * _kEdgeBandPxDefault));
  final edgesInv = cv.threshold(edgesDil, 0.0, 255.0, cv.THRESH_BINARY_INV).$2;

  // keep only inside & not edge
  painted = cv.bitwiseAND(painted, keep);
  painted = cv.bitwiseAND(painted, edgesInv);

  // ทำความสะอาด
  painted = cv.morphologyEx(painted, cv.MORPH_OPEN, _rectK(_kOpenK));
  if (P.grow > 0) painted = cv.dilate(painted, _rectK(P.grow));

  final pr = cv.countNonZero(painted) / cv.countNonZero(keep);
  return _Measure(pr, painted);
}

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

  // เลือก keepInside
  final m0 = _bin(inLineMask);
  final m1 = cv.threshold(m0, 0.0, 255.0, cv.THRESH_BINARY_INV).$2;
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
  if (safeArea <= 0) return 1.0;

  // สถิติพื้นฐาน
  final avgB = cand.avg;
  final qBright = (avgB < 140) ? 0.55 : 0.42;
  final tBright = _tailGEQuantile(grayMed, keep, qBright);

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

  // ปรับ Smin จาก s-tail
  final sTail = _tailGEQuantile(satMed, keep, 0.20);
  P.sMin = (sTail * 0.80).clamp(24, 110).toInt();

  // วัดครั้งที่ 1
  _Measure meas = _measurePainted(grayMed, satMed, keep, P);

  // Auto-tune (เบาลง เพราะเราแก้ pastel แล้ว)
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
    print(
      'Tune#$it painted=${(meas.paintedRatio * 100).toStringAsFixed(1)}% '
      'Smin=${P.sMin} vDark=${P.vDark} pastel=${P.pastel} grow=${P.grow} Tpaper=${P.tPaper}',
    );
  }

  // กระดาษจริง = ขาว & NOT(painted)
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

Future<double> computeBlankFromBgr(cv.Mat bgr, cv.Mat inLineMask) async {
  final hsv = cv.cvtColor(bgr, cv.COLOR_BGR2HSV);
  final hs = cv.split(hsv) as List<cv.Mat>;
  final sat = hs[1];
  final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
  return computeBlank(gray, sat, inLineMask);
}
