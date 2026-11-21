import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_theme.dart';
import '../services/location_tracking_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const List<String> _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  final Set<String> _workingDays = {};

  TimeOfDay? _dutyStartTime;
  TimeOfDay? _dutyEndTime;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _scheduleConfigured = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> get _driverRef =>
    _firestore.collection('drivers').doc(_uid!);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (_uid == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final snapshot = await _driverRef.get();

      if (!snapshot.exists) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final data = snapshot.data() ?? {};

      final List<dynamic> savedDays = data['workingDays'] is List
          ? data['workingDays'] as List<dynamic>
          : [];

      final startTime = data['dutyStartTime']?.toString();
      final endTime = data['dutyEndTime']?.toString();

      if (!mounted) return;

      setState(() {
        _workingDays
          ..clear()
          ..addAll(
            savedDays
                .map((day) => day.toString())
                .where((day) => _days.contains(day)),
          );

        _dutyStartTime = _parseTime(startTime);
        _dutyEndTime = _parseTime(endTime);

        _scheduleConfigured = data['scheduleConfigured'] == true;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage('Unable to load your settings. Please try again.');
    }
  }

  TimeOfDay? _parseTime(String? value) {
    if (value == null || !value.contains(':')) return null;

    final parts = value.split(':');

    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  String _timeToString(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return 'Select time';

    return time.format(context);
  }

  Future<void> _selectTime({required bool isStartTime}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: isStartTime
          ? (_dutyStartTime ?? const TimeOfDay(hour: 8, minute: 0))
          : (_dutyEndTime ?? const TimeOfDay(hour: 17, minute: 0)),
    );

    if (selected == null || !mounted) return;

    setState(() {
      if (isStartTime) {
        _dutyStartTime = selected;
      } else {
        _dutyEndTime = selected;
      }
    });
  }

  void _toggleDay(String day) {
    setState(() {
      if (_workingDays.contains(day)) {
        _workingDays.remove(day);
      } else {
        _workingDays.add(day);
      }
    });
  }

  bool _isValidSchedule() {
    if (_workingDays.isEmpty) {
      _showMessage('Please select at least one working day.');
      return false;
    }

    if (_dutyStartTime == null || _dutyEndTime == null) {
      _showMessage('Please select both duty start and end times.');
      return false;
    }

    final startMinutes = _dutyStartTime!.hour * 60 + _dutyStartTime!.minute;

    final endMinutes = _dutyEndTime!.hour * 60 + _dutyEndTime!.minute;

    if (endMinutes <= startMinutes) {
      _showMessage('Duty end time must be later than duty start time.');
      return false;
    }

    return true;
  }

  Future<void> _saveSettings() async {
    if (_uid == null) {
      _showMessage('Please sign in again.');
      return;
    }

    if (!_isValidSchedule()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await _driverRef.update({
        'workingDays': _days.where(_workingDays.contains).toList(),
        'dutyStartTime': _timeToString(_dutyStartTime!),
        'dutyEndTime': _timeToString(_dutyEndTime!),
        'scheduleConfigured': true,
        'scheduleUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await LocationTrackingService.instance.updateSchedule({
        'scheduleConfigured': true,
        'workingDays': _days.where(_workingDays.contains).toList(),
        'dutyStartTime': _timeToString(_dutyStartTime!),
        'dutyEndTime': _timeToString(_dutyEndTime!),
      });

      if (!mounted) return;

      setState(() {
        _scheduleConfigured = true;
      });

      _showMessage('Your duty schedule has been saved.');
    } on FirebaseException catch (error) {
      _showMessage(
        'Unable to save settings. ${error.message ?? 'Please try again.'}',
      );
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildTimeCard({
    required String title,
    required TimeOfDay? time,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: AppTheme.olive),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                _formatTime(time),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Tap to change',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayTile(String day) {
    final bool selected = _workingDays.contains(day);

    return InkWell(
      onTap: () => _toggleDay(day),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? AppTheme.oliveLight : AppTheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.olive : AppTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 20,
              color: selected ? AppTheme.olive : AppTheme.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                day,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Text(
              selected ? 'WORKING' : 'OFF',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: selected ? AppTheme.olive : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleStatus() {
    final bool configured = _scheduleConfigured;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: configured ? AppTheme.oliveLight : AppTheme.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: configured ? AppTheme.olive : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            configured ? Icons.calendar_month : Icons.info_outline,
            color: configured ? AppTheme.olive : AppTheme.textSecondary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  configured ? 'SCHEDULE CONFIGURED' : 'NOT SET UP',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: configured ? AppTheme.olive : AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  configured
                      ? 'Your working days and duty hours are saved.'
                      : 'Set your working days and duty hours below.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [
        _buildScheduleStatus(),

        const SizedBox(height: 28),

        _buildSectionTitle(
          'Duty hours',
          'Choose when your scheduled working day begins and ends.',
        ),

        const SizedBox(height: 14),

        Row(
          children: [
            _buildTimeCard(
              title: 'START TIME',
              time: _dutyStartTime,
              icon: Icons.login,
              onTap: () => _selectTime(isStartTime: true),
            ),
            const SizedBox(width: 12),
            _buildTimeCard(
              title: 'END TIME',
              time: _dutyEndTime,
              icon: Icons.logout,
              onTap: () => _selectTime(isStartTime: false),
            ),
          ],
        ),

        const SizedBox(height: 28),

        _buildSectionTitle(
          'Working days',
          'Tap a day to switch between working day and off day.',
        ),

        const SizedBox(height: 14),

        ..._days.map(_buildDayTile),

        const SizedBox(height: 14),

        Row(
          children: [
            Icon(Icons.check_circle, size: 16, color: AppTheme.olive),
            const SizedBox(width: 6),
            const Text(
              'Working day',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(width: 18),
            const Icon(
              Icons.circle_outlined,
              size: 16,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            const Text(
              'Off day',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),

        const SizedBox(height: 28),

        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveSettings,
            child: _isSaving
                ? const SizedBox(
                    height: 21,
                    width: 21,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save Schedule'),
          ),
        ),

        const SizedBox(height: 14),

        const Text(
          'Your saved schedule will be used to determine your scheduled availability. '
          'It does not by itself confirm that you have started duty.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Settings'), centerTitle: false),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _uid == null
          ? const Center(child: Text('Please sign in again.'))
          : _buildSettingsContent(),
    );
  }
}
