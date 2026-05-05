import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/attendance_model.dart';
import '../../models/class_model.dart';
import '../../models/session_model.dart';
import '../../services/attendance_service.dart';
import '../../utils/constants.dart';

class ViewAttendanceScreen extends StatefulWidget {
  final ClassModel classModel;
  final String? sessionId;

  const ViewAttendanceScreen({
    super.key,
    required this.classModel,
    this.sessionId,
  });

  @override
  State<ViewAttendanceScreen> createState() => _ViewAttendanceScreenState();
}

class _ViewAttendanceScreenState extends State<ViewAttendanceScreen> {
  final _svc = AttendanceService();
  List<AttendanceModel> _records = [];
  List<SessionModel> _sessions = [];
  SessionModel? _selectedSession;
  bool _loading = true;
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final sessions = await _svc.getClassSessions(widget.classModel.classId);
    if (mounted) {
      setState(() => _sessions = sessions);
    }
    if (widget.sessionId != null) {
      final session = sessions.firstWhere(
        (s) => s.sessionId == widget.sessionId,
        orElse: () => sessions.first,
      );
      _selectedSession = session;
      await _loadAttendance();
    } else if (sessions.isNotEmpty) {
      _selectedSession = sessions.first;
      await _loadAttendance();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadAttendance() async {
    setState(() => _loading = true);
    List<AttendanceModel> records;
    if (_selectedSession != null) {
      records = await _svc.getSessionAttendance(_selectedSession!.sessionId);
    } else {
      records = await _svc.getClassAttendance(widget.classModel.classId);
    }
    if (mounted) {
      setState(() {
        _records = records;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Attendance – ${widget.classModel.className}'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (_sessions.isNotEmpty)
            Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Session',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<SessionModel>(
                    // ignore: deprecated_member_use
                    value: _selectedSession,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: AppColors.background,
                    ),
                    items: _sessions
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s.sessionName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (s) {
                      if (s == null) return;
                      setState(() => _selectedSession = s);
                      _loadAttendance();
                    },
                  ),
                ],
              ),
            ),
          // Summary bar
          Container(
            color: AppColors.primary.withValues(alpha: 0.08),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.people, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  '${_records.length} student(s) present',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox,
                                size: 56, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              'No attendance records',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _records.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final rec = _records[i];
                          return Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    AppColors.success.withValues(alpha: 0.15),
                                child: Text(
                                  rec.userName.isNotEmpty
                                      ? rec.userName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                rec.userName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(rec.userEmail,
                                      style: const TextStyle(fontSize: 12)),
                                  Text(
                                    _dateFmt.format(rec.timestamp),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Present',
                                  style: TextStyle(
                                    color: AppColors.success,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
