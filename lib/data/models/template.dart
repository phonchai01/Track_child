// lib/models/template.dart
class ColoringTemplate {
  final String key; // ใช้เป็นตัวระบุในระบบ เช่น 'fish'
  final String title; // ชื่อแสดงบน UI
  final String maskAsset; // พาธไฟล์ mask (PNG ขาว/ดำ)
  final String tmplAsset; // พาธไฟล์ template (ภาพเส้น)
  const ColoringTemplate({
    required this.key,
    required this.title,
    required this.maskAsset,
    required this.tmplAsset,
  });
}

const templates = <ColoringTemplate>[
  ColoringTemplate(
    key: 'fish',
    title: 'ปลา',
    maskAsset: 'assets/masks/fish_mask.png',
    tmplAsset: 'assets/templates/fish_template.png',
  ),
  ColoringTemplate(
    key: 'pencil',
    title: 'ดินสอ',
    maskAsset: 'assets/masks/pencil_mask.png',
    tmplAsset: 'assets/templates/pencil_template.png',
  ),
  ColoringTemplate(
    key: 'icecream',
    title: 'ไอศกรีม',
    maskAsset: 'assets/masks/icecream_mask.png',
    tmplAsset: 'assets/templates/icecream_template.png',
  ),
];
