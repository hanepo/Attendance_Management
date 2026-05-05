import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/attendance_model.dart';
import '../models/class_model.dart';
import '../models/enrollment_model.dart';
import '../models/session_model.dart';
import '../models/user_model.dart';
import 'database_service.dart';
import 'encryption_service.dart';

class AttendanceService {
  static final AttendanceService _instance = AttendanceService._internal();
  factory AttendanceService() => _instance;
  AttendanceService._internal();

  final _db = DatabaseService();
  final _enc = EncryptionService();
  final _uuid = const Uuid();

  Future<String> createClass({
    required String className,
    required UserModel admin,
  }) async {
    final classId = _uuid.v4();
    final classCode = _generateClassCode();
    final cls = ClassModel(
      classId: classId,
      className: className,
      classCode: classCode,
      adminUid: admin.uid,
      adminName: admin.name,
      createdAt: DateTime.now(),
    );
    await _db.insertClass(cls);
    return classId;
  }

  Future<SessionModel> createSession({
    required String classId,
    required String sessionName,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final sessionId = _uuid.v4();
    final qrData = jsonEncode({
      'sessionId': sessionId,
      'classId': classId,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    final session = SessionModel(
      sessionId: sessionId,
      classId: classId,
      sessionName: sessionName,
      qrData: qrData,
      startTime: startTime,
      endTime: endTime,
      isActive: true,
    );
    await _db.insertSession(session);
    return session;
  }

  Future<String?> joinClass(String classCode, UserModel user) async {
    final cls = await _db.getClassByCode(classCode.trim().toUpperCase());
    if (cls == null) return 'Invalid class code';
    final enrolled = await _db.isEnrolled(cls.classId, user.uid);
    if (enrolled) return 'Already enrolled in this class';
    final enrollment = EnrollmentModel(
      classId: cls.classId,
      userUid: user.uid,
      userName: user.name,
      userEmail: user.email,
      enrolledAt: DateTime.now(),
    );
    await _db.insertEnrollment(enrollment);
    return null;
  }

  Future<String?> submitAttendance({
    required SessionModel session,
    required UserModel user,
  }) async {
    if (!session.isCurrentlyActive) {
      return 'This session is not currently active';
    }
    final alreadyMarked =
        await _db.hasAttendance(session.sessionId, user.uid);
    if (alreadyMarked) return 'Attendance already recorded for this session';

    final isEnrolled =
        await _db.isEnrolled(session.classId, user.uid);
    if (!isEnrolled) return 'You are not enrolled in this class';

    final rawData = jsonEncode({
      'userId': user.uid,
      'userName': user.name,
      'userEmail': user.email,
      'sessionId': session.sessionId,
      'classId': session.classId,
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'present',
    });

    final encryptedData = _enc.encrypt(rawData);

    final attendance = AttendanceModel(
      attendanceId: _uuid.v4(),
      sessionId: session.sessionId,
      classId: session.classId,
      userUid: user.uid,
      userName: user.name,
      userEmail: user.email,
      encryptedData: encryptedData,
      timestamp: DateTime.now(),
      status: 'present',
    );

    await _db.insertAttendance(attendance);
    return null;
  }

  Future<List<ClassModel>> getAdminClasses(String adminUid) =>
      _db.getClassesByAdmin(adminUid);

  Future<List<ClassModel>> getAllClasses() => _db.getAllClasses();

  Future<List<ClassModel>> getUserClasses(String userUid) =>
      _db.getEnrolledClasses(userUid);

  Future<List<SessionModel>> getClassSessions(String classId) =>
      _db.getSessionsByClass(classId);

  Future<String?> updateClass(String classId, String className) async {
    try {
      await _db.updateClass(classId, className);
      return null;
    } catch (e) {
      return 'Failed to update class: $e';
    }
  }

  Future<String?> deleteClass(String classId) async {
    try {
      await _db.deleteClass(classId);
      return null;
    } catch (e) {
      return 'Failed to delete class: $e';
    }
  }

  Future<String?> updateSession(
    String sessionId, {
    String? sessionName,
    DateTime? startTime,
    DateTime? endTime,
    bool? isActive,
  }) async {
    try {
      await _db.updateSession(sessionId,
          sessionName: sessionName,
          startTime: startTime,
          endTime: endTime,
          isActive: isActive);
      return null;
    } catch (e) {
      return 'Failed to update session: $e';
    }
  }

  Future<String?> deleteSession(String sessionId) async {
    try {
      await _db.deleteSession(sessionId);
      return null;
    } catch (e) {
      return 'Failed to delete session: $e';
    }
  }

  Future<String?> removeStudentFromClass(
      String classId, String userUid) async {
    try {
      await _db.removeEnrollment(classId, userUid);
      return null;
    } catch (e) {
      return 'Failed to remove student: $e';
    }
  }

  Future<String?> deleteUser(String uid) async {
    try {
      await _db.deleteUser(uid);
      return null;
    } catch (e) {
      return 'Failed to delete user: $e';
    }
  }

  /// Returns all currently-active sessions across every class the user is enrolled in.
  Future<List<({ClassModel cls, SessionModel session})>> getActiveSessionsForUser(
      String userUid) async {
    final classes = await _db.getEnrolledClasses(userUid);
    final result = <({ClassModel cls, SessionModel session})>[];
    for (final cls in classes) {
      final sessions = await _db.getActiveSessionsByClass(cls.classId);
      for (final s in sessions) {
        if (s.isCurrentlyActive) result.add((cls: cls, session: s));
      }
    }
    return result;
  }

  Future<List<AttendanceModel>> getSessionAttendance(String sessionId) =>
      _db.getAttendanceBySession(sessionId);

  Future<List<AttendanceModel>> getClassAttendance(String classId) =>
      _db.getAttendanceByClass(classId);

  Future<List<AttendanceModel>> getUserAttendance(String userUid) =>
      _db.getAttendanceByUser(userUid);

  Future<SessionModel?> resolveSession(String qrData) async {
    try {
      final data = jsonDecode(qrData) as Map<String, dynamic>;
      final sessionId = data['sessionId'] as String?;
      if (sessionId == null) return null;
      return _db.getSessionById(sessionId);
    } catch (_) {
      return _db.getSessionByQrData(qrData);
    }
  }

  Future<ClassModel?> getClassById(String classId) =>
      _db.getClassById(classId);

  String _generateClassCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = DateTime.now().millisecondsSinceEpoch;
    final r = rand.toString();
    String code = '';
    for (int i = 0; i < 6; i++) {
      final idx = (r.codeUnitAt(i % r.length) + i) % chars.length;
      code += chars[idx];
    }
    return code;
  }
}
