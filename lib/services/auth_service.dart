import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image/image.dart' as imglib;
import '../models/user_model.dart';
import 'database_service.dart';
import 'encryption_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _auth = FirebaseAuth.instance;
  final _db = DatabaseService();
  final _enc = EncryptionService();

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;

  Future<void> init() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) {
      _currentUser = await _db.getUserByUid(firebaseUser.uid);
      if (_currentUser == null) {
        // Profile deleted by admin — sign out
        await _auth.signOut();
      }
    }
  }

  Future<String?> register({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = credential.user!.uid;
      final user = UserModel(
        uid: uid,
        name: name,
        email: email.toLowerCase().trim(),
        passwordHash: '',
        role: role,
        createdAt: DateTime.now(),
      );
      await _db.insertUser(user);
      _currentUser = user;
      return null;
    } on FirebaseAuthException catch (e) {
      return _authError(e.code);
    } catch (e) {
      return 'Registration failed: $e';
    }
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = credential.user!.uid;
      _currentUser = await _db.getUserByUid(uid);
      if (_currentUser == null) {
        await _auth.signOut();
        return 'Account not found. Please contact administrator.';
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return _authError(e.code);
    } catch (e) {
      return 'Login failed: $e';
    }
  }

  Future<void> logout() async {
    _currentUser = null;
    await _auth.signOut();
  }

  Future<void> updateFaceData(String faceData) async {
    if (_currentUser == null) return;
    final encrypted = _enc.encryptFaceData(faceData);
    await _db.updateUserFaceData(_currentUser!.uid, encrypted);
    _currentUser = _currentUser!.copyWith(faceData: encrypted);
  }

  /// Update profile fields. Pass null to leave unchanged.
  Future<String?> updateProfile({
    String? name,
    String? icNumber,
    String? matrixNumber,
    Uint8List? profileImageBytes,
  }) async {
    if (_currentUser == null) return 'Not logged in';
    try {
      String? encryptedPicture;
      if (profileImageBytes != null) {
        // Resize to 200x200 and convert to JPEG
        var img = imglib.decodeImage(profileImageBytes);
        if (img != null) {
          img = imglib.copyResize(img, width: 200, height: 200);
          final jpeg = imglib.encodeJpg(img, quality: 80);
          final b64 = base64Encode(jpeg);
          encryptedPicture = _enc.encrypt(b64);
        }
      }
      await _db.updateUserProfile(
        _currentUser!.uid,
        name: name,
        icNumber: icNumber,
        matrixNumber: matrixNumber,
        profilePicture: encryptedPicture,
      );
      _currentUser = _currentUser!.copyWith(
        name: name ?? _currentUser!.name,
        icNumber: icNumber ?? _currentUser!.icNumber,
        matrixNumber: matrixNumber ?? _currentUser!.matrixNumber,
        profilePicture: encryptedPicture ?? _currentUser!.profilePicture,
      );
      return null;
    } catch (e) {
      return 'Update failed: $e';
    }
  }

  /// Decode and decrypt the stored profile picture to raw bytes.
  Uint8List? getProfileImageBytes() {
    final pic = _currentUser?.profilePicture;
    if (pic == null || pic.isEmpty) return null;
    try {
      final b64 = _enc.decrypt(pic);
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  bool get hasFaceRegistered =>
      _currentUser?.faceData != null && _currentUser!.faceData!.isNotEmpty;

  String _authError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered';
      case 'invalid-email':
        return 'Invalid email address';
      case 'weak-password':
        return 'Password must be at least 6 characters';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later';
      case 'network-request-failed':
        return 'Network error. Check your internet connection';
      default:
        return 'Authentication error: $code';
    }
  }
}
