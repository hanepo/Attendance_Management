class ClassModel {
  final int? id;
  final String classId;
  final String className;
  final String classCode;
  final String adminUid;
  final String adminName;
  final DateTime createdAt;

  ClassModel({
    this.id,
    required this.classId,
    required this.className,
    required this.classCode,
    required this.adminUid,
    required this.adminName,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'class_id': classId,
        'class_name': className,
        'class_code': classCode,
        'admin_uid': adminUid,
        'admin_name': adminName,
        'created_at': createdAt.toIso8601String(),
      };

  factory ClassModel.fromMap(Map<String, dynamic> map) => ClassModel(
        id: map['id'],
        classId: map['class_id'],
        className: map['class_name'],
        classCode: map['class_code'],
        adminUid: map['admin_uid'],
        adminName: map['admin_name'],
        createdAt: DateTime.parse(map['created_at']),
      );
}
