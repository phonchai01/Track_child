import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_record.dart';

class HistoryRepo {
  static const _kKey = 'history_records';

  // อ่านทั้งหมด
  Future<List<HistoryRecord>> getAll() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_kKey) ?? const [];
    return list.map((e) => HistoryRecord.fromJson(e)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // ใหม่อยู่บน
  }

  // เพิ่ม 1 รายการ
  Future<void> add(HistoryRecord rec) async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_kKey) ?? <String>[];
    list.add(rec.toJson());
    await sp.setStringList(_kKey, list);
  }

  // เซฟรูปลงโฟลเดอร์แอป และคืน path
  Future<String> saveImageBytes(Uint8List bytes, {String? name}) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/history');
    if (!await folder.exists()) await folder.create(recursive: true);
    final file = File(
      '${folder.path}/${name ?? DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  // ลบทั้งหมด (เผื่อปุ่มล้างประวัติ)
  Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kKey);
  }
}

final historyRepo = HistoryRepo();
