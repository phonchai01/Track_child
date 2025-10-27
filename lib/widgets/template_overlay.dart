import 'package:flutter/material.dart';

class TemplateOverlay extends StatelessWidget {
  final String templateName;
  final Size innerSize; // ขนาดพื้นที่ที่อยากให้เล็งภายใน
  const TemplateOverlay({
    super.key,
    required this.templateName,
    this.innerSize = const Size(260, 260),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, c) {
        final center = Offset(c.maxWidth / 2, c.maxHeight / 2);
        final rect = Rect.fromCenter(
          center: center,
          width: innerSize.width,
          height: innerSize.height,
        );

        return Stack(
          children: [
            // มืดด้านนอก เหลือช่องโปร่งตรงกลาง
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _DimAroundHolePainter(rect: rect),
                ),
              ),
            ),
            // กรอบ + ข้อความช่วยเล็ง
            Positioned.fromRect(
              rect: rect,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.deepPurple, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    'จัดตำแหน่งให้ภาพอยู่ภายในกรอบ\n("$templateName")',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DimAroundHolePainter extends CustomPainter {
  final Rect rect;
  _DimAroundHolePainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)));
    final diff = Path.combine(PathOperation.difference, outer, inner);

    final paint = Paint()
      ..color = const Color(0xAA000000) // มืดโปร่ง ๆ
      ..style = PaintingStyle.fill;
    canvas.drawPath(diff, paint);
  }

  @override
  bool shouldRepaint(covariant _DimAroundHolePainter oldDelegate) =>
      oldDelegate.rect != rect;
}
