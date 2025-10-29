// lib/services/metrics/entropy_cv.dart
import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;

class EntropyCV {
  /// Shannon entropy normalized [0,1] จาก Gray 8-bit (256 bins)
  static double computeNormalized(cv.Mat bgr, {cv.Mat? mask}) {
    final cv.Mat gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);

    // อ่านข้อมูลพิกเซล (Uint8List) ออกมาตรงๆ
    final data = gray.data; // Uint8List ใน opencv_dart

    // นับ histogram ด้วยตัวเอง (เสถียรกว่าใช้ calcHist ของ lib)
    final List<int> hist = List<int>.filled(256, 0);
    if (mask == null) {
      for (int i = 0; i < data.length; i++) hist[data[i]]++;
    } else {
      final m = mask.data;
      for (int i = 0; i < data.length; i++) {
        if (m[i] != 0) hist[data[i]]++;
      }
    }

    final int total = hist.fold(0, (p, v) => p + v);
    if (total == 0) return 0.0;

    double ent = 0.0;
    for (int i = 0; i < 256; i++) {
      if (hist[i] == 0) continue;
      final double p = hist[i] / total;
      ent -= p * (math.log(p) / math.ln2);
    }
    // normalize ด้วย log2(256) = 8
    return (ent / 8.0).clamp(0.0, 1.0);
  }
}
