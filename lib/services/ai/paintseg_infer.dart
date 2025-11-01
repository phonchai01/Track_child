// lib/services/ai/paintseg_infer.dart
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;
import 'package:image/image.dart' as img;

/// ใช้ TFLite ทำ segmentation พื้นที่ “ระบายสี”
/// หมายเหตุ: พารามิเตอร์ `rgbaBytes` ต้องเป็น **บัฟเฟอร์พิกเซลดิบ RGBA**
/// ไม่ใช่ PNG/JPEG ที่บีบอัดมาแล้ว
class PaintSeg {
  PaintSeg._();
  static final PaintSeg instance = PaintSeg._();

  tfl.Interpreter? _interpreter;
  int _inH = 256, _inW = 256;
  bool _available = false;

  bool get available => _available;

  /// โหลดโมเดลถ้ามีใน assets; ไม่พังถ้าไม่มี
  Future<void> ensureLoaded({
    String assetPath = 'assets/models/paintseg.tflite',
  }) async {
    if (_interpreter != null || _available) return;

    // เช็คจาก AssetManifest ก่อน (กัน error บอกไฟล์ไม่อยู่)
    try {
      final manifest = await rootBundle.loadString('AssetManifest.json');
      if (!manifest.contains(assetPath)) {
        _available = false;
        return;
      }
    } catch (_) {
      // บาง runtime หา manifest ไม่เจอ ก็ลองโหลดเลย ถ้า fail จะจับด้านล่าง
    }

    try {
      final itp = await tfl.Interpreter.fromAsset(assetPath);
      final shape = itp.getInputTensors().first.shape; // [1,H,W,3] โดยทั่วไป
      _inH = shape.length > 1 ? shape[1] : 256;
      _inW = shape.length > 2 ? shape[2] : _inH;
      _interpreter = itp;
      _available = true;
    } catch (e) {
      _interpreter = null;
      _available = false;
    }
  }

  /// ปิด / คืนทรัพยากร (ถ้าต้องการ)
  Future<void> dispose() async {
    try {
      _interpreter?.close();
    } catch (_) {}
    _interpreter = null;
    _available = false;
  }

  /// รันโมเดล → คืน prob-map ขนาด [H][W] (ค่าช่วง 0..1)
  /// ขาเข้า: บัฟเฟอร์ RGBA (ดิบ) + กว้าง/สูงจริงของภาพนั้น
  List<List<double>> run(Uint8List rgbaBytes, int w, int h) {
    if (!available || _interpreter == null) {
      throw StateError('PaintSeg model not available.');
    }

    // สร้างภาพจาก **พิกเซลดิบ** (RGBA)
    // image >= 4.x ต้องส่งเป็น ByteBuffer และกำหนด numChannels ให้ตรง
    final im = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: rgbaBytes.buffer, // ByteBuffer
      numChannels: 4, // RGBA
    );

    // resize -> ขนาดอินพุตของโมเดล
    final r = img.copyResize(im, width: _inW, height: _inH);

    // เตรียม input tensor [1, H, W, 3] แบบ float 0..1
    final input = List.generate(
      1,
      (_) => List.generate(_inH, (_) => List<double>.filled(3, 0.0)),
    );

    for (int y = 0; y < _inH; y++) {
      for (int x = 0; x < _inW; x++) {
        final color = r.getPixel(x, y); // int สีแบบ 0xAARRGGBB

        // ✅ แตกค่า RGB ด้วย bit shift (ไม่ต้องใช้ getRed)
        final pixel = r.getPixel(x, y); // คืนค่า Pixel object
        final rv = pixel.r.toDouble(); // แดง
        final gv = pixel.g.toDouble(); // เขียว
        final bv = pixel.b.toDouble(); // น้ำเงิน

        input[0][y][x] = [rv / 255.0, gv / 255.0, bv / 255.0] as double;
      }
    }

    // สร้าง output tensor [1, H, W, 1]
    final output = List.generate(
      1,
      (_) => List.generate(_inH, (_) => List<double>.filled(1, 0.0)),
    );

    // รันอินเฟอเรนซ์
    _interpreter!.run(input, output);

    // แปลง [1,H,W,1] → [H][W]
    final outputData = output[0]; // <- ตอนนี้คือ List<double> flatten แล้ว
    final prob = List.generate(_inH, (_) => List<double>.filled(_inW, 0.0));

    for (int y = 0; y < _inH; y++) {
      for (int x = 0; x < _inW; x++) {
        // คำนวณ index สำหรับ flatten array
        final idx = y * _inW + x;
        final v = (outputData[idx] is num)
            ? (outputData[idx] as num).toDouble()
            : 0.0;
        prob[y][x] = v;
      }
    }

    return prob;
  }
}
