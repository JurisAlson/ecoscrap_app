import 'package:ecoscrap_app/Collector/collectors_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin/admin_users_dashboard.dart';
import 'auth/login_page.dart';
import 'household/household_dashboard.dart';
import 'junkshop/junkshop_dashboard.dart';
import 'package:cloud_functions/cloud_functions.dart';
//import 'Collector/collectors_dashboard.dart';

Future<void> grantMeAdminClaimIfOwner(User user) async {
if (user.email?.toLowerCase() != "jurisalson@gmail.com") return;

  final callable = FirebaseFunctions.instanceFor(region: "asia-southeast1")
      .httpsCallable("setAdminClaim");

  await callable.call({
    "uid": user.uid,
    "admin": true,
  });

  await user.getIdTokenResult(true); // refresh token
}

class RoleGate extends StatelessWidget {
  const RoleGate({super.key});

  Future<String> _getRoleFromUsers(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
    if (!doc.exists) return 'unknown';

    final data = doc.data() ?? {};
    final raw = (data['Roles'] ?? data['roles'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    // Normalize common variants
    if (raw == 'admin') return 'admin';
    if (raw == 'collector' || raw == 'collectors') return 'collector';
    if (raw == 'junkshop' || raw == 'junkshops') return 'junkshop';
    if (raw == 'user' || raw == 'users' || raw == 'household' || raw == 'households') return 'user';

    // Anything else is invalid
    return 'unknown';
  }

  Future<bool> _junkshopDocExists(String uid) async {
    final junkDoc = await FirebaseFirestore.instance.collection('Junkshop').doc(uid).get();
    return junkDoc.exists;
  }

  Future<bool> _hasAdminClaim(User user) async {
    final token = await user.getIdTokenResult(true); // force refresh
    return token.claims?['admin'] == true;
  }

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    }
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

        if (roleSnap.hasError) {
          return _RoleErrorPage(
            message: "Failed to load role.\n\n${roleSnap.error}",
            actionLabel: "Logout",
            onAction: () => _logout(context),
          );
        }

        final role = roleSnap.data ?? 'unknown';

        // ADMIN: require both Users role AND token claim
if (role == 'admin') {
  return FutureBuilder<bool>(
    future: _hasAdminClaim(user),
    builder: (context, claimSnap) {
      if (claimSnap.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }

      if (claimSnap.hasError) {
        return _RoleErrorPage(
          message: "Failed to check admin claim.\n\n${claimSnap.error}",
          actionLabel: "Logout",
          onAction: () => _logout(context),
        );
      }

      final isAdmin = claimSnap.data == true;
      if (!isAdmin) {
        return _RoleErrorPage(
          message:
              "This account is marked as Admin in Users/{uid}, but your token has no admin claim.\n\n"
              "Ask an existing admin to grant your admin claim, then LOGOUT + LOGIN to refresh.",
          actionLabel: "Logout",
          onAction: () => _logout(context),
        );
      }
      return const AdminUsersDashboardPage();
    },
  );
}

        if (role == 'collector') return const  CollectorsDashboardPage();
        if (role == 'user') return const DashboardPage();

        if (role == 'junkshop') {
          return FutureBuilder<bool>(
            future: _junkshopDocExists(user.uid),
            builder: (context, junkSnap) {
              if (junkSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }

              if (junkSnap.hasError) {
                return _RoleErrorPage(
                  message: "Failed to load junkshop profile.\n\n${junkSnap.error}",
                  actionLabel: "Logout",
                  onAction: () => _logout(context),
                );
              }

              final exists = junkSnap.data == true;
              if (!exists) {
                return _RoleErrorPage(
                  message:
                      "This account is marked as Junkshop, but Junkshop profile is missing.\n\n"
                      "Please contact admin or re-register the shop profile.",
                  actionLabel: "Logout",
                  onAction: () => _logout(context),
                );
              }

              return JunkshopDashboardPage(shopID: user.uid);
            },
          );
        }

        // Unknown / invalid role
        return _RoleErrorPage(
          message:
              "No valid role found for this account.\n\n"
              "Fix Users/{uid}.Roles to one of: admin, user, junkshop, collector.",
          actionLabel: "Logout",
          onAction: () => _logout(context),
        );
      },
    );
  }
}

class _RoleErrorPage extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _RoleErrorPage({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (actionLabel != null && onAction != null)
                ElevatedButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
