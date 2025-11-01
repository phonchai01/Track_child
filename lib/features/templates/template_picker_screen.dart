// lib/features/templates/template_picker_screen.dart
import 'package:flutter/material.dart';
import '../processing/processing_screen.dart';
import '../history/history_list_screen.dart';

class TemplateSpec {
  final String key; // 'fish' | 'pencil' | 'icecream'
  final String title; // ชื่อไทยโชว์บนการ์ด
  final String templateAssetPath; // ภาพตัวอย่าง (ถ้ามี)

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
    templateAssetPath: 'assets/templates/fish.png',
  ),
  TemplateSpec(
    key: 'pencil',
    title: 'ดินสอ',
    templateAssetPath: 'assets/templates/pencil.png',
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
    final hit = kTemplates.where((e) => e.key == key);
    if (hit.isNotEmpty) return hit.first.title;
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
        centerTitle: false,
        actions: [
          if (profileKey.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.badge_outlined, size: 18),
                label: Text('โปรไฟล์: $profileKey'),
                onPressed: () {}, // just info
              ),
            ),
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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: GridView.builder(
          itemCount: kTemplates.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            // ปรับสัดส่วนให้ไม่ล้น (สูงกว่ากว้างนิดหน่อย)
            childAspectRatio: 0.78,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (_, i) {
            final t = kTemplates[i];
            final isSel = t.key == _selectedKey;
            return _TemplateCard(
              spec: t,
              selected: isSel,
              onTap: () => _onSelect(t.key),
            );
          },
        ),
      ),

      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ElevatedButton.icon(
          icon: const Icon(Icons.photo_camera_back_outlined),
          onPressed: (_selectedKey ?? '').isEmpty
              ? null
              : () {
                  final key = _selectedKey!;
                  final title = _titleForKey(key);
                  final maskPath = 'assets/masks/${key}_mask.png';

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProcessingScreen(
                        maskAssetPath: maskPath,
                        templateName: title,
                      ),
                      settings: RouteSettings(
                        arguments: {'profile': profile, 'template': key},
                      ),
                    ),
                  );
                },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          label: Text(
            (_selectedKey ?? '').isEmpty
                ? 'ไปเลือก/ถ่ายรูป'
                : 'ไปเลือก/ถ่ายรูป – ${_titleForKey(_selectedKey!)}',
          ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final TemplateSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? Theme.of(context).colorScheme.primary
        : Colors.black12;
    final fill = selected
        ? Theme.of(context).colorScheme.primary.withOpacity(0.06)
        : Colors.black12.withOpacity(0.04);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thumbnail (คุมสูงแน่นอน = ไม่ล้น)
            Container(
              height: 110,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  spec.templateAssetPath,
                  fit: BoxFit.contain,
                  width: 120,
                  height: 90,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.image_outlined,
                    size: 40,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Title
            Text(
              spec.title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            // Sub pill
            Container(
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black12.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                spec.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Spacer(),
            // Selected tick
            Align(
              alignment: Alignment.topRight,
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 14, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
