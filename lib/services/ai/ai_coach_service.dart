import 'dart:convert';
import 'package:http/http.dart' as http;

/// บริการ “AI โค้ช” สำหรับสรุปผล/แนะนำ
/// แนะนำให้ซ่อน API key ไว้หลัง proxy ของคุณเอง (เช่น Cloud Functions) แทนการใส่ในแอปโดยตรง
class AiCoachService {
  AiCoachService({http.Client? client, String? endpoint, String? apiKey})
    : _client = client ?? http.Client(),
      _endpoint = endpoint ?? 'https://api.openai.com/v1/chat/completions',
      _apiKey = apiKey ?? const String.fromEnvironment('OPENAI_API_KEY');

  final http.Client _client;
  final String _endpoint;
  final String _apiKey; // ❗️อย่า hardcode ใช้ secrets/proxy จะปลอดภัยกว่า

  /// สร้างคำอธิบายผลแบบอบอุ่น เข้าใจง่าย
  Future<String> buildParentFeedback({
    required String templateName, // ปลา/ดินสอ/ไอศกรีม
    required int age, // 4/5
    required double entropy,
    required double complexity,
    required double blank,
    required double cotl,
    required double index, // zSum หรือ index raw ที่คุณมี
    required String levelText, // เช่น “อยู่ในเกณฑ์มาตรฐาน”
  }) async {
    final prompt =
        '''
คุณคือผู้เชี่ยวชาญกิจกรรมศิลปะเด็กปฐมวัย ช่วยเขียนสรุปผลให้ผู้ปกครองแบบกำลังใจ อธิบายสั้น กระชับ อ่านง่าย (ไม่เกิน 4 ประโยค)
ข้อมูลผลงาน:
- เทมเพลต: $templateName
- อายุ: $age ขวบ
- ค่าชี้วัด: Entropy=$entropy, Complexity=$complexity, Blank(in)=$blank, COTL(out)=$cotl
- ดัชนีรวม: $index
- การแปลผลรวม: $levelText

แนวทาง:
- ใช้ภาษาบวก ให้กำลังใจเด็ก
- ชี้จุดเด่น 1 อย่าง และแนะนำต่อยอด 1 อย่าง (เช่น คุมมือให้ติดในเส้น/ฝึกใช้สีหลายเฉด)
- หลีกเลี่ยงศัพท์เทคนิค
- จบด้วยประโยคสร้างแรงจูงใจ
''';

    final body = {
      "model": "gpt-4o-mini", // รุ่นเบา/ไว (เปลี่ยนตามบัญชีของคุณ)
      "messages": [
        {
          "role": "system",
          "content":
              "You are a concise, supportive coach for parents of kindergarten children.",
        },
        {"role": "user", "content": prompt},
      ],
      "temperature": 0.7,
    };

    final res = await _client.post(
      Uri.parse(_endpoint),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $_apiKey",
      },
      body: jsonEncode(body),
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final json = jsonDecode(res.body);
      final text =
          json['choices']?[0]?['message']?['content']?.toString() ?? '';
      return text.trim().isEmpty ? '—' : text.trim();
    } else {
      return 'ขออภัย ไม่สามารถเรียกใช้ผู้ช่วยอัตโนมัติได้ในขณะนี้';
    }
  }

  /// แนะนำ “เทมเพลตถัดไป” แบบเรียบง่ายตามผลลัพธ์
  Future<String> suggestNextTemplate({
    required String currentTemplate, // fish/pencil/icecream
    required double zSum,
    required double cotl,
    required double blank,
  }) async {
    // กติกาเบื้องต้น: ถ้าทำได้ดี → เพิ่มความท้าทาย, ถ้าเลอะนอกเส้นมาก → เสนอที่เส้นหนา/ง่ายขึ้น
    final rule = () {
      final t = currentTemplate.toLowerCase();
      if (zSum >= 1.0 && cotl <= 0.2 && blank >= 0.4) {
        // ดีมาก → เพิ่มดีเทลเส้นตรง (ดินสอ) หรือเส้นโค้ง (ปลา)
        return t == 'icecream' ? 'ดินสอ' : 'ปลา';
      }
      if (cotl > 0.35) {
        // เลอะนอกเส้น → กลับไปเทมเพลตเส้นหนา/เรียบ
        return 'ไอศกรีม';
      }
      // กลาง ๆ → สลับไปอีกชนิดเพื่อฝึกความหลากหลาย
      if (t == 'fish') return 'ดินสอ';
      if (t == 'pencil') return 'ไอศกรีม';
      return 'ปลา';
    }();

    // ถ้าอยากให้ LLM ช่วย “เขียนคำอธิบายสั้น ๆ” ประกอบ:
    final prompt =
        '''
โปรดอธิบายเหตุผลสั้น ๆ (ไม่เกิน 2 ประโยค) ว่าทำไมควรแนะนำเทมเพลต "$rule" ต่อไป
เงื่อนไข: zSum=$zSum, COTL=$cotl, Blank=$blank
โทน: เป็นกันเอง ให้กำลังใจ
''';

    final body = {
      "model": "gpt-4o-mini",
      "messages": [
        {
          "role": "system",
          "content":
              "You recommend the next coloring template for a child kindly and precisely.",
        },
        {"role": "user", "content": prompt},
      ],
      "temperature": 0.6,
    };

    try {
      final res = await _client.post(
        Uri.parse(_endpoint),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $_apiKey",
        },
        body: jsonEncode(body),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final json = jsonDecode(res.body);
        final desc =
            json['choices']?[0]?['message']?['content']?.toString() ?? '';
        return 'แนะนำเทมเพลตถัดไป: $rule\n$desc';
      }
    } catch (_) {}
    return 'แนะนำเทมเพลตถัดไป: $rule';
  }
}
