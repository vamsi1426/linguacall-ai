import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:linguacall/screens/login_screen.dart';
import 'package:linguacall/utils/theme.dart';
import 'package:provider/provider.dart';
import 'package:linguacall/services/auth_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      body: uid == null
          ? const Center(child: Text('Please login to view your profile.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data?.data() ?? const <String, dynamic>{};
                final phone = (data['phone'] ?? '').toString();
                final name = (data['name'] ?? 'User').toString();
                final language = (data['language'] ?? 'Telugu').toString();
                final onlineStatus = data['onlineStatus'] == true;

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _UserHeaderCard(
                      name: name,
                      phone: phone,
                      language: language,
                      onlineStatus: onlineStatus,
                    ),
                    const SizedBox(height: 16),
                    GlassActionCard(
                      icon: Icons.logout,
                      title: 'Logout',
                      onTap: () async {
                        await context.read<AuthService>().logout();
                        if (!context.mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _UserHeaderCard extends StatelessWidget {
  final String name;
  final String phone;
  final String language;
  final bool onlineStatus;

  const _UserHeaderCard({
    required this.name,
    required this.phone,
    required this.language,
    required this.onlineStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.glassCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0038F5), Color(0xFF9F03FF)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      phone,
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _MetaChip(
                icon: Icons.language,
                label: language,
              ),
              const SizedBox(width: 10),
              _MetaChip(
                icon: Icons.circle,
                label: onlineStatus ? 'Online' : 'Offline',
                color: onlineStatus ? AppTheme.secondaryColor : Colors.white54,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MetaChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppTheme.primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardColor.withOpacity(0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: chipColor.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: chipColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class GlassActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const GlassActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.glassCard,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0038F5), Color(0xFF9F03FF)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

