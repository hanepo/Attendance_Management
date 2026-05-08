import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/class_model.dart';
import '../../models/enrollment_model.dart';
import '../../models/session_model.dart';
import '../../services/attendance_service.dart';
import '../../services/database_service.dart';
import '../../utils/constants.dart';
import 'create_session_screen.dart';
import 'view_attendance_screen.dart';

class ClassDetailScreen extends StatefulWidget {
  final ClassModel classModel;
  const ClassDetailScreen({super.key, required this.classModel});

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen>
    with SingleTickerProviderStateMixin {
  final _svc = AttendanceService();
  final _db = DatabaseService();
  List<SessionModel> _sessions = [];
  List<EnrollmentModel> _enrollments = [];
  bool _loading = true;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sessions = await _svc.getClassSessions(widget.classModel.classId);
    final enrollments =
        await _db.getEnrollmentsByClass(widget.classModel.classId);
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _enrollments = enrollments;
        _loading = false;
      });
    }
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.classModel.classCode));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Class code copied'),
        duration: Duration(seconds: 2)));
  }

  Future<void> _editSession(SessionModel session) async {
    final nameCtrl = TextEditingController(text: session.sessionName);
    DateTime startTime = session.startTime;
    DateTime endTime = session.endTime;
    bool isActive = session.isActive;
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Edit Session'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Session Name'),
                ),
                const SizedBox(height: 14),
                _timePicker(
                  ctx,
                  'Start Time',
                  fmt.format(startTime),
                  () async {
                    final dt = await _pickDateTime(ctx, startTime);
                    if (dt != null) setSt(() => startTime = dt);
                  },
                ),
                const SizedBox(height: 8),
                _timePicker(
                  ctx,
                  'End Time',
                  fmt.format(endTime),
                  () async {
                    final dt = await _pickDateTime(ctx, endTime);
                    if (dt != null) setSt(() => endTime = dt);
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: isActive,
                  onChanged: (v) => setSt(() => isActive = v),
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
    final err = await _svc.updateSession(
      session.sessionId,
      sessionName: nameCtrl.text.trim(),
      startTime: startTime,
      endTime: endTime,
      isActive: isActive,
    );
    if (mounted) {
      _showSnack(err ?? 'Session updated');
      if (err == null) _load();
    }
  }

  Widget _timePicker(
      BuildContext ctx, String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.calendar_today, size: 18)),
        child: Text(value),
      ),
    );
  }

  Future<DateTime?> _pickDateTime(
      BuildContext ctx, DateTime initial) async {
    final date = await showDatePicker(
      context: ctx,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return null;
    if (!ctx.mounted) return null;
    final time = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _deleteSession(SessionModel session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Session'),
        content: Text(
            'Delete "${session.sessionName}"? All attendance records for this session will be removed.'),
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
    final err = await _svc.deleteSession(session.sessionId);
    if (mounted) {
      _showSnack(err ?? 'Session deleted');
      if (err == null) _load();
    }
  }

  Future<void> _removeStudent(EnrollmentModel enrollment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Student'),
        content: Text(
            'Remove "${enrollment.userName}" from this class?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final err = await _svc.removeStudentFromClass(
        enrollment.classId, enrollment.userUid);
    if (mounted) {
      _showSnack(err ?? 'Student removed');
      if (err == null) _load();
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final cls = widget.classModel;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(cls.className),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'View All Attendance',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => ViewAttendanceScreen(classModel: cls)),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.event_note, size: 18), text: 'Sessions'),
            Tab(icon: Icon(Icons.people, size: 18), text: 'Students'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Class info
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Class Code',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                            Text(cls.classCode,
                                style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                    letterSpacing: 5)),
                          ],
                        ),
                      ),
                      IconButton(
                          icon: const Icon(Icons.copy,
                              color: AppColors.primary),
                          onPressed: _copyCode,
                          tooltip: 'Copy code'),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final r = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      CreateSessionScreen(classModel: cls)));
                          if (r == true) _load();
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('New Session'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ),
                // Tab content
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _buildSessionsTab(),
                      _buildStudentsTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSessionsTab() {
    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_note, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No sessions yet',
                style: TextStyle(color: Colors.grey[500], fontSize: 15)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _sessions.length,
        separatorBuilder: (_, i) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final session = _sessions[i];
          final isActive = session.isCurrentlyActive;
          return Card(
            elevation: 1,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(session.sessionName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                      ),
                      _statusChip(isActive),
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _editSession(session);
                          if (v == 'delete') _deleteSession(session);
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
                                Icon(Icons.delete,
                                    size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete',
                                    style: TextStyle(color: Colors.red))
                              ])),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_fmtDt(session.startTime)} – ${_fmtDt(session.endTime)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ViewAttendanceScreen(
                                  classModel: widget.classModel,
                                  sessionId: session.sessionId,
                                ))),
                    icon: const Icon(Icons.list_alt, size: 16),
                    label: const Text('Attendance'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.accent),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      minimumSize: const Size(double.infinity, 36),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStudentsTab() {
    if (_enrollments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No students enrolled',
                style: TextStyle(color: Colors.grey[500], fontSize: 15)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _enrollments.length,
        separatorBuilder: (_, i) => const SizedBox(height: 6),
        itemBuilder: (ctx, i) {
          final e = _enrollments[i];
          return Card(
            elevation: 1,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: Text(
                  e.userName.isNotEmpty ? e.userName[0].toUpperCase() : '?',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
              title: Text(e.userName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(e.userEmail,
                  style: const TextStyle(fontSize: 12)),
              trailing: IconButton(
                icon: const Icon(Icons.person_remove, color: Colors.red),
                tooltip: 'Remove from class',
                onPressed: () => _removeStudent(e),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statusChip(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.success.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        isActive ? 'Active' : 'Ended',
        style: TextStyle(
          fontSize: 11,
          color: isActive ? AppColors.success : AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _fmtDt(DateTime dt) =>
      DateFormat('dd/MM HH:mm').format(dt);
}
