// lib/services/image/opencv_utils.dart
import 'dart:typed_data';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Decode อะไรก็ได้ -> Mat (BGR)
/// รองรับ: Uint8List, List<int>, และ cv.Mat (ถ้าเป็น Mat อยู่แล้วคืนเลย)
cv.Mat imdecode(dynamic src, {bool color = true}) {
  if (src is cv.Mat) return src;

  late Uint8List bytes;
  if (src is Uint8List) {
    bytes = src;
  } else if (src is List<int>) {
    bytes = Uint8List.fromList(src);
  } else {
    throw Exception(
      'imdecode: รองรับ Uint8List/List<int>/Mat เท่านั้น แต่ได้ ${src.runtimeType}',
    );
  }

  // ใน opencv_dart 1.4.3 ใช้ imdecode() กับ Uint8List ได้เลย
  final flag = color ? 1 : 0; // 1 = IMREAD_COLOR, 0 = IMREAD_GRAYSCALE
  return cv.imdecode(bytes, flag);
}

/// Mat -> PNG bytes (สำหรับ Image.memory / ส่งข้ามหน้า)
Uint8List imencodePng(cv.Mat mat) {
  final res = cv.imencode('.png', mat); // (bool, Uint8List)
  return Uint8List.fromList(res.$2.toList());
}

/// สี BGR -> Gray   (6 = COLOR_BGR2GRAY)
cv.Mat toGray(cv.Mat bgr) => cv.cvtColor(bgr, 6);

/// Threshold Binary 0/255  (0 = THRESH_BINARY)
cv.Mat thresholdBinary(cv.Mat gray, num t) =>
    cv.threshold(gray, t.toDouble(), 255.0, 0).$2;

/// Resize (width, height)
cv.Mat resize(cv.Mat src, {required int width, required int height}) =>
    cv.resize(src, (width, height));

/// Apply mask: เก็บเฉพาะบริเวณที่ mask>0, นอกนั้นให้ขาว
/// - maskGray ต้องเป็น single-channel (0/255). ถ้าไม่ชัวร์ เรา binarize ให้
cv.Mat applyMask(cv.Mat srcBgr, cv.Mat maskGray) {
  // 1) ให้แน่ใจว่า mask เป็น 0/255
  final cv.Mat maskBin = thresholdBinary(maskGray, 127);

  // 2) เตรียมภาพผลลัพธ์พื้นหลังขาว
  final cv.Mat out = cv.Mat.zeros(srcBgr.rows, srcBgr.cols, srcBgr.type);
  out.setTo(cv.Scalar(255, 255, 255));

  // 3) วาง src เฉพาะจุดที่ mask>0 ลงบน out
  //    Mat.copyTo(dst, mask) จะคัดลอกเฉพาะพิกเซลที่ mask != 0
  srcBgr.copyTo(out, mask: maskBin);

  return out;
}

/// Threshold Binary 0/255
/// คืนค่า (thresholdValue, Mat)
(double, cv.Mat) binarize(cv.Mat gray, {int thresh = 128}) {
  final result = cv.threshold(gray, thresh.toDouble(), 255.0, 0);
  return result;
}
