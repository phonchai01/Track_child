// lib/services/metrics/blank_cv.dart
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// ---- พารามิเตอร์ปรับแต่ง ----
/// S ขั้นต่ำที่ถือว่า "มีสีจริง"
const int _kSatThr = 38;

/// ความต่างที่อนุโลมสำหรับพาสเทลเทียบกับ "ขาวโลคัล"
const int _kPastelAllowance = 12;

/// เกณฑ์ V (จาก gray) ที่ถือว่า "ดำมาก" ⇒ นับเป็นการทาแม้ S จะต่ำ
/// ลองปรับ 100–140 ตามวัสดุที่ใช้ (ดินสอ/ปากกา)
const int _kDarkInkMax = 130;

/// เคอร์เนลสำหรับ morphology
const int _kOpenKernel = 3;
const int _kEdgeDilate = 1;
const int _kErodeMaskPx = 1;

cv.Mat _rectK(int k) => cv.getStructuringElement(0 /*MORPH_RECT*/, (k, k));
cv.Mat _ellipK(int k) => cv.getStructuringElement(2 /*MORPH_ELLIPSE*/, (k, k));

/// คำนวณสัดส่วน "พื้นที่ยังว่าง" ภายในเส้น (0..1)
/// รวม 3 แหล่งที่นับเป็นการทา: (1) S สูง, (2) พาสเทลเข้มกว่าขาวโลคัล,
/// (3) สีดำ/หมึก/ดินสอที่มืดมาก (V ต่ำ)
Future<double> computeBlank(cv.Mat gray, cv.Mat sat, cv.Mat inLineMask) async {
  // เบลอเล็กน้อยกัน noise
  final cv.Mat grayMed = cv.medianBlur(gray, 3);

  // 1) ภายในเส้นแบบปลอดภัย (ร่นเข้าเล็กน้อยกันติดเส้น)
  final cv.Mat maskSafe = cv.erode(inLineMask, _ellipK(_kErodeMaskPx));
  final int area = cv.countNonZero(maskSafe);
  if (area <= 0) return 1.0;

  // 2) สีจริงจาก S
  final cv.Mat satMask = cv
      .threshold(sat, _kSatThr.toDouble(), 255.0, 0 /*BINARY*/)
      .$2;

  // 3) พาสเทลเทียบ "ขาวโลคัล"
  final cv.Mat localWhite = cv.gaussianBlur(grayMed, (31, 31), 0);
  final cv.Mat constVal = cv.Mat.zeros(
    localWhite.rows,
    localWhite.cols,
    localWhite.type,
  )..setTo(cv.Scalar.all(_kPastelAllowance.toDouble()));
  final cv.Mat pastelAllow = cv.subtract(localWhite, constVal);
  final cv.Mat pastelMaskLocal = cv
      .threshold(
        cv.max(
          pastelAllow,
          cv.Mat.zeros(pastelAllow.rows, pastelAllow.cols, pastelAllow.type),
        ),
        0.0,
        255.0,
        1 /*BINARY_INV: gray < (localWhite-allow) → 255*/,
      )
      .$2;

  // 4) ดำมาก (ดินสอ/หมึก) – ใช้ V ต่ำจาก gray
  final cv.Mat veryDark = cv
      .threshold(grayMed, _kDarkInkMax.toDouble(), 255.0, 1 /*BINARY_INV*/)
      .$2;

  // 5) รวมผู้สมัครว่า "ทาแล้ว"
  final cv.Mat coloredCandidate = cv.max(
    cv.max(satMask, pastelMaskLocal),
    veryDark,
  );

  // 6) ลบเส้นขอบด้วย Canny + Dilate แล้วกลับขั้วเป็น mask keep
  final cv.Mat edges = cv.canny(grayMed, 60, 120);
  final cv.Mat edgesDil = cv.dilate(edges, _rectK(_kEdgeDilate));
  final cv.Mat edgesInv = cv
      .threshold(edgesDil, 0.0, 255.0, 1 /*BINARY_INV*/)
      .$2;

  // กรองเส้นออก
  final cv.Mat coloredNoEdge = cv.Mat.zeros(
    coloredCandidate.rows,
    coloredCandidate.cols,
    coloredCandidate.type,
  );
  coloredCandidate.copyTo(coloredNoEdge, mask: edgesInv);

  // 7) จำกัดเฉพาะภายในเส้น และเปิดรูเพื่อล้าง noise จุดเล็ก ๆ
  final cv.Mat coloredIn = cv.Mat.zeros(
    coloredNoEdge.rows,
    coloredNoEdge.cols,
    coloredNoEdge.type,
  );
  coloredNoEdge.copyTo(coloredIn, mask: maskSafe);

  final cv.Mat cleaned = cv.morphologyEx(
    coloredIn,
    1 /*MORPH_OPEN*/,
    _rectK(_kOpenKernel),
  );

  // 8) สัดส่วนพื้นที่ที่ถูกทา → Blank = 1 - paintedRatio
  final int coloredCount = cv.countNonZero(cleaned);
  final double paintedRatio = (coloredCount.toDouble() / area.toDouble()).clamp(
    0.0,
    1.0,
  );
  return (1.0 - paintedRatio).clamp(0.0, 1.0);
}
