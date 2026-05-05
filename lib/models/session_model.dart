class SessionModel {
  final int? id;
  final String sessionId;
  final String classId;
  final String sessionName;
  final String qrData;
  final DateTime startTime;
  final DateTime endTime;
  final bool isActive;

  SessionModel({
    this.id,
    required this.sessionId,
    required this.classId,
    required this.sessionName,
    required this.qrData,
    required this.startTime,
    required this.endTime,
    required this.isActive,
  });

  bool get isCurrentlyActive {
    final now = DateTime.now();
    return isActive && now.isAfter(startTime) && now.isBefore(endTime);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'class_id': classId,
        'session_name': sessionName,
        'qr_data': qrData,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'is_active': isActive ? 1 : 0,
      };

  factory SessionModel.fromMap(Map<String, dynamic> map) => SessionModel(
        id: map['id'],
        sessionId: map['session_id'],
        classId: map['class_id'],
        sessionName: map['session_name'],
        qrData: map['qr_data'],
        startTime: DateTime.parse(map['start_time']),
        endTime: DateTime.parse(map['end_time']),
        isActive: map['is_active'] == 1,
      );
}
