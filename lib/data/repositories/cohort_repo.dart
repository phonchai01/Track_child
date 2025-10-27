import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CohortRepo {
  static const _prefsKey = 'profiles_v1';

  /// โครงสร้างข้อมูลพื้นฐานของโปรไฟล์
  /// { "id": "string", "name": "string", "age": 4|5 }
  Future<List<Map<String, dynamic>>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list;
  }

  Future<void> _saveAll(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(items));
  }

  Future<Map<String, dynamic>> add({
    required String name,
    required int age, // 4 or 5
  }) async {
    final items = await getAll();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final item = {"id": id, "name": name.trim(), "age": age};
    items.add(item);
    await _saveAll(items);
    return item;
  }

  Future<void> remove(String id) async {
    final items = await getAll();
    items.removeWhere((e) => e['id'] == id);
    await _saveAll(items);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
