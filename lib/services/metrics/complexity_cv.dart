import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../image/opencv_utils.dart';

class ComplexityCV {
  static double edgeDensity(cv.Mat bgr) {
    final gray = toGray(bgr);
    final edges = cv.canny(gray, 100, 200);
    final count = cv.countNonZero(edges);
    return count / (bgr.rows * bgr.cols);
  }
}
