import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import '../utils/constants.dart';

/// AES-256-CBC encryption with per-value random IV.
/// Stored format: base64(iv) + ':' + base64(ciphertext)
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  late final enc.Key _key;
  late final enc.IV _legacyIv;

  void init() {
    final keyBytes = utf8.encode(AppStrings.encryptionKey);
    final ivBytes = utf8.encode(AppStrings.encryptionIV);
    _key = enc.Key(Uint8List.fromList(keyBytes.take(32).toList()));
    _legacyIv = enc.IV(Uint8List.fromList(ivBytes.take(16).toList()));
  }

  /// Encrypts [plainText] with a fresh random IV. Returns "ivB64:ctB64".
  String encrypt(String plainText) {
    final iv = enc.IV.fromSecureRandom(16);
    final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '${iv.base64}:${encrypted.base64}';
  }

  /// Decrypts a value produced by [encrypt]. Falls back to legacy fixed-IV
  /// format for backward compatibility.
  String decrypt(String encryptedText) {
    try {
      final colonIdx = encryptedText.indexOf(':');
      if (colonIdx > 0) {
        final ivB64 = encryptedText.substring(0, colonIdx);
        final ctB64 = encryptedText.substring(colonIdx + 1);
        final iv = enc.IV.fromBase64(ivB64);
        final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));
        final encrypted = enc.Encrypted.fromBase64(ctB64);
        return encrypter.decrypt(encrypted, iv: iv);
      }
      // Legacy fixed-IV format
      final encrypter = enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc));
      final encrypted = enc.Encrypted.fromBase64(encryptedText);
      return encrypter.decrypt(encrypted, iv: _legacyIv);
    } catch (_) {
      return encryptedText;
    }
  }

  String hashPassword(String password) {
    final bytes = utf8.encode('${password}AttendanceSalt2024');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  bool verifyPassword(String password, String hash) =>
      hashPassword(password) == hash;

  String encryptFaceData(String faceData) => encrypt(faceData);

  String? decryptFaceData(String? encryptedFaceData) {
    if (encryptedFaceData == null || encryptedFaceData.isEmpty) return null;
    return decrypt(encryptedFaceData);
  }
}
