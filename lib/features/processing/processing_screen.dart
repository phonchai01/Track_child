// lib/features/processing/processing_screen.dart
import 'dart:async';
// import 'dart:typed_data';
import 'dart:typed_data' as td;
import 'dart:math' as math;

import 'package:flutter/material.dart';
// import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/services.dart' as fs;
import 'package:image_picker/image_picker.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

// ใช้ package:image สำหรับ preprocess/แปลง bytes (แบบ 1)
import 'package:image/image.dart' as img;
import '../../services/image/warp_crop.dart';

// Z-score / Metrics / Masks (เหมือนเดิม ไม่แก้ที่ไฟล์อื่น)
import '../../services/metrics/zscore_service.dart';
import '../../services/metrics/masks_cv.dart'
    show shrinkInsideForSafeCount, ensureWhiteIsInside;

import '../../services/metrics/blank_cv.dart';
import '../../services/metrics/cotl_cv.dart';
import '../../services/metrics/entropy_cv.dart';
import '../../services/metrics/complexity_cv.dart';

// AI segmentation (มี guard เมื่อไม่มีโมเดล) — แบบ 1
import '../../services/ai/paintseg_infer.dart';

// ประวัติ
import '../../data/models/history_record.dart';
import '../../data/repositories/history_repo.dart';

