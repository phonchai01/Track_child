import 'package:opencv_dart/opencv_dart.dart' as cv;

/// สร้าง mask พื้นที่ "ภายในเส้น" จากเทมเพลตขาว-ดำที่เป็น "เส้นดำบนพื้นขาว"
/// ผลลัพธ์: 255 = ภายในเส้นจริง, 0 = อื่น ๆ (รวมเส้น)
cv.Mat buildInsideMaskFromTemplateGray(cv.Mat templateGray) {
  // 1) ไบนาไรซ์เส้น (เส้นดำ -> 255)
  final cv.Mat lineBin = cv
      .threshold(templateGray, 200.0, 255.0, cv.THRESH_BINARY_INV)
      .$2;

  // 2) ทำเส้นให้หนาขึ้นเล็กน้อย กัน Anti-Aliasing หลุด
  final cv.Mat thick = cv.dilate(
    lineBin,
    cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3)),
  );

  // 3) เตรียมภาพสำหรับ floodFill: เส้น = 0, ที่เหลือ = 255
  final cv.Mat canvas = cv.bitwiseNOT(thick);

  // 4) floodFill จากมุมซ้ายบน (0,0) ระบาย “นอกเส้น” เป็นค่า 128
  //    (opencv_dart ใช้รูปแบบ floodFill(image, seedPoint, newVal))
  cv.floodFill(canvas, cv.Point(0, 0), cv.Scalar.all(128));

  // 5) ภายในเส้น = ส่วนที่ไม่ใช่ 128 และไม่ใช่ “เส้น”
  //    แนวทางง่าย: เอา canvas ที่ถูกระบาย 128 มาทำ threshold (>=128 เป็นนอกเส้น)
  final cv.Mat outside = cv
      .threshold(canvas, 127.0, 255.0, cv.THRESH_BINARY)
      .$2; // 128/255 = outside
  final cv.Mat insideRough = cv.bitwiseNOT(
    outside,
  ); // คร่าว ๆ = ภายใน (รวมเส้น)

  // 6) ลบเส้นออกจากภายใน
  final cv.Mat insideNoLine = cv.subtract(
    insideRough,
    thick, // เส้นที่เราทำหนาไว้
  );

  // 7) เปิดหน้ากากให้ขอบสะอาด (ล้าง noise จุดเล็ก ๆ)
  final cv.Mat insideClean = cv.morphologyEx(
    insideNoLine,
    cv.MORPH_OPEN,
    cv.getStructuringElement(cv.MORPH_RECT, (3, 3)),
  );

  return insideClean;
}

/// helper: mask ลบเส้นขอบเพิ่มอีกชั้น (กัน AA ติดการนับ)
cv.Mat shrinkInsideForSafeCount(cv.Mat inside, {int px = 1}) {
  final k = px.clamp(0, 5);
  if (k == 0) return inside;
  return cv.erode(inside, cv.getStructuringElement(cv.MORPH_ELLIPSE, (k, k)));
}

/// (ถ้าใช้ไฟล์ mask สำเร็จรูป) ตรวจและกลับสีให้อยู่ในรูปแบบ 255=ภายใน
cv.Mat ensureWhiteIsInside(cv.Mat mask) {
  final total = mask.rows * mask.cols;
  final white = cv.countNonZero(mask);
  if (white < total / 2) {
    return cv.bitwiseNOT(mask);
  }
  return mask;
}
