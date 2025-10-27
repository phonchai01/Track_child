class ChildProfile {
  final String name; // ชื่อเด็ก (unique แบบง่าย ๆ)
  final int age;     // 4 หรือ 5

  const ChildProfile({required this.name, required this.age});

  factory ChildProfile.fromJson(Map<String, dynamic> m) =>
      ChildProfile(name: (m['name'] ?? '').toString(), age: int.tryParse('${m['age']}') ?? 4);

  Map<String, dynamic> toJson() => {'name': name, 'age': age};
}
