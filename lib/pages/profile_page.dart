
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  bool _uploadingPhoto = false;

  Future<void> _changeProfilePicture() async {
    final user = _auth.currentUser;

    if (user == null) return;

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1200,
      );

      if (image == null) return;

      setState(() {
        _uploadingPhoto = true;
      });

      final imageBytes = await image.readAsBytes();

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('driver_profiles/${user.uid}/profile.jpg');

      await storageRef.putData(
        imageBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final photoUrl = await storageRef.getDownloadURL();

      await _firestore.collection('drivers').doc(user.uid).update({
        'photoUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile picture updated successfully.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update profile picture: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploadingPhoto = false;
        });
      }
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) return 'Not available';

    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    } else if (value is DateTime) {
      date = value;
    }

    if (date == null) return 'Not available';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  String _accountStatus(Map<String, dynamic> data) {
    if (data['approved'] == true) return 'Approved';

    final status = (data['status'] ?? 'Pending').toString();

    return status[0].toUpperCase() + status.substring(1);
  }

  Color _statusColor(Map<String, dynamic> data) {
    if (data['approved'] == true) return AppTheme.success;

    final status = (data['status'] ?? '').toString().toLowerCase();

    if (status == 'rejected' || status == 'suspended') {
      return AppTheme.error;
    }

    return AppTheme.warning;
  }

  Widget _buildDetailCard({
    required String title,
    required IconData icon,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            height: 43,
            width: 43,
            decoration: BoxDecoration(
              color: AppTheme.oliveLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: AppTheme.olive,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value.isEmpty ? 'Not available' : value,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent(Map<String, dynamic> data) {
    final firstName = (data['firstName'] ?? '').toString();
    final lastName = (data['lastName'] ?? '').toString();

    final fullName = (data['fullName'] ?? '$firstName $lastName')
        .toString()
        .trim();

    final phone = (data['phone'] ?? '').toString();
    final email = (data['email'] ?? _auth.currentUser?.email ?? '').toString();
    final role = (data['role'] ?? 'Driver').toString();
    final photoUrl = (data['photoUrl'] ?? '').toString();

    final status = _accountStatus(data);
    final statusColor = _statusColor(data);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 12),

          // Profile picture
          Center(
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.olive,
                          width: 3,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 62,
                        backgroundColor: AppTheme.oliveLight,
                        backgroundImage: photoUrl.isNotEmpty
    ? NetworkImage(
        '$photoUrl&v=${DateTime.now().millisecondsSinceEpoch}',
      )
    : null,
                        
                        child: photoUrl.isEmpty
                            ? const Icon(
                                Icons.person_rounded,
                                size: 65,
                                color: AppTheme.olive,
                              )
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 3,
                      right: 3,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: AppTheme.olive,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: _uploadingPhoto
                              ? null
                              : _changeProfilePicture,
                          icon: const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                Text(
                  fullName.isEmpty ? 'Driver' : fullName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 6),

                Text(
                  role.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Account: $status',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),

                if (_uploadingPhoto) ...[
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(
                    color: AppTheme.olive,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Uploading picture...',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 30),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Personal Information',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),

          const SizedBox(height: 16),

          _buildDetailCard(
            title: 'First Name',
            icon: Icons.person_outline_rounded,
            value: firstName,
          ),

          _buildDetailCard(
            title: 'Last Name',
            icon: Icons.person_outline_rounded,
            value: lastName,
          ),

          _buildDetailCard(
            title: 'Phone Number',
            icon: Icons.phone_outlined,
            value: phone,
          ),

          _buildDetailCard(
            title: 'Email Address',
            icon: Icons.email_outlined,
            value: email,
          ),

          _buildDetailCard(
            title: 'Account Role',
            icon: Icons.badge_outlined,
            value: role,
          ),

          _buildDetailCard(
            title: 'Registration Date',
            icon: Icons.calendar_today_outlined,
            value: _formatDate(data['createdAt']),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
      ),
      body: user == null
          ? const Center(
              child: Text('Please sign in to view your profile.'),
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _firestore
                  .collection('drivers')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Unable to load your profile.'),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.olive,
                    ),
                  );
                }

                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(
                    child: Text('Driver profile not found.'),
                  );
                }

                final data = snapshot.data!.data();

                if (data == null) {
                  return const Center(
                    child: Text('Driver profile information is unavailable.'),
                  );
                }

                return _buildProfileContent(data);
              },
            ),
    );
  }
}
