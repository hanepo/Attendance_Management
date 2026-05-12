import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/class_model.dart';
import '../../services/attendance_service.dart';
import '../../utils/constants.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';

class CreateSessionScreen extends StatefulWidget {
  final ClassModel classModel;
  const CreateSessionScreen({super.key, required this.classModel});

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  DateTime _startTime = DateTime.now();
  DateTime _endTime = DateTime.now().add(const Duration(hours: 1));
  bool _loading = false;

  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );
    if (time == null) return;
    setState(() {
      _startTime = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
      if (_endTime.isBefore(_startTime)) {
        _endTime = _startTime.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _pickEnd() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endTime,
      firstDate: _startTime,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endTime),
    );
    if (time == null) return;
    setState(() {
      _endTime = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_endTime.isAfter(_startTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start time'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await AttendanceService().createSession(
        classId: widget.classModel.classId,
        sessionName: _nameCtrl.text.trim(),
        startTime: _startTime,
        endTime: _endTime,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session created successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Create Session'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.classModel.className,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              CustomTextField(
                label: 'Session Name',
                hint: 'e.g. Week 3 Lecture',
                controller: _nameCtrl,
                prefixIcon: Icons.event_note,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Session name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              const Text(
                'Start Time',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _DateTimePickerTile(
                value: _dateFmt.format(_startTime),
                icon: Icons.calendar_today,
                onTap: _pickStart,
              ),
              const SizedBox(height: 16),
              const Text(
                'End Time',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _DateTimePickerTile(
                value: _dateFmt.format(_endTime),
                icon: Icons.calendar_today_outlined,
                onTap: _pickEnd,
              ),
              const SizedBox(height: 32),
              PrimaryButton(
                label: 'Create Session',
                onPressed: _create,
                loading: _loading,
                icon: Icons.qr_code,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateTimePickerTile extends StatelessWidget {
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _DateTimePickerTile({
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Text(
              value,
              style: const TextStyle(fontSize: 15),
            ),
            const Spacer(),
            const Icon(Icons.edit, color: AppColors.textSecondary, size: 16),
          ],
        ),
      ),
    );
  }
}
