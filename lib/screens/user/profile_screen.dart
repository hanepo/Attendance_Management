import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/auth_service.dart';
import '../../utils/constants.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _icCtrl;
  late final TextEditingController _matrixCtrl;
  bool _saving = false;
  Uint8List? _newImageBytes;

  @override
  void initState() {
    super.initState();
    final u = _auth.currentUser!;
    _nameCtrl = TextEditingController(text: u.name);
    _icCtrl = TextEditingController(text: u.icNumber ?? '');
    _matrixCtrl = TextEditingController(text: u.matrixNumber ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _icCtrl.dispose();
    _matrixCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final result = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 400,
      maxHeight: 400,
      imageQuality: 85,
    );
    if (result == null) return;
    final bytes = await result.readAsBytes();
    setState(() => _newImageBytes = bytes);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final error = await _auth.updateProfile(
      name: _nameCtrl.text.trim(),
      icNumber: _icCtrl.text.trim(),
      matrixNumber: _matrixCtrl.text.trim(),
      profileImageBytes: _newImageBytes,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      _showSnack(error, isError: true);
    } else {
      _newImageBytes = null;
      _showSnack('Profile updated successfully');
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser!;
    final storedImageBytes = _auth.getProfileImageBytes();
    final displayBytes = _newImageBytes ?? storedImageBytes;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Profile Picture
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 54,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                      backgroundImage: displayBytes != null
                          ? MemoryImage(displayBytes)
                          : null,
                      child: displayBytes == null
                          ? Text(
                              user.name.isNotEmpty
                                  ? user.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(user.email,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: (user.role == AppStrings.roleAdmin
                          ? AppColors.accent
                          : AppColors.primary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  user.role == AppStrings.roleAdmin ? 'Admin' : 'Student',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: user.role == AppStrings.roleAdmin
                        ? AppColors.accent
                        : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Form fields
              _buildSection('Personal Information', [
                _buildField(
                  controller: _nameCtrl,
                  label: 'Full Name',
                  icon: Icons.person_outline,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 14),
                _buildField(
                  controller: _icCtrl,
                  label: 'IC Number',
                  icon: Icons.credit_card_outlined,
                  hint: 'e.g. 990101-12-3456',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 14),
                _buildField(
                  controller: _matrixCtrl,
                  label: 'Matrix Number',
                  icon: Icons.badge_outlined,
                  hint: 'e.g. CS2101001',
                ),
              ]),
              const SizedBox(height: 20),

              // Face status
              _buildSection('Biometric Status', [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: _auth.hasFaceRegistered
                        ? AppColors.success.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    child: Icon(
                      _auth.hasFaceRegistered
                          ? Icons.check_circle
                          : Icons.warning_amber,
                      color: _auth.hasFaceRegistered
                          ? AppColors.success
                          : Colors.orange,
                    ),
                  ),
                  title: Text(
                    _auth.hasFaceRegistered
                        ? 'Face Registered'
                        : 'Face Not Registered',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _auth.hasFaceRegistered
                        ? 'Your face is enrolled for attendance'
                        : 'Register your face to mark attendance',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ]),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Save Changes',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.5)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider.withValues(alpha: 0.5)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
