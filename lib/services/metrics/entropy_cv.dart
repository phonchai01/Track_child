import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../image/opencv_utils.dart' as utils;

class EntropyCV {
  /// entropy normalized [0,1] จาก Gray 256 bins
  static double computeNormalized(cv.Mat bgr) {
    // 1) แปลงเป็น grayscale
    final gray = utils.toGray(bgr);

    // 2) สร้าง histogram
    final hist = cv.calcHist(
      gray as cv.VecMat, // ภาพ grayscale
      [0] as cv.VecI32, // ใช้ช่องที่ 0
      cv.Mat.empty(), // ไม่มี mask
      [256] as cv.VecI32, // 256 bins
      [0, 256] as cv.VecF32, // ค่า intensity 0–255
    );

    // 3) คำนวณ entropy
    final total = gray.rows * gray.cols;
    double ent = 0.0;

    for (int i = 0; i < 256; i++) {
      final p = hist.atFloat(i, 0) / total;
      if (p > 0) ent -= p * (math.log(p) / math.ln2);
    }

    // normalize ด้วย log2(256)=8
    return ent / 8.0;
  }
}

extension on cv.Mat {
  atFloat(int i, int j) {}
}
