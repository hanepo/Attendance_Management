import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/class_model.dart';
import '../models/session_model.dart';
import '../models/attendance_model.dart';
import '../models/enrollment_model.dart';
import 'encryption_service.dart';

/// All PII fields are AES-256 encrypted before writing to Firestore.
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final EncryptionService _enc = EncryptionService();

  String _e(String v) => _enc.encrypt(v);
  String _d(String v) => _enc.decrypt(v);
  String? _eN(String? v) => v == null || v.isEmpty ? null : _enc.encrypt(v);
  String? _dN(String? v) => v == null || v.isEmpty ? null : _enc.decrypt(v);

  // ─── Collections ─────────────────────────────────────────────────────────
  CollectionReference get _users => _firestore.collection('users');
  CollectionReference get _classes => _firestore.collection('classes');
  CollectionReference get _sessions => _firestore.collection('sessions');
  CollectionReference get _attendance => _firestore.collection('attendance');
  CollectionReference get _enrollments => _firestore.collection('enrollments');

  // ─── Users ────────────────────────────────────────────────────────────────
  Future<void> insertUser(UserModel user) async {
    await _users.doc(user.uid).set(_encryptUser(user.toMap(), user));
  }

  Future<UserModel?> getUserByUid(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return _decryptUser(doc.data() as Map<String, dynamic>);
  }

  /// Returns the raw (still-encrypted) Firestore document for display in
  /// the Encryption Demo screen.
  Future<Map<String, dynamic>?> rawUserDoc(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return doc.data() as Map<String, dynamic>;
  }

  Future<List<UserModel>> getAllUsers() async {
    final snapshot = await _users.orderBy('created_at', descending: false).get();
    return snapshot.docs
        .map((d) => _decryptUser(d.data() as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateUserFaceData(String uid, String faceData) async {
    await _users.doc(uid).update({'face_data': faceData});
  }

  Future<void> updateUserProfile(
    String uid, {
    String? name,
    String? icNumber,
    String? matrixNumber,
    String? profilePicture,
    String? role,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = _e(name);
    if (icNumber != null) data['ic_number'] = _eN(icNumber);
    if (matrixNumber != null) data['matrix_number'] = _eN(matrixNumber);
    if (profilePicture != null) data['profile_picture'] = profilePicture; // already encrypted
    if (role != null) data['role'] = role;
    if (data.isNotEmpty) await _users.doc(uid).update(data);
  }

  Future<void> deleteUser(String uid) async {
    final batch = _firestore.batch();
    batch.delete(_users.doc(uid));
    final enrollments = await _enrollments.where('user_uid', isEqualTo: uid).get();
    for (final d in enrollments.docs) {
      batch.delete(d.reference);
    }
    final att = await _attendance.where('user_uid', isEqualTo: uid).get();
    for (final d in att.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  Map<String, dynamic> _encryptUser(Map<String, dynamic> data, UserModel user) {
    return {
      ...data,
      'name': _e(user.name),
      'email': _e(user.email),
      'ic_number': _eN(user.icNumber),
      'matrix_number': _eN(user.matrixNumber),
    };
  }

  UserModel _decryptUser(Map<String, dynamic> data) {
    return UserModel.fromMap({
      ...data,
      'name': _d(data['name'] as String? ?? ''),
      'email': _d(data['email'] as String? ?? ''),
      'ic_number': _dN(data['ic_number'] as String?),
      'matrix_number': _dN(data['matrix_number'] as String?),
    });
  }

  // ─── Classes ─────────────────────────────────────────────────────────────
  Future<void> insertClass(ClassModel cls) async {
    final data = cls.toMap()
      ..['class_name'] = _e(cls.className)
      ..['admin_name'] = _e(cls.adminName);
    await _classes.doc(cls.classId).set(data);
  }

  Future<void> updateClass(String classId, String className) async {
    await _classes.doc(classId).update({'class_name': _e(className)});
  }

  Future<void> deleteClass(String classId) async {
    // Delete sessions
    final sessions = await _sessions.where('class_id', isEqualTo: classId).get();
    for (final s in sessions.docs) {
      await deleteSession(s.id);
    }
    // Delete enrollments
    final enrollments = await _enrollments.where('class_id', isEqualTo: classId).get();
    final batch = _firestore.batch();
    for (final d in enrollments.docs) {
      batch.delete(d.reference);
    }
    batch.delete(_classes.doc(classId));
    await batch.commit();
  }

  Future<List<ClassModel>> getClassesByAdmin(String adminUid) async {
    final snapshot = await _classes
        .where('admin_uid', isEqualTo: adminUid)
        .get();
    final list = snapshot.docs
        .map((d) => _decryptClass(d.data() as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<List<ClassModel>> getAllClasses() async {
    final snapshot = await _classes.orderBy('created_at', descending: true).get();
    return snapshot.docs.map((d) => _decryptClass(d.data() as Map<String, dynamic>)).toList();
  }

  Future<ClassModel?> getClassByCode(String code) async {
    final snapshot = await _classes.where('class_code', isEqualTo: code).limit(1).get();
    if (snapshot.docs.isEmpty) return null;
    return _decryptClass(snapshot.docs.first.data() as Map<String, dynamic>);
  }

  Future<ClassModel?> getClassById(String classId) async {
    final doc = await _classes.doc(classId).get();
    if (!doc.exists) return null;
    return _decryptClass(doc.data() as Map<String, dynamic>);
  }

  ClassModel _decryptClass(Map<String, dynamic> data) => ClassModel.fromMap({
        ...data,
        'class_name': _d(data['class_name'] as String? ?? ''),
        'admin_name': _d(data['admin_name'] as String? ?? ''),
      });

  // ─── Sessions ─────────────────────────────────────────────────────────────
  Future<void> insertSession(SessionModel session) async {
    final data = session.toMap()..['session_name'] = _e(session.sessionName);
    await _sessions.doc(session.sessionId).set(data);
  }

  Future<void> updateSession(
    String sessionId, {
    String? sessionName,
    DateTime? startTime,
    DateTime? endTime,
    bool? isActive,
  }) async {
    final data = <String, dynamic>{};
    if (sessionName != null) data['session_name'] = _e(sessionName);
    if (startTime != null) data['start_time'] = startTime.toIso8601String();
    if (endTime != null) data['end_time'] = endTime.toIso8601String();
    if (isActive != null) data['is_active'] = isActive ? 1 : 0;
    if (data.isNotEmpty) await _sessions.doc(sessionId).update(data);
  }

  Future<void> deleteSession(String sessionId) async {
    final att = await _attendance.where('session_id', isEqualTo: sessionId).get();
    final batch = _firestore.batch();
    for (final d in att.docs) {
      batch.delete(d.reference);
    }
    batch.delete(_sessions.doc(sessionId));
    await batch.commit();
  }

  Future<List<SessionModel>> getSessionsByClass(String classId) async {
    final snapshot = await _sessions
        .where('class_id', isEqualTo: classId)
        .get();
    final list = snapshot.docs
        .map((d) => _decryptSession(d.data() as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.startTime.compareTo(a.startTime));
    return list;
  }

  Future<List<SessionModel>> getActiveSessionsByClass(String classId) async {
    final snapshot = await _sessions
        .where('class_id', isEqualTo: classId)
        .where('is_active', isEqualTo: 1)
        .get();
    return snapshot.docs.map((d) => _decryptSession(d.data() as Map<String, dynamic>)).toList();
  }

  Future<SessionModel?> getSessionById(String sessionId) async {
    final doc = await _sessions.doc(sessionId).get();
    if (!doc.exists) return null;
    return _decryptSession(doc.data() as Map<String, dynamic>);
  }

  Future<SessionModel?> getSessionByQrData(String qrData) async {
    final snapshot = await _sessions.where('qr_data', isEqualTo: qrData).limit(1).get();
    if (snapshot.docs.isEmpty) return null;
    return _decryptSession(snapshot.docs.first.data() as Map<String, dynamic>);
  }

  SessionModel _decryptSession(Map<String, dynamic> data) => SessionModel.fromMap({
        ...data,
        'session_name': _d(data['session_name'] as String? ?? ''),
      });

  // ─── Attendance ───────────────────────────────────────────────────────────
  Future<void> insertAttendance(AttendanceModel attendance) async {
    final data = attendance.toMap()
      ..['user_name'] = _e(attendance.userName)
      ..['user_email'] = _e(attendance.userEmail);
    await _attendance.doc(attendance.attendanceId).set(data);
  }

  Future<List<AttendanceModel>> getAttendanceBySession(String sessionId) async {
    final snapshot = await _attendance
        .where('session_id', isEqualTo: sessionId)
        .get();
    final list = snapshot.docs
        .map((d) => _decryptAttendance(d.data() as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Future<List<AttendanceModel>> getAttendanceByClass(String classId) async {
    final snapshot = await _attendance
        .where('class_id', isEqualTo: classId)
        .get();
    final list = snapshot.docs
        .map((d) => _decryptAttendance(d.data() as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Future<bool> hasAttendance(String sessionId, String userUid) async {
    final snapshot = await _attendance
        .where('session_id', isEqualTo: sessionId)
        .where('user_uid', isEqualTo: userUid)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  Future<List<AttendanceModel>> getAttendanceByUser(String userUid) async {
    final snapshot = await _attendance
        .where('user_uid', isEqualTo: userUid)
        .get();
    final list = snapshot.docs
        .map((d) => _decryptAttendance(d.data() as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  AttendanceModel _decryptAttendance(Map<String, dynamic> data) =>
      AttendanceModel.fromMap({
        ...data,
        'user_name': _d(data['user_name'] as String? ?? ''),
        'user_email': _d(data['user_email'] as String? ?? ''),
      });

  // ─── Enrollments ──────────────────────────────────────────────────────────
  Future<void> insertEnrollment(EnrollmentModel enrollment) async {
    final docId = '${enrollment.classId}_${enrollment.userUid}';
    final data = enrollment.toMap()
      ..['user_name'] = _e(enrollment.userName)
      ..['user_email'] = _e(enrollment.userEmail);
    await _enrollments.doc(docId).set(data);
  }

  Future<void> removeEnrollment(String classId, String userUid) async {
    final docId = '${classId}_$userUid';
    await _enrollments.doc(docId).delete();
  }

  Future<List<EnrollmentModel>> getEnrollmentsByUser(String userUid) async {
    final snapshot = await _enrollments.where('user_uid', isEqualTo: userUid).get();
    return snapshot.docs.map((d) => _decryptEnrollment(d.data() as Map<String, dynamic>)).toList();
  }

  Future<List<EnrollmentModel>> getEnrollmentsByClass(String classId) async {
    final snapshot = await _enrollments.where('class_id', isEqualTo: classId).get();
    return snapshot.docs.map((d) => _decryptEnrollment(d.data() as Map<String, dynamic>)).toList();
  }

  Future<bool> isEnrolled(String classId, String userUid) async {
    final docId = '${classId}_$userUid';
    final doc = await _enrollments.doc(docId).get();
    return doc.exists;
  }

  Future<List<ClassModel>> getEnrolledClasses(String userUid) async {
    final enrollments = await getEnrollmentsByUser(userUid);
    if (enrollments.isEmpty) return [];
    final futures = enrollments.map((e) => getClassById(e.classId));
    final classes = await Future.wait(futures);
    return classes.whereType<ClassModel>().toList();
  }

  EnrollmentModel _decryptEnrollment(Map<String, dynamic> data) =>
      EnrollmentModel.fromMap({
        ...data,
        'user_name': _d(data['user_name'] as String? ?? ''),
        'user_email': _d(data['user_email'] as String? ?? ''),
      });
}
