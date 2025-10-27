import 'dart:typed_data';
import 'package:image/image.dart' as img;

class MaskUtils {
  /// โหลด mask จาก bytes
  static img.Image decodeMask(Uint8List bytes) => img.decodeImage(bytes)!;

  /// รีไซซ์ mask ให้เท่ารูป
  static img.Image resizeTo(img.Image mask, int width, int height) =>
      img.copyResize(
        mask,
        width: width,
        height: height,
        interpolation: img.Interpolation.linear,
      );

  /// ทำให้ mask เป็นขาวดำ (0/255) จาก threshold
  static img.Image binarize(img.Image mask, {int threshold = 128}) {
    final out = img.Image.from(mask);
    for (int y = 0; y < mask.height; y++) {
      for (int x = 0; x < mask.width; x++) {
        final pixel = mask.getPixel(x, y);
        final r = img.getRed(pixel);
        final g = img.getGreen(pixel);
        final b = img.getBlue(pixel);
        final l = img.getLuminanceRgb(r, g, b);
        final v = l >= threshold ? 255 : 0;
        out.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return out;
  }

  /// apply mask: คงค่าเฉพาะบริเวณขาวของ mask (255)
  static img.Image applyMask(img.Image src, img.Image mask) {
    final out = img.Image.from(src);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final m = mask.getPixel(x, y);
        final maskValue = img.getRed(m); // เอาค่าแดงแทน mask intensity
        if (maskValue < 128) {
          // นอก mask → ทำให้เป็นขาว/โปร่ง
          out.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }
    return out;
  }
}
