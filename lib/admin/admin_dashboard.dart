import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final Map<String, Future<String>> _urlCache = {};

  Future<String> _getPermitUrlCached(String permitPath) {
    return _urlCache.putIfAbsent(
      permitPath,
      () => FirebaseStorage.instance.ref(permitPath).getDownloadURL(),
    );
  }

  Future<void> _setApproved(DocumentReference ref, bool value) async {
    await ref.update({'approved': value});
  }

  Future<void> _deleteRequest(DocumentReference ref, {String? permitPath}) async {
    // Optional: delete the storage file too
    if (permitPath != null && permitPath.isNotEmpty) {
      try {
        await FirebaseStorage.instance.ref(permitPath).delete();
      } catch (_) {
        // ignore
      }
    }
    await ref.delete();
  }

  void _showImageDialog(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _emptyBox(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            const Icon(Icons.mark_email_read, color: Colors.green),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }

  Widget _permitRequestsSection() {
    final stream = FirebaseFirestore.instance
        .collection('permitRequests')
        .orderBy('submittedAt', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text("Firestore error: ${snapshot.error}"),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyBox("No permit requests found.");
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final ref = doc.reference;
            final data = (doc.data() as Map<String, dynamic>? ?? {});

            final shopName = (data['shopName'] ?? 'Unknown').toString();
            final email = (data['email'] ?? '').toString();
            final permitPath = (data['permitPath'] ?? '').toString();
            final approved = data['approved'] == true;

            final ext = permitPath.split(".").last.toLowerCase();
            final isImage = ["png", "jpg", "jpeg"].contains(ext);
            final isPdf = ext == "pdf";

            return Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shopName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(email),
                    ],
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Chip(label: Text(approved ? "APPROVED" : "PENDING/REJECTED")),
                        const Spacer(),

                        TextButton.icon(
                          onPressed: () => _setApproved(ref, true),
                          icon: const Icon(Icons.check),
                          label: const Text("Approve"),
                        ),
                        const SizedBox(width: 6),

                        TextButton.icon(
                          onPressed: () => _setApproved(ref, false),
                          icon: const Icon(Icons.close),
                          label: const Text("Reject"),
                        ),
                        const SizedBox(width: 6),

                        IconButton(
                          tooltip: "Delete request",
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text("Delete request?"),
                                content: const Text("This removes the permit request document from Firestore."),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text("Cancel"),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text("Delete"),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await _deleteRequest(ref, permitPath: permitPath);
                            }
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    if (permitPath.isEmpty)
                      const Text("No permitPath found in this request.")
                    else
                      FutureBuilder<String>(
                        future: _getPermitUrlCached(permitPath),
                        builder: (context, urlSnap) {
                          if (urlSnap.connectionState == ConnectionState.waiting) {
                            return const SizedBox(
                              height: 200,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (urlSnap.hasError || !urlSnap.hasData) {
                            return Text("Permit load failed: ${urlSnap.error}");
                          }

                          final url = urlSnap.data!;

                          if (isPdf) {
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.picture_as_pdf, color: Colors.red),
                                  const SizedBox(width: 10),
                                  const Expanded(child: Text("PDF uploaded (tap to open in browser).")),
                                  TextButton(
                                    onPressed: () {
                                      // simplest: open system browser using url_launcher if you have it
                                      // otherwise keep as info only.
                                      _showImageDialog(context, url); // will show blank for pdf, but harmless
                                    },
                                    child: const Text("Open"),
                                  ),
                                ],
                              ),
                            );
                          }

                          if (!isImage) {
                            return Text("Unsupported file type: .$ext");
                          }

                          return GestureDetector(
                            onTap: () => _showImageDialog(context, url),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                url,
                                height: 220,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, e, __) => Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text("Render error: $e"),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Dashboard (Permits)")),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle("Permit Requests"),
            _permitRequestsSection(),
          ],
        ),
      ),
    );
  }
}