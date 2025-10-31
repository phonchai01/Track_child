// lib/features/templates/template_picker_screen.dart
import 'package:flutter/material.dart';
import '../processing/processing_screen.dart';
import '../history/history_list_screen.dart';

class TemplateSpec {
  final String key; // 'fish' | 'pencil' | 'icecream'
  final String title; // ชื่อที่โชว์บนการ์ด (ไทย)
  final String templateAssetPath; // เผื่อใช้งานภายหลัง

  const TemplateSpec({
    required this.key,
    required this.title,
    required this.templateAssetPath,
  });
}

const kTemplates = <TemplateSpec>[
  TemplateSpec(
    key: 'fish',
    title: 'ปลา',
    templateAssetPath: 'assets/templates/template_fish.png',
  ),
  TemplateSpec(
    key: 'pencil',
    title: 'ดินสอ',
    templateAssetPath: 'assets/templates/template_pencil.png',
  ),
  TemplateSpec(
    key: 'icecream',
    title: 'ไอศกรีม',
    templateAssetPath: 'assets/templates/template_icecream.png',
  ),
];

class TemplatePickerScreen extends StatefulWidget {
  const TemplatePickerScreen({super.key});

  @override
  State<TemplatePickerScreen> createState() => _TemplatePickerScreenState();
}

class _TemplatePickerScreenState extends State<TemplatePickerScreen> {
  String? _selectedKey;

  String _extractProfileKey(Map<String, dynamic>? p) {
    final k = p?['key'] ?? p?['id'] ?? p?['profileKey'] ?? p?['name'] ?? '';
    return k.toString();
  }

  void _onSelect(String key) => setState(() => _selectedKey = key);

  String _titleForKey(String key) {
    // ถ้ามีใน kTemplates ใช้ชื่อจากนั้นก่อน
    final hit = kTemplates.where((e) => e.key == key);
    if (hit.isNotEmpty) return hit.first.title;

    // fallback กัน key แปลก ๆ
    switch (key) {
      case 'fish':
        return 'ปลา';
      case 'pencil':
        return 'ดินสอ';
      case 'icecream':
        return 'ไอศกรีม';
      default:
        return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final profile = (args?['profile'] as Map?)?.cast<String, dynamic>();
    final profileKey = _extractProfileKey(profile);

    return Scaffold(
      appBar: AppBar(
        title: const Text('เลือกเทมเพลต'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'ดูประวัติการประเมิน',
            onPressed: () {
              if (profileKey.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ยังไม่มีโปรไฟล์/คีย์โปรไฟล์')),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HistoryListScreen(profileKey: profileKey),
                ),
              );
            },
          ),
        ],
      ),
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
                  final key = _selectedKey!; // 'fish' | 'pencil' | 'icecream'
                  final maskPath = 'assets/masks/${key}_mask.png';
                  final title = _titleForKey(key); // ชื่อไทยของเทมเพลต

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProcessingScreen(
                        maskAssetPath: maskPath,
                        templateName: title, // ✅ ใช้ title ที่คำนวณ
                      ),
                      settings: RouteSettings(
                        arguments: {'profile': profile, 'template': key},
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
