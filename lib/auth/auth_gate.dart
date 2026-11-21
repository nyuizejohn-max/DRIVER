
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/auth_service.dart';
import '../services/location_tracking_service.dart';
import '../theme/app_theme.dart';
import '../pages/home_page.dart';
import 'login_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AuthService.instance.authStateChanges,
      builder: (context, authSnapshot) {
        // Waiting for Firebase authentication.
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        // No authenticated driver.
        final user = authSnapshot.data;

        if (user == null) {
          return const LoginPage();
        }

        // Listen to the driver's Firestore profile.
        // This also detects changes to approval status.
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('drivers')
              .doc(user.uid)
              .snapshots(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            if (profileSnapshot.hasError) {
              return const _AccessMessageScreen(
                title: 'Unable to verify account',
                message:
                    'We could not verify your driver account. '
                    'Please check your internet connection and try again.',
                icon: Icons.cloud_off_outlined,
              );
            }

            if (!profileSnapshot.hasData ||
                !profileSnapshot.data!.exists) {
              return const _AccessMessageScreen(
                title: 'Driver profile not found',
                message:
                    'Your driver profile could not be found. '
                    'Please contact support.',
                icon: Icons.person_off_outlined,
              );
            }

            final data = profileSnapshot.data!.data();

            final String status = (data?['status'] ?? 'pending')
                .toString()
                .toLowerCase();

            final bool approved = data?['approved'] == true;

            // Only approved drivers can access Home.
            if (approved && status == 'approved') {
              return _ApprovedDriverHome(driverId: user.uid);
            }

            if (status == 'rejected') {
              return const _AccessMessageScreen(
                title: 'Application not approved',
                message:
                    'Your driver registration was not approved. '
                    'Please contact support for more information.',
                icon: Icons.cancel_outlined,
              );
            }

            return const _AccessMessageScreen(
              title: 'Approval pending',
              message:
                  'Your driver account is awaiting approval. '
                  'You will be able to access the app once your '
                  'registration has been approved.',
              icon: Icons.hourglass_empty,
            );
          },
        );
      },
    );
  }
}

// Initializes tracking when an approved driver enters the app.
class _ApprovedDriverHome extends StatefulWidget {
  final String driverId;

  const _ApprovedDriverHome({
    required this.driverId,
  });

  @override
  State<_ApprovedDriverHome> createState() =>
      _ApprovedDriverHomeState();
}

class _ApprovedDriverHomeState extends State<_ApprovedDriverHome> {
  @override
  void initState() {
    super.initState();
    _initializeTracking();
  }

  Future<void> _initializeTracking() async {
    try {
      await LocationTrackingService.instance.initializeForDriver(
        widget.driverId,
      );
    } catch (error) {
      debugPrint('Could not initialize driver tracking: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const HomePage();
  }
}

// Loading screen.
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          color: AppTheme.olive,
        ),
      ),
    );
  }
}

// Pending, rejected, and account error screen.
class _AccessMessageScreen extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const _AccessMessageScreen({
    required this.title,
    required this.message,
    required this.icon,
  });

  Future<void> _signOut(BuildContext context) async {
    try {
      await AuthService.instance.logout();
    } catch (_) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to sign out. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 82,
                    width: 82,
                    decoration: BoxDecoration(
                      color: AppTheme.oliveLight,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(
                      icon,
                      size: 42,
                      color: AppTheme.olive,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => _signOut(context),
                      child: const Text('Back to Sign In'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}