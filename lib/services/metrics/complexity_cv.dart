// lib/services/metrics/complexity_cv.dart
import 'package:opencv_dart/opencv_dart.dart' as cv;

class ComplexityCV {
  /// Edge density (0..1) จาก Canny
  static double edgeDensity(cv.Mat bgr, {cv.Mat? mask}) {
    final cv.Mat gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
    final cv.Mat edges = cv.canny(gray, 100, 200);

    if (mask != null) {
      final cv.Mat edgesIn = cv.Mat.zeros(edges.rows, edges.cols, edges.type);
      edges.copyTo(edgesIn, mask: mask);
      final int cnt = cv.countNonZero(edgesIn);
      final int area = cv.countNonZero(mask);
      if (area <= 0) return 0.0;
      return (cnt / area).clamp(0.0, 1.0);
    } else {
      final int cnt = cv.countNonZero(edges);
      return (cnt / (bgr.rows * bgr.cols)).clamp(0.0, 1.0);
    }
  }
}
