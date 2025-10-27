// lib/features/templates/template_picker_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_phone_app/data/models/template.dart';

import '../../models/template.dart'; // <- แหล่งข้อมูล templates
import '../../routes.dart'; // <- ใช้ AppRoutes.camera

class TemplatePickerScreen extends StatefulWidget {
  const TemplatePickerScreen({super.key});

  @override
  State<TemplatePickerScreen> createState() => _TemplatePickerScreenState();
}

class _TemplatePickerScreenState extends State<TemplatePickerScreen> {
  String? _selectedKey;

  void _onSelect(ColoringTemplate t) {
    setState(() => _selectedKey = t.key);
  }

  void _goNext() {
    final t = templates.firstWhere((e) => e.key == _selectedKey);
    // ➜ ไปหน้าเลือก/ถ่ายรูป พร้อมส่ง templateKey ที่เลือก
    Navigator.pushNamed(
      context,
      AppRoutes.camera,
      arguments: {'templateKey': t.key},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('เลือกเทมเพลต')),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.0,
        ),
        itemCount: templates.length,
        itemBuilder: (_, i) {
          final t = templates[i];
          final isSelected = t.key == _selectedKey;

          return InkWell(
            onTap: () => _onSelect(t),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  width: isSelected ? 3 : 1,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.dividerColor,
                ),
                boxShadow: [
                  if (isSelected)
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(.15),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // แสดงภาพเทมเพลตเป็นตัวอย่าง
                  Image.asset(
                    t.tmplAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(t.title, style: theme.textTheme.titleMedium),
                    ),
                  ),
                  // แถบชื่อด้านล่าง
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      color: Colors.black.withOpacity(0.35),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        t.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  // ไอคอนติ๊กถูกเมื่อเลือกแล้ว
                  if (isSelected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: theme.colorScheme.primary,
                        child: const Icon(
                          Icons.check,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: FilledButton(
          onPressed: _selectedKey == null ? null : _goNext,
          child: const Text('ไปเลือก/ถ่ายรูป'),
        ),
      ),
    );
  }
}
