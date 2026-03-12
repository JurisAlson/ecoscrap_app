import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth/email_verification_page.dart';
import 'admin/admin_home_page.dart';
import 'auth/login_page.dart';
import 'Collector/collectors_dashboard.dart';
import 'household/household_dashboard.dart';
import 'auth/restricted_account_page.dart';
import 'screens/junkshop/junkshop_dashboard.dart';

// Future<void> grantMeAdminClaimIfOwner(User user) async {
//   if (user.email?.toLowerCase() != "jurisalson@gmail.com") return;

//   final callable = FirebaseFunctions.instanceFor(region: "asia-southeast1")
//       .httpsCallable("setAdminClaim");

//   await callable.call({
//     "uid": user.uid,
//     "makeAdmin": true,
//   });

//   await user.getIdTokenResult(true);
// }

class RoleGate extends StatefulWidget {
  const RoleGate({super.key});

  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> with WidgetsBindingObserver {
  String _normRole(dynamic raw) {
    final s = (raw ?? "").toString().trim().toLowerCase();

    if (s == "admins" || s == "admin") return "admin";
    if (s == "collectors" || s == "collector") return "collector";
    if (s == "junkshop" || s == "junkshops") return "junkshop";
    if (s == "users" ||
        s == "user" ||
        s == "household" ||
        s == "households") {
      return "user";
    }

    return "unknown";
  }

  static const Map<String, String> restrictionReasonMap = {
    "potential_fake": "Potential fake account / identity",
    "false_information": "False information",
    "suspicious_activity": "Suspicious activity / fraud",
    "spam_abuse": "Spam / abuse",
    "duplicate_account": "Duplicate account",
    "policy_violation": "Violation of app rules / policy",
    "other": "Others",
  };

  Map<String, String> _buildRestrictionInfo(Map<String, dynamic> data) {
    final reasonCode = (data['restrictedReasonCode'] ?? '').toString().trim();
    final reasonText = (data['restrictedReasonText'] ?? '').toString().trim();

    final title = (reasonCode.isNotEmpty)
        ? (restrictionReasonMap[reasonCode] ?? "Restricted")
        : "Restricted";

    String details;

    if (reasonCode == "other" && reasonText.isNotEmpty) {
      details =
          "Admin note:\n$reasonText\n\n"
          "If you believe this is a mistake, please contact the admin and provide supporting details.";
    } else if (reasonCode.isNotEmpty) {
      details =
          "Your account was restricted due to:\n$title\n\n"
          "You can still sign in, but you cannot use EcoScrap until the admin reviews your account.\n\n"
          "If you believe this is a mistake, contact the admin and request an appeal/unrestriction.";
    } else {
      details =
          "Your account has been restricted by an administrator.\n\n"
          "If you believe this is a mistake, please contact the admin to request a review.";
    }

    return {
      "title": title,
      "details": details,
    };
  }

  bool _isResidentApproved(Map<String, dynamic> data) {
    final residentStatus =
        (data['residentStatus'] ?? "").toString().trim().toLowerCase();
    return residentStatus == "approved";
  }

  bool _isCollectorApproved(Map<String, dynamic> data) {
    final status =
        (data['collectorStatus'] ?? "").toString().trim().toLowerCase();

    if (status == "adminapproved") return true;
    if (status == "approved") return true;

    final legacyAdminOk = data['adminVerified'] == true;
    final legacyAdminStatus =
        (data['adminStatus'] ?? "").toString().toLowerCase() == "approved";
    final legacyActive = data['collectorActive'] == true;

    return legacyAdminOk && legacyAdminStatus && legacyActive;
  }

  Future<bool> _hasAdminClaim(User user) async {
    final token = await user.getIdTokenResult(true);
    return token.claims?['admin'] == true;
  }

  Future<void> _setOnline(bool online) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance.collection('Users').doc(uid).set({
      'isOnline': online,
      if (!online) 'lastSeen': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _logout(BuildContext context) async {
    await _setOnline(false);
    await FirebaseAuth.instance.signOut();

    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _setOnline(true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setOnline(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnline(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _setOnline(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const LoginPage();

    return FutureBuilder<void>(
      future: user.reload(),
      builder: (context, reloadSnap) {
        if (reloadSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final refreshedUser = FirebaseAuth.instance.currentUser;
        if (refreshedUser == null) return const LoginPage();

        if (!refreshedUser.emailVerified) {
          return EmailVerificationPage(user: refreshedUser);
        }

        final docStream = FirebaseFirestore.instance
            .collection('Users')
            .doc(refreshedUser.uid)
            .snapshots();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: docStream,
          builder: (context, docSnap) {
            if (docSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
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

            final status =
                (data['status'] ?? 'active').toString().trim().toLowerCase();

            if (status == "restricted") {
              final info = _buildRestrictionInfo(data);
              return RestrictedAccountPage(
                reasonTitle: info["title"] ?? "Restricted",
                reasonDetails: info["details"] ?? "",
                uid: refreshedUser.uid,
                email: refreshedUser.email,
              );
            }

            final role =
                _normRole(data['Roles'] ?? data['roles'] ?? data['role']);

            debugPrint(
              "RoleGate => role=$role | status=$status | residentStatus=${data['residentStatus']} | collectorStatus=${data['collectorStatus']}",
            );

            if (role == 'admin') {
              return FutureBuilder<bool>(
                future: _hasAdminClaim(refreshedUser),
                builder: (context, claimSnap) {
                  if (claimSnap.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
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

            if (role == 'collector') {
              final ok = _isCollectorApproved(data);

              if (!ok) {
                final cs =
                    (data['collectorStatus'] ?? "").toString().toLowerCase();

                final msg = cs == "rejected"
                    ? "Your collector request was rejected.\n\nPlease resubmit your application."
                    : "Your collector account is not verified yet.\n\nPlease wait for admin approval.";

                return _RoleErrorPage(
                  message: msg,
                  actionLabel: "Logout",
                  onAction: () => _logout(context),
                );
              }

              return const CollectorsDashboardPage();
            }

            if (role == 'junkshop') {
              final shopName =
                  (data['Name'] ?? data['name'] ?? data['shopName'] ?? 'Junkshop')
                      .toString()
                      .trim();

              return JunkshopDashboardPage(
                shopID: refreshedUser.uid,
                shopName: shopName.isNotEmpty ? shopName : 'Junkshop',
              );
            }

            if (role == 'user') {
              final ok = _isResidentApproved(data);

              if (!ok) {
                final rs =
                    (data['residentStatus'] ?? "").toString().toLowerCase();

                final msg = rs == "rejected"
                    ? "Account verification rejected.\n\nPlease re-submit a valid Government ID."
                    : "Account pending verification.\n\nPlease wait for admin approval.";

                return _RoleErrorPage(
                  message: msg,
                  actionLabel: "Logout",
                  onAction: () => _logout(context),
                );
              }

              return const DashboardPage();
            }

            return _RoleErrorPage(
              message:
                  "No valid role found for this account.\n\n"
                  "Fix Users/{uid}.Roles to one of: admin, user, collector, junkshop.",
              actionLabel: "Logout",
              onAction: () => _logout(context),
            );
          },
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