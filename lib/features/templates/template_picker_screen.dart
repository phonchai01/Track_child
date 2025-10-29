// lib/features/templates/template_picker_screen.dart
import 'package:flutter/material.dart';
// ไม่จำเป็นแล้ว: import '../processing/pick_image_screen.dart';
import '../processing/processing_screen.dart';

class TemplateSpec {
  final String key; // ใช้เป็น id ภายใน เช่น 'fish'
  final String title; // ชื่อที่โชว์บนการ์ด
  final String templateAssetPath; // ยังเก็บไว้ได้ เผื่อใช้อย่างอื่นภายหลัง

  const TemplateSpec({
    required this.key,
    required this.title,
    required this.templateAssetPath,
  });
}

// TODO: ปรับ path ให้ตรงกับของคุณ (ตอนนี้ยังไม่ใช้ค่า templateAssetPath ในการคำนวณ)
const kTemplates = <TemplateSpec>[
  TemplateSpec(
    key: 'fish',
    title: 'ปลา',
    templateAssetPath: 'assets/templates/templates_fish.png',
  ),
  TemplateSpec(
    key: 'pencil',
    title: 'ดินสอ',
    templateAssetPath: 'assets/templates/templates_pencil.png',
  ),
  TemplateSpec(
    key: 'icecream',
    title: 'ไอศกรีม',
    templateAssetPath: 'assets/templates/templates_icecream.png',
  ),
];

class TemplatePickerScreen extends StatefulWidget {
  const TemplatePickerScreen({super.key});

  @override
  State<TemplatePickerScreen> createState() => _TemplatePickerScreenState();
}

class _TemplatePickerScreenState extends State<TemplatePickerScreen> {
  String? _selectedKey;

  void _onSelect(String key) {
    setState(() => _selectedKey = key);
  }

  @override
  Widget build(BuildContext context) {
    final selected = kTemplates.firstWhere(
      (t) => t.key == _selectedKey,
      orElse: () =>
          const TemplateSpec(key: '', title: '', templateAssetPath: ''),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('เลือกเทมเพลต')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.builder(
          itemCount: kTemplates.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.85,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (_, i) {
            final t = kTemplates[i];
            final isSel = t.key == _selectedKey;
            return InkWell(
              onTap: () => _onSelect(t.key),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSel ? Colors.blue : Colors.grey.shade400,
                    width: isSel ? 2.0 : 1.0,
                  ),
                  color: isSel
                      ? Colors.blue.withOpacity(0.05)
                      : Colors.grey.withOpacity(0.06),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Icon(
                      Icons.image_outlined,
                      size: 48,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSel
                            ? Colors.blueGrey.shade200
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        t.title,
                        style: TextStyle(
                          color: isSel ? Colors.black : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ElevatedButton(
          onPressed: (_selectedKey ?? '').isEmpty
              ? null
              : () {
                  final key = _selectedKey!; // fish / pencil / icecream
                  final maskPath = 'assets/masks/${key}_mask.png';

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProcessingScreen(
                        // ProcessingScreen จะเปิด picker ให้เลือก/ถ่ายรูปอัตโนมัติถ้าไม่ส่ง imageBytes
                        maskAssetPath: maskPath,
                        showInlineResult: true,
                        templateAssetPath: '',
                      ),
                    ),
                  );
                },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Text('ไปเลือก/ถ่ายรูป'),
        ),
      ),
    );
  }
}
