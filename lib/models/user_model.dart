class UserModel {
  final String uid;
  final String name;
  final String email;
  final String passwordHash;
  final String role;
  final String? faceData;
  final String? icNumber;
  final String? matrixNumber;
  final String? profilePicture; // AES-encrypted base64 JPEG
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.passwordHash,
    required this.role,
    this.faceData,
    this.icNumber,
    this.matrixNumber,
    this.profilePicture,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'email': email,
        'password_hash': passwordHash,
        'role': role,
        'face_data': faceData,
        'ic_number': icNumber,
        'matrix_number': matrixNumber,
        'profile_picture': profilePicture,
        'created_at': createdAt.toIso8601String(),
      };

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel(
        uid: map['uid'] as String? ?? '',
        name: map['name'] as String? ?? '',
        email: map['email'] as String? ?? '',
        passwordHash: map['password_hash'] as String? ?? '',
        role: map['role'] as String? ?? 'user',
        faceData: map['face_data'] as String?,
        icNumber: map['ic_number'] as String?,
        matrixNumber: map['matrix_number'] as String?,
        profilePicture: map['profile_picture'] as String?,
        createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? passwordHash,
    String? role,
    String? faceData,
    String? icNumber,
    String? matrixNumber,
    String? profilePicture,
    DateTime? createdAt,
  }) =>
      UserModel(
        uid: uid ?? this.uid,
        name: name ?? this.name,
        email: email ?? this.email,
        passwordHash: passwordHash ?? this.passwordHash,
        role: role ?? this.role,
        faceData: faceData ?? this.faceData,
        icNumber: icNumber ?? this.icNumber,
        matrixNumber: matrixNumber ?? this.matrixNumber,
        profilePicture: profilePicture ?? this.profilePicture,
        createdAt: createdAt ?? this.createdAt,
      );
}
