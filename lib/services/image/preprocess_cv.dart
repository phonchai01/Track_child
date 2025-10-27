import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'opencv_utils.dart';

class PreprocessCV {
  /// อ่านภาพจาก bytes แล้ว center-crop เป็นสี่เหลี่ยมจัตุรัส + resize
  static cv.Mat centerCropResize(Uint8List bytes, {int target = 512}) {
    final bgr = imdecode(bytes); // อ่านเป็น BGR
    final h = bgr.rows, w = bgr.cols;
    final side = h < w ? h : w;
    final x0 = (w - side) ~/ 2;
    final y0 = (h - side) ~/ 2;

    // ✅ crop แบบใช้ region()
    final rect = cv.Rect(x0, y0, side, side);
    final roi = bgr.region(rect);

    final out = resize(roi, width: target, height: target);
    return out;
  }

  /// perspective stub (ถ้าจะหามุมจริง: findContours + approxPolyDP)
  static cv.Mat perspectiveStub(Uint8List bytes, {int target = 512}) {
    return centerCropResize(bytes, target: target);
  }
}
