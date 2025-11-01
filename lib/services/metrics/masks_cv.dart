// lib/services/metrics/masks_cv.dart
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// สร้าง mask "ภายในเส้น" จากเทมเพลตเส้นดำบนพื้นขาว (หรือพื้นดำก็ได้)
/// ผลลัพธ์ 8U: 255=ภายในจริง, 0=อื่น ๆ (รวมเส้น)
cv.Mat buildInsideMaskFromTemplateGray(
  cv.Mat templateGray, {
  int otsuBias = 0,
}) {
  final g = (templateGray.channels > 1)
      ? cv.cvtColor(templateGray, cv.COLOR_BGR2GRAY)
      : templateGray.clone();

  // แยกสองฝั่งด้วย OTSU (+bias ได้)
  final otsu =
      cv.threshold(g, 0.0, 255.0, cv.THRESH_BINARY | cv.THRESH_OTSU).$1 +
      otsuBias;

  final binLight = cv.threshold(g, otsu, 255.0, cv.THRESH_BINARY).$2;
  final binDark = cv.threshold(g, otsu, 255.0, cv.THRESH_BINARY_INV).$2;

  // เลือกฝั่งที่ “เล็กกว่า” เป็นด้านใน (เช่น ปลาขาวพื้นดำ ⇒ binLight)
  final nLight = cv.countNonZero(binLight);
  final nDark = cv.countNonZero(binDark);
  final inside = (nLight <= nDark) ? binLight : binDark;

  // กัน anti-alias: ทำเส้นให้หนาขึ้นเล็กน้อยแล้ว floodFill
  final thick = cv.dilate(
    cv.bitwiseNOT(inside), // กลับสีชั่วคราวเพื่อทำให้เส้นชัด
    cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3)),
  );
  final canvas = cv.bitwiseNOT(thick);

  // floodFill ระบายพื้นที่นอกเส้นเป็น 128 (opencv_dart: image, seedPoint, newVal)
  cv.floodFill(canvas, cv.Point(0, 0), cv.Scalar.all(128));

  // outside = 128/255, inside = not outside
  final outside = cv.threshold(canvas, 127.0, 255.0, cv.THRESH_BINARY).$2;
  final insideRough = cv.bitwiseNOT(outside);

  // ลบเส้นออก (ใช้ thick เดิมช่วยกันคราบเส้น)
  final insideNoLine = cv.subtract(insideRough, thick);

  // เปิดหน้ากากให้ขอบสะอาด
  final insideClean = cv.morphologyEx(
    insideNoLine,
    cv.MORPH_OPEN,
    cv.getStructuringElement(cv.MORPH_RECT, (3, 3)),
  );

  final res = cv.convertScaleAbs(insideClean);
  print(
    '🧩 buildInsideMask: insidePx=${cv.countNonZero(res)} '
    'size=${res.cols}x${res.rows}',
  );
  return res;
}

/// หด mask ภายในอีกชั้น (กันหน้าต่าง 2×2 ไปชนเส้น) — ใช้ค่าน้อย ๆ 1–4 px
cv.Mat shrinkInsideForSafeCount(cv.Mat inside, {int px = 2}) {
  final k = px.clamp(0, 8);
  if (k == 0) return inside;
  final ker = cv.getStructuringElement(cv.MORPH_ELLIPSE, (k, k));
  final er = cv.erode(inside, ker);
  print('🧩 shrinkInside: px=$px -> insidePx=${cv.countNonZero(er)}');
  return er;
}

/// ถ้า mask สำเร็จรูปกลับสีอยู่ ให้กลับให้เป็น 255=ภายใน
cv.Mat ensureWhiteIsInside(cv.Mat mask) {
  final total = mask.rows * mask.cols;
  final white = cv.countNonZero(mask);
  if (white < total / 2) {
    final r = cv.bitwiseNOT(mask);
    print('🧩 ensureWhiteIsInside: inverted -> insidePx=${cv.countNonZero(r)}');
    return r;
  }
  print('🧩 ensureWhiteIsInside: ok -> insidePx=${white}');
  return mask;
}
