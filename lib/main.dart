import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'auth/auth_gate.dart';
import 'theme/app_theme.dart';

import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;

import 'dart:ui' as ui;

@pragma('vm:entry-point')
Future<void> backgroundGeolocationHeadlessTask(
  bg.HeadlessEvent headlessEvent,
) async {
  try {
    // Only GPS location events need to be saved here.
    if (headlessEvent.name != bg.Event.LOCATION) {
      return;
    }

    ui.DartPluginRegistrant.ensureInitialized();
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize Firebase in the background engine.
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    // Retrieve the driver ID saved during login.
    final preferences = await SharedPreferences.getInstance();
    final savedDriverId = preferences.getString('active_driver_uid');

    if (savedDriverId == null || savedDriverId.isEmpty) {
      return;
    }

    // Confirm that this driver is still authenticated.
    final User? user = await FirebaseAuth.instance.authStateChanges().first;

    if (user == null || user.uid != savedDriverId) {
      return;
    }

    final bg.Location location = headlessEvent.event;
    final coordinates = location.coords;

    // Save the latest driver location.
    await FirebaseFirestore.instance
        .collection('driverLocations')
        .doc(savedDriverId)
        .set({
          'driverId': savedDriverId,
          'latitude': coordinates.latitude,
          'longitude': coordinates.longitude,
          'accuracy': coordinates.accuracy,
          'speed': coordinates.speed,
          'heading': coordinates.heading,
          'capturedAt': location.timestamp,
          'lastUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  } catch (error, stackTrace) {
    debugPrint('[Driver Headless] Location error: $error');
    debugPrint('$stackTrace');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Headless background tracking is supported on native platforms only.
  if (!kIsWeb) {
    await bg.BackgroundGeolocation.registerHeadlessTask(
      backgroundGeolocationHeadlessTask,
    );
  }

  runApp(const DriverApp());
}

class DriverApp extends StatelessWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthGate(),
    );
  }
}
