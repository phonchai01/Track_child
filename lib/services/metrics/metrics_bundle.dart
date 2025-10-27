import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../image/opencv_utils.dart';
import 'blank_cv.dart' as blankcv;
import 'cotl_cv.dart' as cotlcv;

const double kWhiteThr = 250.0;
const double kBlackThr = 40.0;
const int kSatThr = 30;

class MetricsResult {
  final double h, dstar, blank, cotl;
  MetricsResult({
    required this.h,
    required this.dstar,
    required this.blank,
    required this.cotl,
  });
}

class MetricsBundle {
  Future<MetricsResult> computeAll({
    required Uint8List imageBytes,
    required Uint8List maskBytes,
  }) async {
    final cv.Mat img = imdecode(imageBytes);
    cv.Mat msk = imdecode(maskBytes);

    if (msk.rows != img.rows || msk.cols != img.cols) {
      msk = cv.resize(msk, (img.cols, img.rows));
    }

    final cv.Mat mskGray = cv.cvtColor(msk, 6);
    final cv.Mat mskBin = cv.threshold(mskGray, 127.0, 255.0, 0).$2;

    final cv.Mat gray = cv.cvtColor(img, 6);
    final cv.Mat hsv = cv.cvtColor(img, 40);
    final cv.Mat sat = cv.extractChannel(hsv, 1);

    final double H = await _computeEntropy(gray, mskBin);
    final double Dstar = await _computeComplexity(gray, mskBin);

    final double Blank = (await blankcv.computeBlank(gray, sat, mskBin));
    final double Cotl = await cotlcv.computeCotl(gray, sat, mskBin);

    return MetricsResult(h: H, dstar: Dstar, blank: Blank, cotl: Cotl);
  }

  Future<double> _computeEntropy(cv.Mat gray, cv.Mat mask) async {
    final (_, stddevScalar) = cv.meanStdDev(gray, mask: mask);
    final double stddev = stddevScalar.val[0];
    return (stddev / 64.0).clamp(0.0, 1.0);
  }

  Future<double> _computeComplexity(cv.Mat gray, cv.Mat mask) async {
    final cv.Mat edges = cv.canny(gray, 50, 150);
    final cv.Mat edgesIn = cv.Mat.zeros(edges.rows, edges.cols, edges.type);
    edges.copyTo(edgesIn, mask: mask);
    final int area = cv.countNonZero(mask);
    if (area <= 0) return 0.0;
    final int edgeCount = cv.countNonZero(edgesIn);
    return (edgeCount / area).clamp(0.0, 1.0);
  }
}
