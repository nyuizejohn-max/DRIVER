
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_theme.dart';

class AddTaskPage extends StatefulWidget {
  const AddTaskPage({super.key});

  @override
  State<AddTaskPage> createState() => _AddTaskPageState();
}

class _AddTaskPageState extends State<AddTaskPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _taskController = TextEditingController();

  bool _isLoading = false;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  // Kuwait time is UTC+3.
  DateTime get _kuwaitNow =>
      DateTime.now().toUtc().add(const Duration(hours: 3));

  int? _parseTime(String value) {
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

    return hour * 60 + minute;
  }

  // Classify the task using the saved duty schedule.
  String _getTaskType(Map<String, dynamic> driverData) {
    final configured = driverData['scheduleConfigured'] == true;

    if (!configured) {
      return 'overtime';
    }

    final workingDays = (driverData['workingDays'] as List?)
            ?.map((day) => day.toString().toLowerCase().trim())
            .toList() ??
        [];

    final startTime = driverData['dutyStartTime']?.toString() ?? '';
    final endTime = driverData['dutyEndTime']?.toString() ?? '';

    final startMinutes = _parseTime(startTime);
    final endMinutes = _parseTime(endTime);

    // Missing or invalid schedule: classify conservatively.
    if (workingDays.isEmpty ||
        startMinutes == null ||
        endMinutes == null ||
        endMinutes <= startMinutes) {
      return 'overtime';
    }

    final now = _kuwaitNow;

    const dayNames = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];

    final today = dayNames[now.weekday - 1];

    if (!workingDays.contains(today)) {
      return 'overtime';
    }

    final currentMinutes = now.hour * 60 + now.minute;

    if (currentMinutes < startMinutes ||
        currentMinutes >= endMinutes) {
      return 'overtime';
    }

    return 'normal';
  }

  Future<void> _startTask() async {
    if (!_formKey.currentState!.validate()) return;

    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('Please sign in before starting a task.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final DocumentReference<Map<String, dynamic>> driverRef =
          _firestore.collection('drivers').doc(user.uid);

      final DocumentReference<Map<String, dynamic>> taskRef =
          _firestore.collection('tasks').doc();

      await _firestore.runTransaction((transaction) async {
        final driverSnapshot = await transaction.get(driverRef);

        if (!driverSnapshot.exists) {
          throw StateError(
            'Your driver profile could not be found.',
          );
        }

        final driverData = driverSnapshot.data()!;

        // Prevent another active task.
        final bool hasActiveTask =
            driverData['hasActiveTask'] == true ||
            driverData['activeTaskId'] != null;

        if (hasActiveTask) {
          throw StateError(
            'You already have an active task. '
            'Please complete it before starting another.',
          );
        }

        // Determine normal or overtime automatically.
        final taskType = _getTaskType(driverData);

        // Save the task and its permanent classification.
        transaction.set(taskRef, {
          'taskId': taskRef.id,
          'driverId': user.uid,
          'task': _taskController.text.trim(),

          'taskType': taskType,

          // Keep a copy of the schedule used for classification.
          'classificationSchedule': {
            'scheduleConfigured':
                driverData['scheduleConfigured'] == true,
            'workingDays': driverData['workingDays'] ?? [],
            'dutyStartTime': driverData['dutyStartTime'],
            'dutyEndTime': driverData['dutyEndTime'],
          },

          'status': 'active',
          'startedAt': FieldValue.serverTimestamp(),
          'endedAt': null,
          'durationSeconds': null,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Update the driver's active task information.
        transaction.update(driverRef, {
          'hasActiveTask': true,
          'activeTaskId': taskRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;

      _showMessage('Task started successfully.');

      Navigator.pop(context, true);
    } on StateError catch (error) {
      _showMessage(error.message);
    } on FirebaseException catch (error) {
      debugPrint('FIREBASE TASK ERROR: ${error.code}');
      debugPrint('FIREBASE TASK MESSAGE: ${error.message}');

      _showMessage(
        'Unable to start task: ${error.message ?? error.code}',
      );
    } catch (error, stackTrace) {
      debugPrint('START TASK ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      _showMessage('Start task failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'New task',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Describe the task you are about to perform.',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildTaskField() {
    return TextFormField(
      controller: _taskController,
      enabled: !_isLoading,
      maxLines: 5,
      minLines: 4,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        hintText: 'Enter your task description...',
        alignLabelWithHint: true,
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: 75),
          child: Icon(Icons.assignment_outlined),
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter a task description.';
        }

        if (value.trim().length < 3) {
          return 'Please enter a little more detail.';
        }

        return null;
      },
    );
  }

  Widget _buildInformationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.oliveLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.olive.withValues(alpha: 0.15),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            color: AppTheme.olive,
            size: 22,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Automatic task recording',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Your task start time, date and task category '
                  'will be recorded automatically. When you finish, '
                  'press End Task to record the completion time '
                  'and duration.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
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

  Widget _buildStartButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _startTask,
        icon: _isLoading
            ? const SizedBox(
                height: 19,
                width: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.play_arrow_rounded),
        label: Text(
          _isLoading ? 'Starting task...' : 'Start Task',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Add Task'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildHeader(),
              const SizedBox(height: 25),
              const Text(
                'Task description',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              _buildTaskField(),
              const SizedBox(height: 20),
              _buildInformationCard(),
              const SizedBox(height: 30),
              _buildStartButton(),
            ],
          ),
        ),
      ),
    );
  }
}
