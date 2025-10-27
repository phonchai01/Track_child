import 'package:flutter/material.dart';
import '../routes.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.deepPurple),
            child: Text(
              'เมนู',
              style: TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('เลือกเทมเพลต'),
            onTap: () => Navigator.pushNamed(context, AppRoutes.templates),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('ประวัติการถ่าย'),
            onTap: () => Navigator.pushNamed(context, AppRoutes.history),
          ),
          ListTile(
            leading: const Icon(Icons.show_chart),
            title: const Text('กราฟความคืบหน้า'),
            onTap: () => Navigator.pushNamed(context, AppRoutes.trends),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('ตั้งค่า (placeholder)'),
            onTap: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('ยังไม่ทำหน้านี้'))),
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('กราฟความคืบหน้า'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.trends);
            },
          ),
        ],
      ),
    );
  }
}
