class EnrollmentModel {
  final int? id;
  final String classId;
  final String userUid;
  final String userName;
  final String userEmail;
  final DateTime enrolledAt;

  EnrollmentModel({
    this.id,
    required this.classId,
    required this.userUid,
    required this.userName,
    required this.userEmail,
    required this.enrolledAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'class_id': classId,
        'user_uid': userUid,
        'user_name': userName,
        'user_email': userEmail,
        'enrolled_at': enrolledAt.toIso8601String(),
      };

  factory EnrollmentModel.fromMap(Map<String, dynamic> map) => EnrollmentModel(
        id: map['id'],
        classId: map['class_id'],
        userUid: map['user_uid'],
        userName: map['user_name'],
        userEmail: map['user_email'],
        enrolledAt: DateTime.parse(map['enrolled_at']),
      );
}
