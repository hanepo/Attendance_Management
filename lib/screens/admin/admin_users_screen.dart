import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/attendance_service.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../utils/constants.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _db = DatabaseService();
  final _svc = AttendanceService();
  List<UserModel> _users = [];
  List<UserModel> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final users = await _db.getAllUsers();
    if (mounted) {
      setState(() {
        _users = users;
        _filtered = users;
        _loading = false;
      });
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _users
          : _users
              .where((u) =>
                  u.name.toLowerCase().contains(q) ||
                  u.email.toLowerCase().contains(q) ||
                  (u.matrixNumber ?? '').toLowerCase().contains(q))
              .toList();
    });
  }

  Future<void> _editUser(UserModel user) async {
    final nameCtrl = TextEditingController(text: user.name);
    final icCtrl = TextEditingController(text: user.icNumber ?? '');
    final matrixCtrl = TextEditingController(text: user.matrixNumber ?? '');
    String selectedRole = user.role;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Edit User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Full Name', prefixIcon: Icon(Icons.person)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: icCtrl,
                  decoration: const InputDecoration(
                      labelText: 'IC Number',
                      prefixIcon: Icon(Icons.credit_card)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: matrixCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Matrix Number',
                      prefixIcon: Icon(Icons.badge)),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'user', child: Text('Student')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (v) => setSt(() => selectedRole = v ?? 'user'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true) return;
    await _db.updateUserProfile(
      user.uid,
      name: nameCtrl.text.trim(),
      icNumber: icCtrl.text.trim(),
      matrixNumber: matrixCtrl.text.trim(),
      role: selectedRole,
    );
    _load();
  }

  Future<void> _deleteUser(UserModel user) async {
    final selfUid = AuthService().currentUser?.uid;
    if (user.uid == selfUid) {
      _showSnack('Cannot delete your own account');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
            'Delete "${user.name}"? This will remove all their enrollments and attendance records.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final err = await _svc.deleteUser(user.uid);
    if (err != null) {
      _showSnack(err, isError: true);
    } else {
      _showSnack('User deleted');
      _load();
    }
  }

  Future<void> _viewUserDetail(UserModel user) async {
    final attendance = await _db.getAttendanceByUser(user.uid);
    final enrollments = await _db.getEnrollmentsByUser(user.uid);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scroll) => Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            controller: scroll,
            children: [
              Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              _infoRow(Icons.person, 'Name', user.name),
              _infoRow(Icons.email, 'Email', user.email),
              if (user.icNumber?.isNotEmpty == true)
                _infoRow(Icons.credit_card, 'IC Number', user.icNumber!),
              if (user.matrixNumber?.isNotEmpty == true)
                _infoRow(Icons.badge, 'Matrix Number', user.matrixNumber!),
              _infoRow(Icons.manage_accounts, 'Role',
                  user.role == 'admin' ? 'Admin' : 'Student'),
              _infoRow(Icons.class_, 'Classes Enrolled',
                  '${enrollments.length} classes'),
              _infoRow(Icons.check_circle, 'Total Attendance',
                  '${attendance.length} records'),
              _infoRow(Icons.face, 'Face Registered',
                  (user.faceData?.isNotEmpty == true) ? 'Yes' : 'No'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Text('$label: ',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
          ),
        ],
      ),
    );
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
    final students = _filtered.where((u) => u.role != 'admin').length;
    final admins = _filtered.where((u) => u.role == 'admin').length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Manage Users'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
              tooltip: 'Refresh'),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            color: AppColors.primary,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                _statChip(Icons.people, '$students Students'),
                const SizedBox(width: 10),
                _statChip(Icons.admin_panel_settings, '$admins Admins'),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by name, email or matrix number…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _filter();
                        })
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline,
                                size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('No users found',
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 15)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _filtered.length,
          separatorBuilder: (_, i) => const SizedBox(height: 6),
                          itemBuilder: (ctx, i) =>
                              _UserTile(
                            user: _filtered[i],
                            onEdit: () => _editUser(_filtered[i]),
                            onDelete: () => _deleteUser(_filtered[i]),
                            onView: () => _viewUserDetail(_filtered[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final UserModel user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onView;

  const _UserTile({
    required this.user,
    required this.onEdit,
    required this.onDelete,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin = user.role == 'admin';
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onView,
        leading: CircleAvatar(
          backgroundColor: isAdmin
              ? AppColors.accent.withValues(alpha: 0.15)
              : AppColors.primary.withValues(alpha: 0.12),
          child: Text(
            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isAdmin ? AppColors.accent : AppColors.primary),
          ),
        ),
        title: Text(user.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.email,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            if (user.matrixNumber?.isNotEmpty == true)
              Text('Matrix: ${user.matrixNumber}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isAdmin
                    ? AppColors.accent.withValues(alpha: 0.1)
                    : AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isAdmin ? 'Admin' : 'Student',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isAdmin ? AppColors.accent : AppColors.primary),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Edit')
                    ])),
                const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red))
                    ])),
              ],
            ),
          ],
        ),
        isThreeLine: user.matrixNumber?.isNotEmpty == true,
      ),
    );
  }
}