class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({
    super.key,
    this.imageBytes,
    this.imageAssetPath,
    required this.maskAssetPath,
    this.templateName,
    this.imageName,
  });

  // final Uint8List? imageBytes;
  final td.Uint8List? imageBytes;
  final String? imageAssetPath;
  final String maskAssetPath; // e.g. assets/masks/fish_mask.png (ขาว=ด้านใน)
  final String? templateName; // label แสดงผล
  final String? imageName;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  // ======= Tunables (รวมของทั้งสองแบบ) =======
  static const int _DX = 2, _DY = 2; // ขนาดหน้าต่าง Bandt–Pompe (ถ้า lib รองรับ)
  static const int _SHRINK_EXTRA = 22; // ระยะเพิ่มจากขอบสำหรับ safe mask
  static const double _EDGE_RATIO_EPS = 0.0005; // <0.05% เส้นขอบ ถือว่าเงียบมาก
  static const double _BLANK_ONE_EPS = 0.01;  // เหลือว่าง >= 99.9% → ปัดเป็น 1.0


  // ---- Zero-guard tunables ----
  static const int _HC_EXTRA_MARGIN_PX = 20; // ขยับลึกเข้าไปอีกสำหรับ H/C
  // หมายเหตุ: ไม่ใช้ std(gray) แล้ว แต่คงค่าเดิมไว้เผื่อ debug/ปรับภายหลัง
  static const double _STD_GRAY_EPS = 1.8;
  static const int _SAT_MIN_COLORED = 26; // S ต่ำกว่า → ไม่ถือว่า "สีจริง"
  static const int _V_NEARWHITE = 240; // Gray >= นี้ → ใกล้ขาว
  static const double _COLORED_RATIO_EPS = 0.002; // <0.2% สี → ยังไม่ระบาย

  String? _error;

  // preview
  // Uint8List? _previewBytes;
  td.Uint8List? _previewBytes;
  int? _imgW, _imgH;

  // metrics (raw)
  double? _blank, _cotl, _entropy, _complexity;

  // Index (raw) + ระดับ
  double? _indexRaw;
  String? _level;

  // ช่วงอ้างอิงของ Index(raw)
  double? _lowCut, _highCut, _mu, _sigma;

  // profile/template
  late String _classKey; // 'Fish' | 'Pencil' | 'IceCream'
  late int _age; // 4 หรือ 5
  String _profileKey = ''; // owner ของประวัติ

  bool _started = false;
  late Future<void> _svcWarmup;

  // ===== AI segmentation (แบบ 1) =====
  late Future<void> _aiWarmup;
  bool _useAiMask = false; // toggle โดยผู้ใช้
  bool _aiMaskUsed = false; // ใช้งานจริงหลังสำเร็จ

  @override
  void initState() {
    super.initState();
    _svcWarmup = ZScoreService.instance.ensureLoaded();
    _aiWarmup = PaintSeg.instance.ensureLoaded(); // set available=true เมื่อมีไฟล์
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started) return;
      _started = true;
      _run(); // เริ่มประมวลผลครั้งแรก
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final profile = (args?['profile'] as Map?)?.cast<String, dynamic>();

    _profileKey =
        (profile?['key'] ??
                profile?['id'] ??
                profile?['profileKey'] ??
                profile?['name'] ??
                '')
            .toString();

    final rawTemplate =
        (args?['template'] ?? args?['templateKey'] ?? widget.templateName ?? '')
            .toString();
    _classKey = _resolveClassKey(rawTemplate);

    final dynamic ageRaw = profile?['age'];
    _age = (ageRaw is int) ? ageRaw : int.tryParse('${ageRaw ?? '0'}') ?? 0;

    debugPrint('>> args -> classKey=$_classKey age=$_age profileKey=$_profileKey');
  }

  // ---------- Helpers ----------
  String _resolveClassKey(String raw) {
    switch (raw) {
      case 'ปลา':
      case 'fish':
      case 'Fish':
        return 'Fish';
      case 'ดินสอ':
      case 'pencil':
      case 'Pencil':
        return 'Pencil';
      case 'ไอศกรีม':
      case 'icecream':
      case 'IceCream':
      case 'ice_cream':
        return 'IceCream';
      default:
        return raw;
    }
  }

  String _templateLabelFromKey(String key) => switch (key) {
        'Fish' => 'ปลา',
        'Pencil' => 'ดินสอ',
        'IceCream' => 'ไอศกรีม',
        _ => key,
      };

  // Future<cv.Mat> _decodeBgr(Uint8List bytes) async =>
  Future<cv.Mat> _decodeBgr(td.Uint8List bytes) async =>
      cv.imdecode(bytes, cv.IMREAD_COLOR);

  // Uint8List _matToPng(cv.Mat m) =>
  //     Uint8List.fromList(cv.imencode('.png', m).$2.toList());
  td.Uint8List _matToPng(cv.Mat m) =>
    td.Uint8List.fromList(cv.imencode('.png', m).$2.toList());

  // Future<Uint8List> _loadAssetBytes(String path) async {
  Future<td.Uint8List> _loadAssetBytes(String path) async {
    // final b = await rootBundle.load(path);
    final b = await fs.rootBundle.load(path);
    return b.buffer.asUint8List();
  }

  cv.Mat _extractS(cv.Mat bgr) {
    final hsv = cv.cvtColor(bgr, cv.COLOR_BGR2HSV);
    try {
      return cv.extractChannel(hsv, 1);
    } catch (_) {
      return cv.split(hsv)[1];
    }
  }

  Future<cv.Mat> _loadBinaryMask(String path) async {
    final bytes = await _loadAssetBytes(path);
    cv.Mat m = await _decodeBgr(bytes);
    if (m.channels > 1) m = cv.cvtColor(m, cv.COLOR_BGR2GRAY);
    return cv.threshold(m, 127.0, 255.0, cv.THRESH_BINARY).$2;
  }

  // ---------- Preprocess (center-crop + resize + bakeOrientation) — แบบ 1 ----------
  // Uint8List _preprocessBytes(Uint8List origin, {int target = 900}) {
  td.Uint8List _preprocessBytes(td.Uint8List origin, {int target = 900}) {
    final im = img.decodeImage(origin);
    if (im == null) return origin;
    final oriented = img.bakeOrientation(im);
    final prepped = WarpCrop.centerCropResize(oriented, target: target);
    _imgW = prepped.width;
    _imgH = prepped.height;
    return td.Uint8List.fromList(img.encodePng(prepped));
  }

  // แปลง PNG preview -> RGBA bytes ให้ PaintSeg (แบบ 1)
  // Uint8List _pngToRgba(Uint8List png) {
  td.Uint8List _pngToRgba(td.Uint8List png) {
    final im = img.decodeImage(png);
    if (im == null) return png;
    final rgba = im.getBytes(order: img.ChannelOrder.rgba);
    return td.Uint8List.fromList(rgba);
  }

  // prob-map (0..1) -> mask_out (ขาว=นอก, ดำ=ใน), scale เท่ารูป (แบบ 1)
  Future<cv.Mat> _probToMaskOut(
    List<List<double>> prob,
    int outW,
    int outH, {
    double thr = 0.5,
    bool probIsInside = true, // ถ้า prob หมายถึง "ด้านใน" ให้กลับขั้วเป็น mask_out
  }) async {
    final h = prob.length;
    final w = prob[0].length;

    // ใช้ package:image ทำ 8-bit แล้วค่อย decode เป็น Mat
    final canvas = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final inside = prob[y][x] >= thr;
        final isOutsideWhite = probIsInside ? !inside : inside;
        final v = isOutsideWhite ? 255 : 0;
        canvas.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    final smallPng = td.Uint8List.fromList(img.encodePng(canvas));
    cv.Mat m = await _decodeBgr(smallPng);
    if (m.channels > 1) m = cv.cvtColor(m, cv.COLOR_BGR2GRAY);
    final resized = cv.resize(m, (outW, outH), interpolation: cv.INTER_NEAREST);
    return cv.threshold(resized, 127.0, 255.0, cv.THRESH_BINARY).$2;
  }

  /// safe mask ด้วย distanceTransform (แบบ 2)
  cv.Mat _allInsideMask(cv.Mat inside,
      {int dx = _DX, int dy = _DY, int extraPx = _SHRINK_EXTRA}) {
    final pair =
        cv.distanceTransform(inside, cv.DIST_L2, 3, cv.DIST_LABEL_PIXEL);
    final dist = pair.$1;
    final need = math.max(extraPx, math.max(dx, dy)).toDouble();
    final safe = cv.threshold(dist, need, 255.0, cv.THRESH_BINARY).$2;
    return cv.convertScaleAbs(safe);
  }

  /// สร้างพื้นที่ปลอดภัยพิเศษสำหรับคำนวณ H/C (ลึกกว่า insideSafe อีกนิด)
  cv.Mat _makeInsideForHC(cv.Mat insideSafe) {
    final deeper = _allInsideMask(
      insideSafe,
      dx: _DX,
      dy: _DY,
      extraPx: _SHRINK_EXTRA + _HC_EXTRA_MARGIN_PX,
    );
    return deeper;
  } 
  /// สร้าง edge mask แบบ simple ด้วย morphological gradient (dilate - erode)
  cv.Mat _edgeMaskSimple(cv.Mat gray, cv.Mat insideMask) {
    // kernel สี่เหลี่ยม 3x3
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));

    // gradient = dilate - erode
    final dil = cv.dilate(gray, kernel, iterations: 1);
    final ero = cv.erode(gray, kernel, iterations: 1);
    final grad = cv.subtract(dil, ero);

    // threshold เพื่อให้ได้ขอบคมชัด
    final edges = cv.threshold(grad, 12.0, 255.0, cv.THRESH_BINARY).$2;

    // จำกัดขอบให้อยู่เฉพาะด้านใน template
    return cv.min(edges, insideMask);
  }





  /// คำนวณ H/C พร้อม "ศูนย์จริง" guard (ไม่ใช้ Gaussian/Sobel/Laplacian)
  ({double ent, double comp}) _computeEntCompWithZeroGuard({
    required cv.Mat bgr,
    required cv.Mat gray,
    required cv.Mat insideForHC,
  }) {
    // denoise เบาๆ ด้วย median (เมธอดนี้มีในแพ็กเกจ)
    final bgrMed = cv.medianBlur(bgr, 3);

    // 1) คำนวณ Entropy / Complexity ปกติ
    double ent = EntropyCV.computeNormalized(
      bgrMed,
      mask: insideForHC,
      dx: _DX,
      dy: _DY,
    );
    double comp = ComplexityCV.edgeDensity(
      bgrMed,
      mask: insideForHC,
      dx: _DX,
      dy: _DY,
    );

    // 2) วัด "edge ratio" ด้วย morphological gradient (แทน Sobel/Canny)
    final edgesInside = _edgeMaskSimple(gray, insideForHC);
    final areaInside  = math.max(1, cv.countNonZero(insideForHC));
    final edgeRatio   = cv.countNonZero(edgesInside) / areaInside;

    // 3) วัด "colored ratio" = พิกเซลที่มีสีจริงและไม่ขาว
    final hsv = cv.cvtColor(bgrMed, cv.COLOR_BGR2HSV);
    final sCh = () { try { return cv.extractChannel(hsv, 1); } catch (_) { return cv.split(hsv)[1]; } }();
    final satHi     = cv.threshold(sCh, _SAT_MIN_COLORED * 1.0, 255.0, cv.THRESH_BINARY).$2;
    final notWhite  = cv.threshold(gray, _V_NEARWHITE   * 1.0, 255.0, cv.THRESH_BINARY_INV).$2;
    // opencv_dart ไม่มี bitwiseAnd(mask:...) → ใช้ min() แทน AND
    final colored        = cv.min(satHi, notWhite);
    final coloredInside  = cv.min(colored, insideForHC);
    final coloredRatio   = cv.countNonZero(coloredInside) / areaInside;

    // 4) Zero-Guard: ถ้า “ไม่มีลาย” และ “แทบไม่มีสี” → บังคับ H/C = 0
    if (edgeRatio < _EDGE_RATIO_EPS && coloredRatio < _COLORED_RATIO_EPS) {
      ent  = 0.0;
      comp = 0.0;
      debugPrint('🧪 ZeroGuard: edgeRatio=${edgeRatio.toStringAsFixed(6)}, '
                'coloredRatio=${coloredRatio.toStringAsFixed(6)} → H/C=0');
    } else {
      debugPrint('ℹ️ H/C kept: edgeRatio=${edgeRatio.toStringAsFixed(6)}, '
                'coloredRatio=${coloredRatio.toStringAsFixed(6)}');
    }

    return (ent: ent, comp: comp);
  }


  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- Pipeline ----------
  // Future<void> _run({Uint8List? overrideBytes}) async {
  Future<void> _run({td.Uint8List? overrideBytes}) async {
    try {
      // 1) load image (แบบ 1: orientation+crop+resize)
      td.Uint8List rawBytes;
      if (overrideBytes != null) {
        rawBytes = overrideBytes;
      } else if (widget.imageBytes != null) {
        rawBytes = widget.imageBytes!;
      } else if (widget.imageAssetPath != null) {
        rawBytes = await _loadAssetBytes(widget.imageAssetPath!);
      } else {
        final src = await _askImageSource();
        if (src == null) throw Exception('ยกเลิกการเลือกรูปภาพ');
        final XFile? picked = await ImagePicker().pickImage(source: src);
        if (picked == null) throw Exception('ยังไม่ได้เลือกรูปจาก $src');
        rawBytes = await picked.readAsBytes();
      }

      // 2) preprocess → preview PNG
      final preBytes = _preprocessBytes(rawBytes, target: 900);
      _previewBytes = preBytes;
      cv.Mat bgr = await _decodeBgr(preBytes);

      // 3) prepare masks (AI ถ้าเปิดและ available)
      await _aiWarmup;
      cv.Mat? maskOutAi;
      _aiMaskUsed = false;

      if (_useAiMask) {
        if (!PaintSeg.instance.available) {
          _snack('ยังไม่มีโมเดล AI · ใช้ mask ปกติแทน');
        } else if (_previewBytes != null && _imgW != null && _imgH != null) {
          try {
            final rgba = _pngToRgba(_previewBytes!);
            final prob = PaintSeg.instance.run(rgba, _imgW!, _imgH!);
            // prob = inside → กลับขั้วเป็น mask_out
            maskOutAi = await _probToMaskOut(
              prob,
              bgr.cols,
              bgr.rows,
              thr: 0.5,
              probIsInside: true,
            );
            _aiMaskUsed = true;
          } catch (e) {
            debugPrint('AI mask failed: $e');
            _snack('AI mask ใช้งานไม่ได้ · ใช้ mask ปกติแทน');
            _aiMaskUsed = false;
          }
        }
      }

      // 4) สร้าง masks แยกตามงาน
      late cv.Mat insideForBlank;
      late cv.Mat insideForCotl;
      late cv.Mat insideForHC;

      if (maskOutAi != null) {
        // AI → mask_out (ขาว=นอก) → inside
        final insideFromAi = cv.bitwiseNOT(maskOutAi);
        final insideEnsured = ensureWhiteIsInside(insideFromAi);
        final resized = insideEnsured; // AI ออกมาก็เท่ารูปแล้ว

        // ⬇️ แยกใช้
        insideForBlank = shrinkInsideForSafeCount(resized, px: 1);      // บางเหมือนเดิม
        insideForCotl  = shrinkInsideForSafeCount(resized, px: 1);
        insideForHC    = _makeInsideForHC(resized);                     // หนาเฉพาะ H/C
      } else {
        // จาก asset ปกติ: _mask.png (ขาว=ด้านใน)
        final maskInRaw = await _loadBinaryMask(widget.maskAssetPath);
        final insideRaw = ensureWhiteIsInside(maskInRaw);
        final inside = cv.resize(insideRaw, (bgr.cols, bgr.rows), interpolation: cv.INTER_NEAREST);

        // ⬇️ แยกใช้
        insideForBlank = shrinkInsideForSafeCount(inside, px: 1);       // ❗ ไม่ผ่าน _allInsideMask
        // COTL: พยายามใช้ _mask_out ถ้ามี
        final maskOutPath = widget.maskAssetPath
            .replaceAll('assets/masks/', 'assets/masks_out/')
            .replaceAll('_mask', '_mask_out');
        try {
          final maskOutRaw = await _loadBinaryMask(maskOutPath);        // ขาว=นอก
          final insideFromOut = ensureWhiteIsInside(cv.bitwiseNOT(maskOutRaw));
          insideForCotl = cv.resize(insideFromOut, (bgr.cols, bgr.rows), interpolation: cv.INTER_NEAREST);
          insideForCotl = shrinkInsideForSafeCount(insideForCotl, px: 1);
        } catch (_) {
          insideForCotl = insideForBlank;
        }

        insideForHC = _makeInsideForHC(inside);                         // หนาเฉพาะ H/C
      }


      // 5) channels
      final gray = cv.cvtColor(bgr, cv.COLOR_BGR2GRAY);
      final sat  = _extractS(bgr);

      // 6) metrics — ใช้ mask แยกตามงาน
      double blank = await computeBlank(gray, sat, insideForBlank);
      final double cotl  = await computeCotl(
        gray,
        sat,
        cv.bitwiseNOT(insideForCotl), // ส่ง mask_out ให้ COTL
      );

      // ถ้ารูป "ว่างเกือบทั้งหมด" ให้ปัดเป็น 1.0 เพื่อได้ 1.0000 เป๊ะ
      if ((1.0 - blank) < _BLANK_ONE_EPS) {
        blank = 1.0;
      }


      // ===== DEBUG: แสดงขนาดพื้นที่ของแต่ละ mask + ค่า blank คร่าว ๆ =====
      debugPrint(
        '🟣 RUN_METRICS v3 — areas: '
        'blank=${cv.countNonZero(insideForBlank)}, '
        'cotl=${cv.countNonZero(insideForCotl)}, '
        'hc=${cv.countNonZero(insideForHC)} | '
        'blank≈${blank.toStringAsFixed(4)}'
      );

      // คำนวณ H/C ด้วย Zero-Guard (ใช้เฉพาะ insideForHC)
      final hc = _computeEntCompWithZeroGuard(
        bgr: bgr,
        gray: gray,
        insideForHC: insideForHC,
      );
      double ent  = hc.ent;
      double comp = hc.comp;

      // เงื่อนไขอัดเป็นศูนย์แบบเสริม (เพื่อภาพที่ยังไม่ระบายจริง ๆ)
      if (blank > 0.985 && (cotl == 0.0 || cotl.abs() < 1e-6)) {
        debugPrint('✅ ForceZero: blank>0.985 && cotl≈0 → H/C=0');
        ent  = 0.0;
        comp = 0.0;
      }

      // ===== DEBUG: สรุปค่าออกปลายทาง =====
      debugPrint(
        '📊 FINAL  H=${ent.toStringAsFixed(6)} '
        'C=${comp.toStringAsFixed(6)}  '
        'Blank=${blank.toStringAsFixed(6)}  '
        'COTL=${cotl.toStringAsFixed(6)}'
      );

      // 7) index & z
      await _svcWarmup;
      final raw = await ZScoreService.instance.computeRaw(
        templateKey: _classKey,
        age: _age,
        h: ent,
        c: comp,
        blank: blank,
        cotl: cotl,
      );
      final z = await ZScoreService.instance.compute(
        templateKey: _classKey,
        age: _age,
        h: ent,
        c: comp,
        blank: blank,
        cotl: cotl,
      );

      // 8) save history
      try {
        // final Uint8List pngBytes = _previewBytes ?? _matToPng(bgr);
        final td.Uint8List pngBytes = _previewBytes ?? _matToPng(bgr);
        String imagePath = '';
        if (_profileKey.isNotEmpty) {
          imagePath = await HistoryRepo.I.saveImageBytes(
            pngBytes,
            profileKey: _profileKey,
          );
        }

        final now = DateTime.now();
        final rec = HistoryRecord(
          id: now.millisecondsSinceEpoch.toString(),
          createdAt: now,
          profileKey: _profileKey,
          templateKey: _classKey,
          age: _age,
          h: ent,
          c: comp,
          blank: blank,
          cotl: cotl,
          zH: z.zH,
          zC: z.zC,
          zBlank: z.zBlank,
          zCotl: z.zCotl,
          zSum: z.zSum,
          level: raw.level,
          imagePath: imagePath,
        );
        await HistoryRepo.I.add(_profileKey, rec);
        debugPrint('✅ [HIS] saved ${rec.id} for profile=$_profileKey');
      } catch (e) {
        debugPrint('⚠️ [HIS] save failed: $e');
      }

      if (!mounted) return;
      setState(() {
        _previewBytes = _previewBytes; // already set
        _blank = blank;
        _cotl = cotl;
        _entropy = ent;
        _complexity = comp;

        _indexRaw = raw.index;
        _level = raw.level;

        _lowCut = raw.lowCut;
        _highCut = raw.highCut;
        _mu = raw.mu;
        _sigma = raw.sigma;

        _error = null;
        _imgW = _imgW;
        _imgH = _imgH;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  // ===== UI helpers =====
  Future<ImageSource?> _askImageSource() async {
    if (!mounted) return null;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'เลือกแหล่งรูปภาพ',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'เลือกรูปจากแกลเลอรีหรือถ่ายใหม่ด้วยกล้อง',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            _SheetActionButton(
              icon: Icons.photo_library_outlined,
              label: 'เลือกรูปจากแกลเลอรี',
              filled: true,
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 10),
            _SheetActionButton(
              icon: Icons.photo_camera_outlined,
              label: 'ถ่ายรูปด้วยกล้อง',
              filled: false,
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ⭐ ดาว (คงเมธอดเดิม)
  Widget _buildStarLevel(String? level) {
    if (level == null || level.trim().isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (i) => Icon(
            Icons.star_border_rounded,
            size: 30,
            color: Colors.grey.shade400,
          ),
        ),
      );
    }

    final s = level.toLowerCase();
    int stars = 3;
    final very = s.contains('มาก');
    final hi = s.contains('สูง') || s.contains('ดีกว่า') || s.contains('above');
    final low =
        s.contains('ต่ำ') || s.contains('ต่ำกว่า') || s.contains('below');
    final normal =
        s.contains('ปกติ') || s.contains('เกณฑ์') || s.contains('normal');

    if (hi && very) {
      stars = 5;
    } else if (hi) {
      stars = 4;
    } else if (low && very) {
      stars = 1;
    } else if (low) {
      stars = 2;
    }

    final gradient = const LinearGradient(
      colors: [Color(0xFFFFD700), Color(0xFFFFA726)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < stars;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (Rect bounds) => gradient.createShader(bounds),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_border_rounded,
              size: 32,
              color: filled ? Colors.amber : Colors.grey.shade400,
              shadows: filled
                  ? [Shadow(color: Colors.amber.withOpacity(0.6), blurRadius: 8)]
                  : [],
            ),
          ),
        );
      }),
    );
  }

  // เปิดดูรูปเต็มจอ
  void _openFullImage() {
    if (_previewBytes == null) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InteractiveViewer(
            minScale: 0.7,
            maxScale: 5,
            child: Image.memory(_previewBytes!, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  // เลือกรูปใหม่แล้วประมวลผลต่อทันที
  Future<void> _changeImage() async {
    final src = await _askImageSource();
    if (src == null) return;
    final XFile? picked = await ImagePicker().pickImage(source: src);
    if (picked == null) return;
    setState(() {
      _previewBytes = null;
      _blank = _cotl = _entropy = _complexity = null;
      _indexRaw = null;
      _level = null;
      _lowCut = _highCut = _mu = _sigma = null;
      _error = null;
    });
    final bytes = await picked.readAsBytes();
    await _run(overrideBytes: bytes);
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final templateLabel =
        widget.templateName ?? _templateLabelFromKey(_classKey);

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text('ประมวลผล · $templateLabel')),
        body: Center(
          child: Text(
            'เกิดข้อผิดพลาด:\n$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    final waiting =
        _blank == null || _cotl == null || _entropy == null || _complexity == null;

    if (waiting) {
      return Scaffold(
        appBar: AppBar(title: Text('ประมวลผล · $templateLabel')),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            SizedBox(height: 8),
            Center(child: CircularProgressIndicator()),
            SizedBox(height: 10),
            Text('กำลังประมวลผล...'),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('ผลการประเมิน · $templateLabel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_previewBytes != null) ...[
            _PreviewCard(
              bytes: _previewBytes!,
              chipText:
                  'อายุ $_age ขวบ • $templateLabel'
                  '${_imgW != null && _imgH != null ? ' • ${_imgW}×${_imgH}px' : ''}'
                  '${_aiMaskUsed ? ' • AI mask' : ''}',
              onZoom: _openFullImage,
              // trailing: Row(
              //   mainAxisSize: MainAxisSize.min,
              //   children: [
              //     const Text('ใช้ AI mask'),
              //     const SizedBox(width: 6),
              //     Switch(
              //       value: _useAiMask && PaintSeg.instance.available,
              //       onChanged: (v) async {
              //         if (v && !PaintSeg.instance.available) {
              //           _snack('ยังไม่มีโมเดล AI');
              //           return;
              //         }
              //         setState(() => _useAiMask = v);
              //         // re-run
              //         setState(() {
              //           _blank = _cotl = _entropy = _complexity = null;
              //           _indexRaw = null;
              //           _level = null;
              //           _lowCut = _highCut = _mu = _sigma = null;
              //           _error = null;
              //         });
              //         await _run(overrideBytes: _previewBytes!);
              //       },
              //     ),
              //   ],
              // ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openFullImage,
                    icon: const Icon(Icons.open_in_full_rounded),
                    label: const Text('เปิดเต็มจอ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _changeImage(),
                    icon: const Icon(Icons.image_search_outlined),
                    label: const Text('เปลี่ยนรูป'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 🟣 การ์ดสรุปผล
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.28),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.primary.withOpacity(0.25)),
                boxShadow: [
                  BoxShadow(
                    color: cs.primary.withOpacity(0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ภาพรวมการประเมิน',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildStarLevel(_level),
                  const SizedBox(height: 6),
                  Text(
                    _level ?? '-',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withOpacity(0.75),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          const Divider(height: 28),

          Text('ค่าชี้วัดดิบ', style: theme.textTheme.titleLarge),
          _metricRow('Blank (ในเส้น)', _blank!),
          _metricRow('COTL (นอกเส้น)', _cotl!),
          _metricRow('Entropy (normalized)', _entropy!),
          _metricRow('Complexity', _complexity!),

          const Divider(height: 28),

          Text('ดัชนีรวม (Index – raw)', style: theme.textTheme.titleLarge),
          _metricRow('Index', _indexRaw ?? 0),

          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.home_outlined),
            label: const Text('กลับไปหน้าเลือกเทมเพลต'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricRow(String label, double value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.black12.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value.toStringAsFixed(4)),
          ],
        ),
      );
}

// ===== ปุ่มการ์ดใน bottom sheet =====
class _SheetActionButton extends StatelessWidget {
  const _SheetActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bgColor = filled ? cs.primaryContainer.withOpacity(0.35) : cs.surface;
    final borderColor =
        filled ? cs.primary.withOpacity(0.35) : cs.outlineVariant;
    final iconColor = filled ? cs.primary : cs.onSurfaceVariant;
    final textStyle = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.w800);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: textStyle)),
            Icon(
              Icons.chevron_right_rounded,
              color: cs.onSurfaceVariant,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

// ===== การ์ดพรีวิวรูป (มีสวิตช์ AI mask ที่มุมขวาล่าง) =====
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.bytes,
    required this.chipText,
    required this.onZoom,
    this.trailing,
  });

  // final Uint8List bytes;
  final td.Uint8List bytes;
  final String chipText;
  final VoidCallback onZoom;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Container(
            color: cs.surfaceVariant.withOpacity(0.35),
            width: double.infinity,
            alignment: Alignment.center,
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
          Positioned(
            left: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surface.withOpacity(0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    chipText,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (trailing != null) Positioned(right: 10, bottom: 10, child: trailing!),
          Positioned(
            right: 8,
            top: 8,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onZoom,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.zoom_in_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
