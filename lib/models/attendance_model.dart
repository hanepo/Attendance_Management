class AttendanceModel {
  final int? id;
  final String attendanceId;
  final String sessionId;
  final String classId;
  final String userUid;
  final String userName;
  final String userEmail;
  final String encryptedData;
  final DateTime timestamp;
  final String status;

  AttendanceModel({
    this.id,
    required this.attendanceId,
    required this.sessionId,
    required this.classId,
    required this.userUid,
    required this.userName,
    required this.userEmail,
    required this.encryptedData,
    required this.timestamp,
    required this.status,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'attendance_id': attendanceId,
        'session_id': sessionId,
        'class_id': classId,
        'user_uid': userUid,
        'user_name': userName,
        'user_email': userEmail,
        'encrypted_data': encryptedData,
        'timestamp': timestamp.toIso8601String(),
        'status': status,
      };

  factory AttendanceModel.fromMap(Map<String, dynamic> map) => AttendanceModel(
        id: map['id'],
        attendanceId: map['attendance_id'],
        sessionId: map['session_id'],
        classId: map['class_id'],
        userUid: map['user_uid'],
        userName: map['user_name'],
        userEmail: map['user_email'],
        encryptedData: map['encrypted_data'],
        timestamp: DateTime.parse(map['timestamp']),
        status: map['status'],
      );
}
