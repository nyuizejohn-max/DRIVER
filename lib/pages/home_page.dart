import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_theme.dart';
import 'add_task_page.dart';
import 'map_page.dart';
import 'settings_page.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  bool _isEndingTask = false;
  Timer? _clockTimer;

  String _completedTaskFilter = 'all';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Kuwait uses UTC+3.
  DateTime get _kuwaitNow =>
      DateTime.now().toUtc().add(const Duration(hours: 3));

  @override
  void initState() {
    super.initState();

    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  // ------------------------------------------------------------
  // ADD TASK
  // ------------------------------------------------------------

  Future<void> _addNewTask() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddTaskPage()),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  // ------------------------------------------------------------
  // END TASK
  // ------------------------------------------------------------

  Future<void> _endTask(String taskId) async {
    if (_isEndingTask) return;

    setState(() {
      _isEndingTask = true;
    });

    try {
      final driverRef = _firestore.collection('drivers').doc(_uid);
      final taskRef = _firestore.collection('tasks').doc(taskId);

      await _firestore.runTransaction((transaction) async {
        final driverSnapshot = await transaction.get(driverRef);
        final taskSnapshot = await transaction.get(taskRef);

        if (!driverSnapshot.exists || !taskSnapshot.exists) {
          throw StateError('Task information could not be found.');
        }

        final driverData = driverSnapshot.data()!;
        final taskData = taskSnapshot.data()!;

        if (driverData['activeTaskId'] != taskId ||
            taskData['status'] != 'active') {
          throw StateError('This task is no longer active.');
        }

        final startedAt = taskData['startedAt'];

        if (startedAt is! Timestamp) {
          throw StateError('Task start time is not available.');
        }

        final durationSeconds = DateTime.now()
            .difference(startedAt.toDate())
            .inSeconds;

        transaction.update(taskRef, {
          'status': 'completed',
          'endedAt': FieldValue.serverTimestamp(),
          'durationSeconds': durationSeconds,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Ending a task does not end the driver's duty.
        transaction.update(driverRef, {
          'hasActiveTask': false,
          'activeTaskId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) {
        _showMessage('Task completed successfully.');
      }
    } on StateError catch (error) {
      _showMessage(error.message);
    } on FirebaseException catch (error) {
      _showMessage(error.message ?? 'Unable to end task. Please try again.');
    } catch (_) {
      _showMessage('Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isEndingTask = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // ------------------------------------------------------------
  // MAIN BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pages = [_buildHomeContent(), const MapPage(), const SettingsPage()];

    return Scaffold(
      backgroundColor: AppTheme.background,

      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: pages),
      ),

      // Circular add-task button.
      floatingActionButton: _selectedIndex == 0
          ? FloatingActionButton(
              onPressed: _addNewTask,
              backgroundColor: AppTheme.olive,
              foregroundColor: Colors.white,
              elevation: 3,
              shape: const CircleBorder(),
              child: const Icon(Icons.add, size: 29),
            )
          : null,

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        backgroundColor: Colors.white,
        selectedItemColor: AppTheme.olive,
        unselectedItemColor: AppTheme.textSecondary,
        elevation: 10,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map_rounded),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // HOME CONTENT
  // ------------------------------------------------------------

  Widget _buildHomeContent() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('drivers').doc(_uid).snapshots(),
      builder: (context, driverSnapshot) {
        if (driverSnapshot.hasError) {
          return _buildErrorState('Unable to load your driver profile.');
        }

        if (!driverSnapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.olive),
          );
        }

        final driverData = driverSnapshot.data!.data();

        if (driverData == null) {
          return _buildErrorState('Your driver profile could not be found.');
        }

        final firstName = (driverData['firstName'] ?? 'Driver').toString();
        final photoUrl = (driverData['photoUrl'] ?? '').toString();

        final activeTaskId = driverData['activeTaskId']?.toString();

        final dutyStatus = _getDutyStatus(driverData);

        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 105),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildHeader(firstName, dutyStatus, photoUrl),

const SizedBox(height: 24),

_buildTaskFilters(),

const SizedBox(height: 20),
if (activeTaskId != null && activeTaskId.isNotEmpty) ...[
  _buildActiveTaskSection(activeTaskId),
  const SizedBox(height: 20),
],

_buildCompletedTasksSection(),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------
  // DUTY STATUS
  // ------------------------------------------------------------

  String _getDutyStatus(Map<String, dynamic> driverData) {
    final configured = driverData['scheduleConfigured'] == true;

    final workingDays =
        (driverData['workingDays'] as List?)
            ?.map((day) => day.toString().toLowerCase().trim())
            .toList() ??
        [];

    final startTime = driverData['dutyStartTime']?.toString() ?? '';
    final endTime = driverData['dutyEndTime']?.toString() ?? '';

    int? parseMinutes(String value) {
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

    final startMinutes = parseMinutes(startTime);
    final endMinutes = parseMinutes(endTime);

    final validSchedule =
        configured &&
        workingDays.isNotEmpty &&
        startMinutes != null &&
        endMinutes != null &&
        endMinutes > startMinutes;

    if (!validSchedule) return 'NOT SET';

    const dayNames = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];

    final now = _kuwaitNow;
    final today = dayNames[now.weekday - 1];

    if (!workingDays.contains(today)) {
      return 'OFF DUTY';
    }

    final currentMinutes = now.hour * 60 + now.minute;

    if (currentMinutes < startMinutes || currentMinutes >= endMinutes) {
      return 'OFF DUTY';
    }

    return 'ON DUTY';
  }

  // ------------------------------------------------------------
  // HEADER
  // ------------------------------------------------------------

  
Widget _buildHeader(String firstName, String dutyStatus, String photoUrl) {
  final hour = _kuwaitNow.hour;

  final greeting = hour < 12
      ? 'Good morning'
      : hour < 17
          ? 'Good afternoon'
          : 'Good evening';

  final statusColor = dutyStatus == 'ON DUTY'
      ? AppTheme.success
      : dutyStatus == 'OFF DUTY'
          ? AppTheme.error
          : AppTheme.textSecondary;

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(21),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [
          AppTheme.olive,
          Color(0xFF77713A),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(23),
      boxShadow: [
        BoxShadow(
          color: AppTheme.olive.withValues(alpha: 0.20),
          blurRadius: 16,
          offset: const Offset(0, 7),
        ),
      ],
    ),
    child: Stack(
      children: [
        Positioned(
          right: -12,
          bottom: -18,
          child: Icon(
            Icons.directions_car_rounded,
            size: 105,
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),

        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.waving_hand_rounded,
                        color: Color(0xFFFFD580),
                        size: 17,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        greeting.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 9),

                  Text(
                    firstName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  const SizedBox(height: 7),

                  const Text(
                    'Here is your driving activity.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),

                  const SizedBox(height: 13),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'DRIVER DASHBOARD',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            InkWell(
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProfilePage(),
      ),
    );
  },
  borderRadius: BorderRadius.circular(40),
  child: Container(
    height: 61,
    width: 61,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: statusColor,
        width: 3,
      ),
    ),
    child: Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.16),
      ),
      child: ClipOval(
        child: photoUrl.isNotEmpty
            ? Image.network(
    '$photoUrl&v=${DateTime.now().millisecondsSinceEpoch}',
                width: 55,
                height: 55,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.person_outline_rounded,
                    color: Colors.white,
                    size: 32,
                  );
                },
              )
            : const Icon(
                Icons.person_outline_rounded,
                color: Colors.white,
                size: 32,
              ),
      ),
    ),
  ),
),
          ],
        ),
      ],
    ),
  );
}

  // ------------------------------------------------------------
  // TASK FILTERS
  // ------------------------------------------------------------

  Widget _buildTaskFilters() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                _completedTaskFilter = 'all';
              });
            },
            style: OutlinedButton.styleFrom(
              backgroundColor: _completedTaskFilter == 'all'
                  ? AppTheme.olive
                  : Colors.white,
              foregroundColor: _completedTaskFilter == 'all'
                  ? Colors.white
                  : AppTheme.textSecondary,
              side: BorderSide(
                color: _completedTaskFilter == 'all'
                    ? AppTheme.olive
                    : AppTheme.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'All Tasks',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                _completedTaskFilter = 'overtime';
              });
            },
            style: OutlinedButton.styleFrom(
              backgroundColor: _completedTaskFilter == 'overtime'
                  ? AppTheme.warning
                  : Colors.white,
              foregroundColor: _completedTaskFilter == 'overtime'
                  ? Colors.white
                  : AppTheme.textSecondary,
              side: BorderSide(
                color: _completedTaskFilter == 'overtime'
                    ? AppTheme.warning
                    : AppTheme.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Overtime Only',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }


  // ------------------------------------------------------------
  // ACTIVE TASK SECTION
  // ------------------------------------------------------------

      Widget _buildActiveTaskSection(String taskId) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('tasks').doc(taskId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorCard('Unable to load your active task.');
        }

        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(15),
              child: CircularProgressIndicator(color: AppTheme.olive),
            ),
          );
        }

        if (!snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final task = snapshot.data!.data();

        if (task == null || task['status'] != 'active') {
          return const SizedBox.shrink();
        }

        return _buildActiveTaskCard(taskId, task);
      },
    );
  }

  // ------------------------------------------------------------
  // ACTIVE TASK CARD
  // ------------------------------------------------------------

  Widget _buildActiveTaskCard(String taskId, Map<String, dynamic> task) {
    final description = (task['task'] ?? 'Active task').toString();
    final startedAt = task['startedAt'];

    final isOvertime = task['taskType'] == 'overtime';
    final taskColor = isOvertime ? AppTheme.warning : AppTheme.success;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: taskColor.withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.play_circle_fill_rounded, color: taskColor, size: 20),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  'TASK IN PROGRESS',
                  style: TextStyle(
                    color: taskColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),

              Icon(Icons.route_outlined, color: taskColor, size: 21),
            ],
          ),

          const SizedBox(height: 13),

          Text(
            description,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            isOvertime ? 'OVERTIME TASK' : 'NORMAL TASK',
            style: TextStyle(
              color: taskColor,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const Icon(
                Icons.access_time,
                color: AppTheme.textSecondary,
                size: 16,
              ),

              const SizedBox(width: 7),

              Text(
                startedAt is Timestamp
                    ? 'Started ${_formatTime(_toKuwaitTime(startedAt.toDate()))}'
                    : 'Recording start time...',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isEndingTask ? null : () => _endTask(taskId),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _isEndingTask
                  ? const SizedBox(
                      height: 17,
                      width: 17,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.stop_circle_outlined, size: 19),
              label: Text(
                _isEndingTask ? 'Ending Task...' : 'End Task',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // COMPLETED TASKS
  // ------------------------------------------------------------

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  DateTime _toKuwaitTime(DateTime date) {
    return date.toUtc().add(const Duration(hours: 3));
  }

  Widget _buildCompletedTasksSection() {
    final completedQuery = _firestore
        .collection('tasks')
        .where('driverId', isEqualTo: _uid);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: completedQuery.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('COMPLETED TASKS ERROR: ${snapshot.error}');

          return _buildErrorCard(
            'Unable to load completed tasks. Please try again.',
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: AppTheme.olive),
            ),
          );
        }

        final now = _kuwaitNow;
        final cutoff = now.subtract(const Duration(days: 40));

        // Keep completed tasks from the rolling last 40 days.
        final tasks = snapshot.data!.docs.where((document) {
          final data = document.data();

          if (data['status'] != 'completed') return false;

          final endedAt = data['endedAt'];

          if (endedAt is! Timestamp) return false;

          final completedDate = _toKuwaitTime(endedAt.toDate());

          if (completedDate.isBefore(cutoff) || completedDate.isAfter(now)) {
            return false;
          }

          if (_completedTaskFilter == 'overtime' &&
              data['taskType'] != 'overtime') {
            return false;
          }

          return true;
        }).toList();

        // Newest completed tasks first.
        tasks.sort((a, b) {
          final aDate = a.data()['endedAt'] as Timestamp;
          final bDate = b.data()['endedAt'] as Timestamp;

          return bDate.compareTo(aDate);
        });

        // Group completed tasks by date.
        final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        groupedTasks = {};

        for (final document in tasks) {
          final endedAt = document.data()['endedAt'] as Timestamp;
          final date = _toKuwaitTime(endedAt.toDate());
          final dateKey = _dateKey(date);

          groupedTasks.putIfAbsent(dateKey, () => []);
          groupedTasks[dateKey]!.add(document);
        }

        final sortedDates = groupedTasks.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        // Count all overtime tasks within the same 40-day period.
        final overtimeCount = snapshot.data!.docs.where((document) {
          final data = document.data();
          final endedAt = data['endedAt'];

          if (data['status'] != 'completed' ||
              data['taskType'] != 'overtime' ||
              endedAt is! Timestamp) {
            return false;
          }

          final date = _toKuwaitTime(endedAt.toDate());

          return !date.isBefore(cutoff) && !date.isAfter(now);
        }).length;
        return Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
        

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _completedTaskFilter == 'overtime'
                      ? 'Overtime tasks'
                      : 'All completed tasks',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),

                Text(
                  _completedTaskFilter == 'overtime'
                      ? '$overtimeCount overtime tasks'
                      : '${tasks.length} tasks',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            if (tasks.isEmpty)
              _buildNoCompletedTasks()
            else
              ...sortedDates.map((dateKey) {
                final dateParts = dateKey.split('-');

                final date = DateTime(
                  int.parse(dateParts[0]),
                  int.parse(dateParts[1]),
                  int.parse(dateParts[2]),
                );

                final dayTasks = groupedTasks[dateKey]!;
                final yesterday = _kuwaitNow.subtract(const Duration(days: 1));

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    key: PageStorageKey<String>('completed_tasks_$dateKey'),
                    initiallyExpanded: false,
                    leading: Container(
                      height: 42,
                      width: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.oliveLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.calendar_month_outlined,
                        color: AppTheme.olive,
                      ),
                    ),
                    title: Text(
                      dateKey == _dateKey(_kuwaitNow)
                          ? 'Today'
                          : dateKey == _dateKey(yesterday)
                          ? 'Yesterday'
                          : _formatDate(date),
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      '${dayTasks.length} completed '
                      '${dayTasks.length == 1 ? 'task' : 'tasks'}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    children: [
                      const Divider(height: 1),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        child: Column(
                          children: dayTasks.map((document) {
                            return _buildCompletedTaskCard(
                              document.id,
                              document.data(),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------
  // EMPTY COMPLETED TASKS
  // ------------------------------------------------------------

  Widget _buildNoCompletedTasks() {
    final isOvertime = _completedTaskFilter == 'overtime';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.history, color: AppTheme.textSecondary, size: 30),

          const SizedBox(height: 10),

          Text(
            isOvertime ? 'No overtime tasks found' : 'No completed tasks yet',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            isOvertime
                ? 'Your completed overtime tasks will appear here.'
                : 'Your completed tasks will be saved here.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // COMPLETED TASK CARD
  // ------------------------------------------------------------

  Widget _buildCompletedTaskCard(String taskId, Map<String, dynamic> task) {
    final description = (task['task'] ?? 'Completed task').toString();

    final endedAt = task['endedAt'];
    final duration = task['durationSeconds'];

    final isOvertime = task['taskType'] == 'overtime';
    final taskColor = isOvertime ? AppTheme.warning : AppTheme.success;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: taskColor.withValues(alpha: 0.45), width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TaskDetailsPage(taskId: taskId, task: task),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                height: 43,
                width: 43,
                decoration: BoxDecoration(
                  color: taskColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isOvertime ? Icons.more_time : Icons.check_circle_outline,
                  color: taskColor,
                ),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      isOvertime ? 'OVERTIME TASK' : 'NORMAL TASK',
                      style: TextStyle(
                        color: taskColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      endedAt is Timestamp
                          ? _formatDate(_toKuwaitTime(endedAt.toDate()))
                          : 'Completion date unavailable',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),

                    if (duration is num) ...[
                      const SizedBox(height: 4),

                      Text(
                        'Duration: ${_formatDuration(duration.toInt())}',
                        style: TextStyle(
                          color: taskColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }


  // ------------------------------------------------------------
  // ERROR DISPLAY
  // ------------------------------------------------------------

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.error),
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppTheme.error, fontSize: 13),
      ),
    );
  }

  // ------------------------------------------------------------
  // DATE AND TIME FORMATTING
  // ------------------------------------------------------------

  String _formatTime(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }

    if (minutes > 0) {
      return '${minutes}m ${remainingSeconds}s';
    }

    return '${remainingSeconds}s';
  }
}

// ============================================================
// COMPLETED TASK DETAILS SCREEN
// ============================================================

class TaskDetailsPage extends StatelessWidget {
  final String taskId;
  final Map<String, dynamic> task;

  const TaskDetailsPage({super.key, required this.taskId, required this.task});

  DateTime _toKuwaitTime(DateTime date) {
    return date.toUtc().add(const Duration(hours: 3));
  }

  @override
  Widget build(BuildContext context) {
    final description = (task['task'] ?? 'Completed task').toString();

    final startedAt = task['startedAt'];
    final endedAt = task['endedAt'];
    final duration = task['durationSeconds'];

    final isOvertime = task['taskType'] == 'overtime';
    final taskColor = isOvertime ? AppTheme.warning : AppTheme.success;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Task Details'),
        backgroundColor: AppTheme.background,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: taskColor,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Colors.white,
                      size: 35,
                    ),

                    const SizedBox(height: 15),

                    Text(
                      isOvertime ? 'OVERTIME TASK' : 'NORMAL TASK',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Your task summary',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

              const Text(
                'Task description',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                description,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 25),

              _detailRow(
                icon: Icons.calendar_today_outlined,
                label: 'Date',
                value: startedAt is Timestamp
                    ? _date(_toKuwaitTime(startedAt.toDate()))
                    : 'Unavailable',
              ),

              _detailRow(
                icon: Icons.play_circle_outline,
                label: 'Start time',
                value: startedAt is Timestamp
                    ? _time(_toKuwaitTime(startedAt.toDate()))
                    : 'Unavailable',
              ),

              _detailRow(
                icon: Icons.stop_circle_outlined,
                label: 'End time',
                value: endedAt is Timestamp
                    ? _time(_toKuwaitTime(endedAt.toDate()))
                    : 'Unavailable',
              ),

              _detailRow(
                icon: Icons.timer_outlined,
                label: 'Total duration',
                value: duration is num
                    ? _duration(duration.toInt())
                    : 'Unavailable',
              ),

              const SizedBox(height: 25),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: AppTheme.oliveLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Task reference: $taskId',
                  style: const TextStyle(
                    color: AppTheme.olive,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 17),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.olive, size: 21),

          const SizedBox(width: 13),

          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),

          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _time(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
  }

  String _date(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _duration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }

    if (minutes > 0) {
      return '${minutes}m ${remainingSeconds}s';
    }

    return '${remainingSeconds}s';
  }
}

