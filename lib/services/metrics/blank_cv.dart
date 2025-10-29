import 'package:opencv_dart/opencv_dart.dart' as cv;

/// ---------- โปรไฟล์เกณฑ์ (ค่าเริ่มต้นแบบยืดหยุ่น) ----------
class _BlankParams {
  final int satThr;          // S ขั้นต่ำที่ถือว่า "มีสี"
  final int pastelAllowance; // ส่วนลดเทียบ white-local (ยิ่งมากยิ่งรับสีอ่อน)
  final int darkInkMax;      // เกณฑ์ V (gray) ที่นับว่า "ดำมาก" => ทาแล้ว
  final int openKernel;
  final int edgeDilate;
  final int erodeMaskPx;
  const _BlankParams({
    required this.satThr,
    required this.pastelAllowance,
    required this.darkInkMax,
    this.openKernel = 3,
    this.edgeDilate = 1,
    this.erodeMaskPx = 1,
  });
}

enum BlankMode { auto, color, pencil }

// โปรไฟล์พื้นฐาน
const _colorParams  = _BlankParams(satThr: 35, pastelAllowance: 15, darkInkMax: 140);
const _pencilParams = _BlankParams(satThr: 22, pastelAllowance: 25, darkInkMax: 170);

cv.Mat _rectK(int k)  => cv.getStructuringElement(0, (k, k));
cv.Mat _ellipK(int k) => cv.getStructuringElement(2, (k, k));

/// เลือกโปรไฟล์อัตโนมัติจากสถิติ S/V ภายในมาสก์
_BlankParams _autoTune(cv.Mat grayMed, cv.Mat sat, cv.Mat maskSafe) {
  // สุ่มตัวอย่างหยาบเพื่อลดเวลา
  final cv.Mat satMasked  = cv.Mat.zeros(sat.rows, sat.cols, sat.type)..setTo(cv.Scalar.all(0));
  final cv.Mat grayMasked = cv.Mat.zeros(grayMed.rows, grayMed.cols, grayMed.type)..setTo(cv.Scalar.all(255));
  sat.copyTo(satMasked,  mask: maskSafe);
  grayMed.copyTo(grayMasked, mask: maskSafe);

  // สถิติง่าย ๆ: ค่ามัธยฐานโดย approx ด้วย blur แล้วหาค่าเฉลี่ย
  final satMed      = cv.mean(cv.medianBlur(satMasked, 5)).v0;
  final grayMedMean = cv.mean(grayMasked).v0;


  // สัดส่วน "มืดจัด" ภายใน (บอกแนวดินสอ)
  final vDark = cv.threshold(grayMed, 160.0, 255.0, 1 /*INV*/).$2; // V<160
  final vDarkIn = cv.Mat.zeros(vDark.rows, vDark.cols, vDark.type);
  vDark.copyTo(vDarkIn, mask: maskSafe);
  final darkRatio = cv.countNonZero(vDarkIn) / cv.countNonZero(maskSafe).clamp(1, 1<<30);

  // เงื่อนไขง่าย ๆ:
  // - S ต่ำ (≤20~25) และมืดเยอะ หรือ V โดยรวมมืด → pencil
  // - อย่างอื่น → color
  final isPencil = (satMed <= 24.0 && darkRatio >= 0.12) || (grayMedMean <= 155.0);
  return isPencil ? _pencilParams : _colorParams;
}
/// คำนวณสัดส่วน "พื้นที่ยังว่าง" ภายในเส้น (0..1)
/// รวม 3 แหล่งที่นับเป็นการทา: (1) S สูง, (2) พาสเทลเข้มกว่าขาวโลคัล,
/// (3) สีดำ/หมึก/ดินสอที่มืดมาก (V ต่ำ) 
Future<double> computeBlank(
  cv.Mat gray,
  cv.Mat sat,
  cv.Mat inLineMask, {
  BlankMode mode = BlankMode.auto,   // ✅ เพิ่มโหมด
}) async {
  final cv.Mat grayMed = cv.medianBlur(gray, 3);

  // 1) ภายในเส้นแบบปลอดภัย
  final cv.Mat maskSafe = cv.erode(inLineMask, _ellipK(_colorParams.erodeMaskPx));
  final int area = cv.countNonZero(maskSafe);
  if (area <= 0) return 1.0;

  // 2) เลือกพารามิเตอร์ตามโหมด
  final _BlankParams p = switch (mode) {
    BlankMode.color  => _colorParams,
    BlankMode.pencil => _pencilParams,
    BlankMode.auto   => _autoTune(grayMed, sat, maskSafe),
  };

  // 3) สีจริงจาก S
  final cv.Mat satMask = cv.threshold(sat, p.satThr.toDouble(), 255.0, 0).$2;

  // 4) พาสเทลเทียบ "ขาวโลคัล"
  final cv.Mat localWhite = cv.gaussianBlur(grayMed, (31, 31), 0);
  final cv.Mat constVal = cv.Mat.zeros(localWhite.rows, localWhite.cols, localWhite.type)
    ..setTo(cv.Scalar.all(p.pastelAllowance.toDouble()));
  final cv.Mat pastelAllow = cv.subtract(localWhite, constVal);
  final cv.Mat pastelMaskLocal = cv.threshold(
    cv.max(pastelAllow, cv.Mat.zeros(pastelAllow.rows, pastelAllow.cols, pastelAllow.type)),
    0.0, 255.0, 1 /*INV: gray < (localWhite-allow) */,
  ).$2;

  // 5) ดำมาก (ดินสอ/หมึก)
  final cv.Mat veryDark = cv.threshold(grayMed, p.darkInkMax.toDouble(), 255.0, 1 /*INV*/).$2;

  // 6) ลบเส้นขอบเฉพาะส่วน "สี/พาสเทล" เพื่อไม่ลบดินสอเข้มทิ้ง
  final cv.Mat edges = cv.canny(grayMed, 60, 120);
  final cv.Mat edgesDil = cv.dilate(edges, _rectK(p.edgeDilate));
  final cv.Mat edgesInv = cv.threshold(edgesDil, 0.0, 255.0, 1 /*INV*/).$2;

  final cv.Mat colorOrPastel = cv.max(satMask, pastelMaskLocal);
  final cv.Mat colorOrPastel_NoEdge = cv.Mat.zeros(colorOrPastel.rows, colorOrPastel.cols, colorOrPastel.type);
  colorOrPastel.copyTo(colorOrPastel_NoEdge, mask: edgesInv);

  // 7) รวมกับ veryDark (ไม่ลบ edge)
  final cv.Mat coloredNoEdge = cv.max(colorOrPastel_NoEdge, veryDark);

  // 8) จำกัดเฉพาะภายใน + ทำความสะอาด
  final cv.Mat coloredIn = cv.Mat.zeros(coloredNoEdge.rows, coloredNoEdge.cols, coloredNoEdge.type);
  coloredNoEdge.copyTo(coloredIn, mask: maskSafe);
  final cv.Mat cleaned = cv.morphologyEx(coloredIn, 1 /*OPEN*/, _rectK(p.openKernel));

  final int coloredCount = cv.countNonZero(cleaned);
  final double paintedRatio = (coloredCount.toDouble() / area.toDouble()).clamp(0.0, 1.0);
  return (1.0 - paintedRatio).clamp(0.0, 1.0);
}
