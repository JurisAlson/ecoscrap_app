import 'package:flutter/material.dart';

class AdminHelpers {
  static void toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static Future<T?> confirm<T>({
    required BuildContext context,
    required String title,
    required String body,
    required T yesValue,
    required String yesLabel,
    String noLabel = "Cancel",
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(noLabel)),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, yesValue), child: Text(yesLabel)),
        ],
      ),
    );
  }
}