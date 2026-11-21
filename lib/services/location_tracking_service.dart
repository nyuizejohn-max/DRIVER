import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;

class LocationTrackingService {
  LocationTrackingService._();

  static final LocationTrackingService instance = LocationTrackingService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? _driverId;
  bool _initialized = false;

  /// Initialize background tracking for the authenticated driver.
  Future<void> initializeForDriver(String driverId) async {
    if (kIsWeb) {
      _driverId = driverId;
      _initialized = true;
      debugPrint('Background tracking is unavailable on web.');
      return;
    }
    if (_initialized && _driverId == driverId) return;

    _driverId = driverId;

    final driverSnapshot = await _firestore
        .collection('drivers')
        .doc(driverId)
        .get();

    if (!driverSnapshot.exists) {
      throw Exception('Driver profile was not found.');
    }

    final driverData = driverSnapshot.data()!;

    // Listen for GPS updates.
    bg.BackgroundGeolocation.onLocation(_onLocation, _onLocationError);

    // Convert the driver's saved working hours into SDK schedule entries.
    final schedule = _buildSchedule(driverData);

    await bg.BackgroundGeolocation.ready(
      bg.Config(
        reset: false,
        geolocation: bg.GeoConfig(
          desiredAccuracy: bg.DesiredAccuracy.navigation,
          distanceFilter: 10,
          stopTimeout: 5,
        ),
        app: bg.AppConfig(
          schedule: schedule,
          scheduleUseAlarmManager: true,
          stopOnTerminate: false,
          startOnBoot: true,
          enableHeadless: true,
          notification: bg.Notification(
            title: 'WHEATTASTE Driver',
            text: 'Duty location tracking is active',
          ),
        ),
      ),
    );

    _initialized = true;

    if (schedule.isNotEmpty) {
      await bg.BackgroundGeolocation.startSchedule();
    } else {
      await bg.BackgroundGeolocation.stopSchedule();
      await bg.BackgroundGeolocation.stop();
    }
  }

  /// Convert Firestore working days and hours into SDK schedule entries.
  List<String> _buildSchedule(Map<String, dynamic> driverData) {
    if (driverData['scheduleConfigured'] != true) {
      return [];
    }

    final workingDays = driverData['workingDays'];

    final startTime = driverData['dutyStartTime']?.toString();
    final endTime = driverData['dutyEndTime']?.toString();

    if (workingDays is! List ||
        workingDays.isEmpty ||
        startTime == null ||
        endTime == null) {
      return [];
    }

    const dayNumbers = {
      'Sunday': 1,
      'Monday': 2,
      'Tuesday': 3,
      'Wednesday': 4,
      'Thursday': 5,
      'Friday': 6,
      'Saturday': 7,
    };

    final schedule = <String>[];

    for (final day in workingDays) {
      final dayNumber = dayNumbers[day.toString()];

      if (dayNumber != null) {
        schedule.add('$dayNumber $startTime-$endTime');
      }
    }

    return schedule;
  }

  /// Save the driver's latest GPS position for the Admin app.
  Future<void> _onLocation(bg.Location location) async {
    final driverId = _driverId;

    if (driverId == null) return;

    try {
      final coordinates = location.coords;

      await _firestore.collection('driverLocations').doc(driverId).set({
        'driverId': driverId,
        'latitude': coordinates.latitude,
        'longitude': coordinates.longitude,
        'accuracy': coordinates.accuracy,
        'speed': coordinates.speed,
        'heading': coordinates.heading,
        'capturedAt': location.timestamp,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      print('Could not save driver location: $error');
    }
  }

  void _onLocationError(bg.LocationError error) {
    print('Background location error: $error');
  }

  /// Apply a new duty schedule after the driver changes Settings.
  Future<void> updateSchedule(Map<String, dynamic> driverData) async {
    if (kIsWeb) return;
    final schedule = _buildSchedule(driverData);

    await bg.BackgroundGeolocation.setConfig(
      bg.Config(
        app: bg.AppConfig(schedule: schedule, scheduleUseAlarmManager: true),
      ),
    );

    if (schedule.isNotEmpty) {
      await bg.BackgroundGeolocation.startSchedule();
    } else {
      await bg.BackgroundGeolocation.stopSchedule();
      await bg.BackgroundGeolocation.stop();
    }
  }

  /// Stop tracking when the driver logs out.
  Future<void> stopTracking() async {
    if (kIsWeb) {
      _driverId = null;
      _initialized = false;
      return;
    }
    await bg.BackgroundGeolocation.stopSchedule();
    await bg.BackgroundGeolocation.stop();

    _driverId = null;
    _initialized = false;
  }
}
