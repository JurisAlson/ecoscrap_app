import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'admin/admin_home_page.dart';
import 'auth/login_page.dart';
import 'Collector/collectors_dashboard.dart';
import 'household/household_dashboard.dart';
import 'junkshop/junkshop_dashboard.dart';

Future<void> grantMeAdminClaimIfOwner(User user) async {
  if (user.email?.toLowerCase() != "jurisalson@gmail.com") return;

  final callable = FirebaseFunctions.instanceFor(region: "asia-southeast1")
      .httpsCallable("setAdminClaim");

    await callable.call({
      "uid": user.uid,
      "makeAdmin": true,
    });

  await user.getIdTokenResult(true); // refresh token
}

class RoleGate extends StatelessWidget {
  const RoleGate({super.key});

  String _normRole(dynamic raw) {
    final s = (raw ?? "").toString().trim().toLowerCase();
    if (s == "admins" || s == "admin") return "admin";
    if (s == "collectors" || s == "collector") return "collector";
    if (s == "junkshops" || s == "junkshop") return "junkshop";
    if (s == "users" || s == "user" || s == "household" || s == "households") return "user";
    return "unknown";
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _getUserDoc(String uid) {
    return FirebaseFirestore.instance.collection('Users').doc(uid).get();
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

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _getUserDoc(user.uid),
      builder: (context, docSnap) {
        if (docSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (docSnap.hasError) {
          return _RoleErrorPage(
            message: "Failed to load Users/{uid}.\n\n${docSnap.error}",
            actionLabel: "Logout",
            onAction: () => _logout(context),
          );
        }

        if (!docSnap.hasData || !docSnap.data!.exists) {
          return _RoleErrorPage(
            message:
                "Profile is missing in Users/{uid}.\n\n"
                "Please logout and login again. If it persists, contact admin.",
            actionLabel: "Logout",
            onAction: () => _logout(context),
          );
        }

        final data = docSnap.data!.data() ?? {};
        final role = _normRole(data['Roles'] ?? data['roles'] ?? data['role']);

        // ================= ADMIN =================
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

              return const AdminHomePage();
            },
          );
        }

        // ================= COLLECTOR =================
// ================= COLLECTOR =================
        if (role == 'collector') {
          final ok = data["junkshopVerified"] == true ||
              (data["junkshopStatus"] ?? "").toString().toLowerCase() == "verified";

          if (!ok) {
            final status = (data["junkshopStatus"] ?? "pending").toString();
            return _RoleErrorPage(
              message:
                  "Collector is not yet verified by a junkshop.\n\n"
                  "Status: $status\n\n"
                  "Please wait for a junkshop to accept you.",
              actionLabel: "Logout",
              onAction: () => _logout(context),
            );
          }

          return const CollectorsDashboardPage();
        }

        // ================= USER =================
        if (role == 'user') {
          return const DashboardPage();
        }

        // ================= JUNKSHOP =================
        if (role == 'junkshop') {
          final verified = data["verified"] == true;
          final shopName = (data["shopName"] ?? data["name"] ?? "Junkshop").toString();

          // If you want to block unverified junkshops:
          if (!verified) {
            final status = (data["junkshopStatus"] ?? "pending").toString();
            return _RoleErrorPage(
              message:
                  "Junkshop application is not verified yet.\n\n"
                  "Status: $status\n\n"
                  "Please wait for admin approval.",
              actionLabel: "Logout",
              onAction: () => _logout(context),
            );
          }

          // Verified -> proceed
          return JunkshopDashboardPage(
            shopID: user.uid,
            shopName: shopName,
          );
        }

        // ================= UNKNOWN =================
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