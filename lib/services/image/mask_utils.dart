import 'dart:typed_data';
import 'package:image/image.dart' as img;

class MaskUtils {
  /// โหลดภาพ mask จาก bytes (รองรับ PNG/JPG)
  static img.Image decodeMask(Uint8List bytes) => img.decodeImage(bytes)!;

  /// รีไซซ์ mask ให้เท่ารูปอ้างอิง
  static img.Image resizeTo(img.Image mask, int width, int height) =>
      img.copyResize(
        mask,
        width: width,
        height: height,
        interpolation: img.Interpolation.linear,
      );

  /// ทำ Binarize mask เป็น 0/255 ด้วย threshold (ค่าเทา)
  /// ใช้ค่า Luminance จาก RGB (Rec. 709)
  static img.Image binarize(img.Image mask, {int threshold = 128}) {
    final out = img.Image.from(mask);

    for (int y = 0; y < mask.height; y++) {
      for (int x = 0; x < mask.width; x++) {
        final px = mask.getPixel(x, y); // Pixel object
        final r = px.r.toDouble();
        final g = px.g.toDouble();
        final b = px.b.toDouble();

        // Luminance (0..255)
        final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b).round();
        final v = lum >= threshold ? 255 : 0;

        out.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return out;
  }

  /// Apply mask: คงค่าพิกเซลเฉพาะบริเวณที่ mask “ขาว” (>=128) ที่เหลือทำเป็นขาวทึบ
  /// *ถ้าอยากให้โปร่งใส ให้เปลี่ยนค่า alpha เป็น 0 แทน 255*
  static img.Image applyMask(img.Image src, img.Image mask) {
    assert(
      src.width == mask.width && src.height == mask.height,
      'applyMask: source/mask size mismatch',
    );

    final out = img.Image.from(src);

    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final m = mask.getPixel(x, y);
        // ใช้ช่องแดงเป็นตัวแทนความเข้มของ mask (เพราะเป็นภาพขาวดำอยู่แล้ว)
        final maskValue = m.r;

        if (maskValue < 128) {
          // นอก mask → ทำเป็นสีขาว (ถ้าต้องการโปร่งใสเปลี่ยน a=0)
          out.setPixelRgba(x, y, 255, 255, 255, 255);
        } else {
          // ใน mask → เก็บพิกเซลเดิมไว้
          final s = src.getPixel(x, y);
          out.setPixelRgba(x, y, s.r, s.g, s.b, 255);
        }
      }
    }
    return out;
  }
}
