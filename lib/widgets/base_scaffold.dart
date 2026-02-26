import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BaseScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final bool showBackButton;

  const BaseScaffold({
    super.key,
    required this.title,
    required this.body,
    this.showBackButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: showBackButton,
        leading: showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: body,
    );
  }
}

class BellWithDot extends StatelessWidget {
  const BellWithDot({
    super.key,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return IconButton(
        onPressed: onTap,
        icon: Icon(Icons.notifications_none, color: iconColor),
      );
    }

    final Query<Map<String, dynamic>> unreadQuery = FirebaseFirestore.instance
        .collection("Users")
        .doc(uid)
        .collection("notifications")
        .where("read", isEqualTo: false);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: unreadQuery.snapshots(),
      builder: (context, snap) {
        final unreadCount = snap.data?.size ?? 0;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              onPressed: onTap,
              icon: Icon(Icons.notifications_none, color: iconColor),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black26, width: 1),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}