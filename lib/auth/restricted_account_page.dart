import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RestrictedAccountPage extends StatelessWidget {
  final String reasonTitle;     // e.g. "False information"
  final String reasonDetails;   // e.g. "Your profile contains inconsistent details..."
  final String? uid;
  final String? email;

  const RestrictedAccountPage({
    super.key,
    required this.reasonTitle,
    required this.reasonDetails,
    this.uid,
    this.email,
  });

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.orangeAccent.withOpacity(0.25)),
                    ),
                    child: const Icon(Icons.block, color: Colors.orangeAccent),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Account Restricted",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Main Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Why you’re seeing this",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Your access to EcoScrap has been restricted by an administrator. You can still log in, but you cannot use the app until this is resolved.",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.80),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Reason badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.orangeAccent.withOpacity(0.25)),
                      ),
                      child: Text(
                        "Reason: $reasonTitle",
                        style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),

                    if (reasonDetails.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        reasonDetails,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.78),
                          height: 1.35,
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Optional info
                    if ((email ?? "").isNotEmpty || (uid ?? "").isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.07)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((email ?? "").isNotEmpty)
                              Text(
                                "Email: $email",
                                style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
                              ),
                            if ((uid ?? "").isNotEmpty)
                              Text(
                                "UID: $uid",
                                style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12),
                              ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 14),

                    const Text(
                      "What you can do",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "• Review your information and make sure it is accurate.\n"
                      "• Contact the admin to request an appeal/unrestriction.\n"
                      "• If this is a mistake, provide proof (ID / barangay certificate / etc.).",
                      style: TextStyle(color: Colors.white.withOpacity(0.78), height: 1.35),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withOpacity(0.18)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text(
                        "Log out",
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}