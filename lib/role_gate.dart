import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth/login_page.dart';
import 'admin/admin_dashboard.dart';
import 'household/household_dashboard.dart';
import 'junkshop/junkshop_dashboard.dart';

class RoleGate extends StatelessWidget {
  const RoleGate({super.key});

  Future<String> _getRoleFromUsers(String uid) async {
    final usersDoc =
        await FirebaseFirestore.instance.collection('Users').doc(uid).get();

    if (!usersDoc.exists) return 'unknown';

    final data = usersDoc.data() ?? {};
    final role = (data['Roles'] ?? data['roles'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (role == 'admin') return 'admin';
    if (role == 'collector' || role == 'collectors') return 'collector';
    if (role == 'junkshop' || role == 'junkshops') return 'junkshop';

    // default
    return 'user';
  }

  Future<bool> _junkshopDocExists(String uid) async {
    final junkDoc =
        await FirebaseFirestore.instance.collection('Junkshop').doc(uid).get();
    return junkDoc.exists;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginPage();

    return FutureBuilder<String>(
      future: _getRoleFromUsers(user.uid),
      builder: (context, roleSnap) {
        if (roleSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final role = roleSnap.data ?? 'unknown';

        if (role == 'admin') return const AdminDashboardPage();

        if (role == 'collector') {
          // If you don't have collector dashboard yet, send to normal dashboard
          return const DashboardPage();
        }

        if (role == 'user') return const DashboardPage();

        if (role == 'junkshop') {
          // ✅ only now check Junkshop collection
          return FutureBuilder<bool>(
            future: _junkshopDocExists(user.uid),
            builder: (context, junkSnap) {
              if (junkSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }

              final exists = junkSnap.data == true;
              if (!exists) {
                return const _RoleErrorPage(
                  message:
                      "This account is marked as Junkshop, but Junkshop profile is missing.\n\nPlease contact admin or re-register the shop profile.",
                );
              }

              return JunkshopDashboardPage(shopID: user.uid);
            },
          );
        }

        return const _RoleErrorPage(
          message:
              "No role found for this account.\n\nMake sure Users/{uid} has a Roles field.",
        );
      },
    );
  }
}

class _RoleErrorPage extends StatelessWidget {
  final String message;
  const _RoleErrorPage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
