import 'package:image/image.dart' as img;

/// ครอปตรงกลางแบบสี่เหลี่ยมจัตุรัส แล้วรีไซซ์เป็นขนาดเป้าหมาย
class WarpCrop {
  static img.Image centerCropResize(img.Image src, {int target = 512}) {
    // เผื่อกรณีที่รูปมี EXIF orientation
    final oriented = img.bakeOrientation(src);

    final side = oriented.width < oriented.height
        ? oriented.width
        : oriented.height;

    final x0 = (oriented.width - side) ~/ 2;
    final y0 = (oriented.height - side) ~/ 2;

    // ✅ copyCrop ใน v4 ใช้ named parameters
    final cropped = img.copyCrop(
      oriented,
      x: x0,
      y: y0,
      width: side,
      height: side,
    );

    // ✅ copyResize ใช้ named parameters เช่นกัน
    return img.copyResize(
      cropped,
      width: target,
      height: target,
      interpolation: img.Interpolation.linear,
    );
  }

  /// stub สำหรับอนาคต: perspective transform
  static img.Image perspectiveStub(img.Image src) => src;
}
