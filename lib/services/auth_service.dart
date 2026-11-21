import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'location_tracking_service.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Register a new driver.
  Future<void> registerDriver({
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
    required String password,
  }) async {
    UserCredential? credential;

    try {
      credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final User user = credential.user!;

      await user.updateDisplayName('$firstName $lastName');

      await _firestore.collection('drivers').doc(user.uid).set({
        'uid': user.uid,
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'fullName': '${firstName.trim()} ${lastName.trim()}',
        'phone': phone.trim(),
        'email': email.trim().toLowerCase(),
        'role': 'driver',
        'status': 'pending',
        'approved': false,
        'hasActiveTask': false,
        'activeTaskId': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Registration is complete, but approval is still required.
      await _auth.signOut();
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      // Avoid leaving an authentication account without a profile.
      if (credential?.user != null) {
        await credential!.user!.delete();
      }
      rethrow;
    }
  }

  // Sign in an existing driver.
  Future<String> loginDriver({
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final User user = credential.user!;

      final DocumentSnapshot<Map<String, dynamic>> profile = await _firestore
          .collection('drivers')
          .doc(user.uid)
          .get();

      if (!profile.exists) {
        await _auth.signOut();
        throw Exception(
          'Your driver profile could not be found. Please contact support.',
        );
      }

      final data = profile.data()!;

      final String status = (data['status'] ?? 'pending')
          .toString()
          .toLowerCase();

      final bool approved = data['approved'] == true;

      if (!approved || status != 'approved') {
        await _auth.signOut();

        if (status == 'rejected') {
          throw Exception(
            'Your registration was not approved. Please contact support.',
          );
        }

        throw Exception('Your account is awaiting admin approval.');
      }

      // Save the approved driver's UID for background tracking.
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('active_driver_uid', user.uid);

      return 'success';
    } on FirebaseAuthException {
      rethrow;
    }
  }

  // Sign out the current driver.
  Future<void> logout() async {
    await LocationTrackingService.instance.stopTracking();

    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('active_driver_uid');

    await _auth.signOut();
  }

  // Retrieve the current driver's Firestore profile.
  Future<Map<String, dynamic>?> getDriverProfile() async {
    final user = _auth.currentUser;

    if (user == null) return null;

    final snapshot = await _firestore.collection('drivers').doc(user.uid).get();

    return snapshot.data();
  }
}
