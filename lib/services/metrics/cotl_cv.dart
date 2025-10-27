import 'package:opencv_dart/opencv_dart.dart' as cv;

const int _S_COLORED_MIN = 25;
const int _V_BRIGHT_MIN = 70;
const int _V_DARK_MAX = 110;
const int _S_NEARWHITE = 12;
const int _V_NEARWHITE = 235;

int _cmToPxOnA4ByWidth(
  cv.Mat mask, {
  double cm = 3.0,
  double paperWidthMm = 210.0,
}) {
  final w = mask.cols;
  final pxPerMm = w / paperWidthMm;
  final mm = cm * 10.0;
  final r = (mm * pxPerMm).round();
  return r.clamp(1, 160);
}

cv.Mat _maskOr(cv.Mat a, cv.Mat b) {
  final added = cv.add(a, b);
  return cv.threshold(added, 1, 255.0, 0).$2;
}

cv.Mat _maskAnd(cv.Mat srcMaskA, cv.Mat maskB) {
  final out = cv.Mat.zeros(srcMaskA.rows, srcMaskA.cols, srcMaskA.type);
  srcMaskA.copyTo(out, mask: maskB);
  return out;
}

cv.Mat maskNot(cv.Mat m) {
  return cv.bitwiseNOT(m);
}

Future<double> computeCotl(cv.Mat gray, cv.Mat sat, cv.Mat inLineMask) async {
  final rPx = _cmToPxOnA4ByWidth(inLineMask, cm: 3.0);
  final k = 2 * rPx + 1;
  final ringKernel = cv.getStructuringElement(2, (k, k));
  final cv.Mat outer = cv.dilate(inLineMask, ringKernel);

  final cv.Mat invInside = cv.threshold(inLineMask, 127.0, 255.0, 1).$2;

  cv.Mat band = _maskAnd(outer, invInside);

  final shrinkK = cv.getStructuringElement(2, (3, 3));
  band = cv.erode(band, shrinkK);

  final cv.Mat sGt25 = cv
      .threshold(sat, _S_COLORED_MIN.toDouble(), 255.0, 0)
      .$2;
  final cv.Mat vGt70 = cv
      .threshold(gray, _V_BRIGHT_MIN.toDouble(), 255.0, 0)
      .$2;

  final cv.Mat coloredBySat = _maskAnd(sGt25, vGt70);

  final cv.Mat vLt110 = cv.threshold(gray, _V_DARK_MAX.toDouble(), 255.0, 1).$2;

  final cv.Mat coloredPre = _maskOr(coloredBySat, vLt110);

  final cv.Mat sLt12 = cv.threshold(sat, _S_NEARWHITE.toDouble(), 255.0, 1).$2;
  final cv.Mat vGt235 = cv
      .threshold(gray, _V_NEARWHITE.toDouble(), 255.0, 0)
      .$2;
  final cv.Mat nearWhite = _maskAnd(sLt12, vGt235);

  final cv.Mat keepMask = maskNot(nearWhite);
  final cv.Mat colored = _maskAnd(coloredPre, keepMask);

  final openK = cv.getStructuringElement(0, (3, 3));
  final cv.Mat coloredClean = cv.morphologyEx(colored, 1, openK);

  final cv.Mat coloredNear = _maskAnd(coloredClean, band);

  final int bandArea = cv.countNonZero(band);
  if (bandArea <= 0) return 0.0;

  final int coloredNearCount = cv.countNonZero(coloredNear);
  final ratio = coloredNearCount / bandArea;
  return ratio.clamp(0.0, 1.0);
}
