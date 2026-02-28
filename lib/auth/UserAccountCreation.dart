import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

import 'package:ecoscrap_app/security/kyc_cyrpto.dart';
import 'package:ecoscrap_app/security/kyc_shared_key.dart';
import 'package:ecoscrap_app/security/admin_public_key.dart';

class UserAccountCreationPage extends StatefulWidget {
  const UserAccountCreationPage({super.key});

  @override
  State<UserAccountCreationPage> createState() => _UserAccountCreationPageState();
}

class _UserAccountCreationPageState extends State<UserAccountCreationPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  PlatformFile? _pickedFile; // REQUIRED government ID
  bool _isLoading = false;

  static const Color _bg = Color(0xFF0F172A);
  static const Color _primary = Color(0xFF1FA9A7);

  @override
  void initState() {
    super.initState();

    // ✅ Re-validate confirm password when password changes
    _passwordController.addListener(() {
      if (_confirmPasswordController.text.isNotEmpty) {
        _formKey.currentState?.validate();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ---------- UI helpers ----------
  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent : _primary,
      ),
    );
  }

  Future<void> _showInfoDialog({
    required String title,
    required String message,
    IconData icon = Icons.info_outline,
  }) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        actionsPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(icon, color: _primary),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // ---------- file picking ----------
  Future<void> _pickIdFile() async {
    await _showInfoDialog(
      title: "Palo Alto Residency Verification",
      icon: Icons.verified_user_outlined,
      message:
          "To create an account, you must upload a valid Government-issued ID.\n\n"
          "This is required to verify you RESIDE IN PALO ALTO.\n\n"
          "Accepted IDs:\n"
          "• Driver’s License\n"
          "• National ID\n"
          "• Voter’s ID\n"
          "• Other valid Government-issued ID\n\n"
          "Accepted file types: JPG, PNG, PDF (max 10MB).\n"
          "Please upload a clear photo/scan.",
    );

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) {
      _toast("Invalid file. Please try again.", error: true);
      return;
    }

    if (file.size > 10 * 1024 * 1024) {
      _toast("File too large (Max 10MB).", error: true);
      return;
    }

    final ext = (file.extension ?? "").toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'pdf'].contains(ext)) {
      _toast("Invalid file type. Use JPG/PNG/PDF only.", error: true);
      return;
    }

    setState(() => _pickedFile = file);

    await _showInfoDialog(
      title: "ID Selected",
      icon: Icons.check_circle_outline,
      message:
          "Selected: ${file.name}\n\n"
          "Security note:\n"
          "Your ID will be encrypted and used ONLY to verify Palo Alto residency.\n"
          "It will not be shared publicly.",
    );
  }

  String _randId([int len = 16]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  // =====================================================
  // ✅ Encrypt + Upload KYC (resident)
  // Storage gets ONLY encrypted bytes
  // Saves decrypt metadata to residentKYC/{uid} (admin-only)
  // =====================================================
  Future<void> _uploadEncryptedResidentKyc({
    required String uid,
    required Uint8List fileBytes,
    required String originalFileName,
  }) async {
    final eph = await KycSharedKey.newEphemeral();
    final ephPubBytes = await KycSharedKey.publicKeyBytes(eph);

    final salt = KycSharedKey.randomSalt16();
    final nonce = KycCrypto.randomNonce12();

    final aesKey = await KycSharedKey.deriveForCollector(
      ephKeyPair: eph,
      adminPublicKeyB64: AdminPublicKey.adminPublicKeyB64,
      salt: salt,
    );

    final enc = await KycCrypto.encryptBytes(
      plain: fileBytes,
      key: aesKey,
      nonce12: nonce,
      aad: utf8.encode(uid),
    );

    final encryptedName = "$originalFileName.enc";
    final storagePath = "resident_kyc/$uid/$encryptedName";

    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(
      enc.cipherText,
      SettableMetadata(contentType: "application/octet-stream"),
    );

    final db = FirebaseFirestore.instance;
    await db.collection("residentKYC").doc(uid).set({
      "uid": uid,
      "status": "pending",
      "hasKycFile": true,
      "storagePath": storagePath,
      "originalFileName": originalFileName,
      "ephPubKeyB64": base64Encode(ephPubBytes),
      "saltB64": base64Encode(Uint8List.fromList(salt)),
      "nonceB64": base64Encode(enc.nonce),
      "macB64": base64Encode(enc.macBytes),
      "submittedAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---------- registration ----------
  Future<void> _createAccount() async {
    if (_isLoading) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    // Form validation
    if (!_formKey.currentState!.validate()) return;

    // ✅ REQUIRED ID
    if (_pickedFile == null) {
      _toast("Government ID is required for Palo Alto verification.", error: true);
      return;
    }

    // Extra guard (in case validators change)
    if (password != confirmPassword) {
      _toast("Passwords do not match.", error: true);
      return;
    }

    setState(() => _isLoading = true);

    Reference? uploadedEncryptedRef;

    try {
      // 1) Create user in Auth
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final user = userCredential.user!;
      final uid = user.uid;

      // 2) Upload encrypted ID
      final ext = (_pickedFile!.extension ?? "").toLowerCase();
      final normalizedExt = (ext == "jpeg") ? "jpg" : ext;

      final rid = _randId();
      final kycFileName = "resident_id_$rid.$normalizedExt";
      final bytes = await File(_pickedFile!.path!).readAsBytes();

      await _uploadEncryptedResidentKyc(
        uid: uid,
        fileBytes: Uint8List.fromList(bytes),
        originalFileName: kycFileName,
      );

      final storagePath = "resident_kyc/$uid/$kycFileName.enc";
      uploadedEncryptedRef = FirebaseStorage.instance.ref(storagePath);

      // 3) Save user + request docs
      final db = FirebaseFirestore.instance;
      final userRef = db.collection("Users").doc(uid);
      final reqRef = db.collection("residentRequests").doc(uid);

      await db.runTransaction((tx) async {
        // Users/{uid}
        tx.set(userRef, {
          "UserID": uid,
          "Name": name,
          "Email": email,

          // normalized role
          "role": "user",
          "Roles": "user",

          // ✅ REQUIRED for access gating
          "adminVerified": false,
          "adminStatus": "pending",
          "adminReviewedAt": FieldValue.delete(),

          // optional mirror field
          "residentStatus": "pending",

          "CreatedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // residentRequests/{uid}
        tx.set(reqRef, {
          "uid": uid,
          "publicName": name,
          "emailDisplay": email,

          "hasKycFile": true,
          "status": "pending",
          "adminVerified": false,
          "adminStatus": "pending",

          "submittedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      // 4) Update display name + send verification
      await user.updateDisplayName(name);
      await user.sendEmailVerification();

      _toast("Verification email sent! Please check your inbox.");

      // 5) Logout (prevents access until they verify + admin approves)
      await FirebaseAuth.instance.signOut();
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? "Authentication failed", error: true);
    } catch (e) {
      // cleanup encrypted blob if something failed after upload
      if (uploadedEncryptedRef != null) {
        try {
          await uploadedEncryptedRef.delete();
        } catch (_) {}
      }
      _toast("An unexpected error occurred: $e", error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text("User Registration"),
        backgroundColor: _bg,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _HeroHeaderUser(),

                const SizedBox(height: 14),

                _InfoCard(
                  title: "Palo Alto Residents Only",
                  icon: Icons.location_on_outlined,
                  children: const [
                    Text(
                      "This app is strictly for residents of Palo Alto. "
                      "To protect the community and ensure correct service coverage, we require identity and residency validation.",
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                    SizedBox(height: 10),
                    _Bullet(text: "Prevents fake / out-of-area accounts"),
                    _Bullet(text: "Ensures services are for Palo Alto only"),
                    _Bullet(text: "Improves safety and trust in the platform"),
                  ],
                ),

                const SizedBox(height: 12),

                _InfoCard(
                  title: "Government ID Required",
                  icon: Icons.badge_outlined,
                  children: const [
                    _Bullet(text: "Driver’s License"),
                    _Bullet(text: "National ID"),
                    _Bullet(text: "Voter’s ID"),
                    _Bullet(text: "Other valid Government-issued ID"),
                    SizedBox(height: 10),
                    Text(
                      "File types: JPG, PNG, PDF (max 10MB). Upload a clear photo/scan.\n\n"
                      "Your ID will be reviewed by admins to confirm you reside in Palo Alto.",
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                _InfoCard(
                  title: "Your Security is our Priority",
                  icon: Icons.lock_outline,
                  children: const [
                    Text(
                      "Your ID is encrypted and used ONLY for Palo Alto residency verification. "
                      "It will not be shared publicly or used for any other purpose.",
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                const _SectionTitle("Account Details"),
                const SizedBox(height: 10),

                _buildTextField(
                  _nameController,
                  "Full Name",
                  Icons.person_outline,
                  type: _FieldType.name,
                ),
                const SizedBox(height: 15),
                _buildTextField(
                  _emailController,
                  "Email",
                  Icons.email_outlined,
                  type: _FieldType.email,
                ),
                const SizedBox(height: 15),
                _buildTextField(
                  _passwordController,
                  "Password",
                  Icons.lock_outline,
                  isObscure: true,
                  type: _FieldType.password,
                ),
                const SizedBox(height: 15),
                _buildTextField(
                  _confirmPasswordController,
                  "Confirm Password",
                  Icons.lock_reset,
                  isObscure: true,
                  type: _FieldType.confirmPassword,
                ),

                const SizedBox(height: 18),

                _UploadTile(
                  requiredLabel: true,
                  pickedFileName: _pickedFile?.name,
                  onTap: _isLoading ? null : _pickIdFile,
                  onRemove: _isLoading || _pickedFile == null
                      ? null
                      : () => setState(() => _pickedFile = null),
                ),

                const SizedBox(height: 25),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isLoading ? null : _createAccount,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            "Create Account",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                  ),
                ),

                const SizedBox(height: 10),
                const Text(
                  "By creating an account, you agree that the information provided is true and correct.\n"
                  "Access is granted only after email verification and admin approval.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isObscure = false,
    required _FieldType type,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isObscure,
      style: const TextStyle(color: Colors.white),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: _primary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary, width: 1.6),
        ),
      ),
      validator: (v) {
        final value = (v ?? "").trim();
        if (value.isEmpty) return "Required";

        switch (type) {
          case _FieldType.email:
            if (!value.contains("@") || !value.contains(".")) return "Enter a valid email";
            break;

          case _FieldType.password:
            if (value.length < 6) return "Password must be at least 6 characters";
            break;

          case _FieldType.confirmPassword:
            if (value != _passwordController.text.trim()) return "Passwords do not match";
            break;

          case _FieldType.name:
            break;
        }
        return null;
      },
    );
  }
}

// =========================
// UI Components
// =========================

enum _FieldType { name, email, password, confirmPassword }

class _HeroHeaderUser extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1FA9A7).withOpacity(0.25),
            Colors.white.withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF1FA9A7).withOpacity(0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.home_outlined, color: Color(0xFF7CF5F2)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Create a Resident Account",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  "Access is limited to verified Palo Alto residents. Upload a Government ID for approval.",
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF1FA9A7)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: Colors.white54),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  final String? pickedFileName;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final bool requiredLabel;

  const _UploadTile({
    required this.pickedFileName,
    required this.onTap,
    required this.onRemove,
    this.requiredLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile = pickedFileName != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1FA9A7).withOpacity(0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                hasFile ? Icons.check_circle_outline : Icons.upload_file,
                color: hasFile ? const Color(0xFF7CF5F2) : const Color(0xFF1FA9A7),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        hasFile ? "Government ID selected" : "Upload Government ID",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      if (requiredLabel)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
                          ),
                          child: const Text(
                            "REQUIRED",
                            style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasFile ? pickedFileName! : "JPG / PNG / PDF • Max 10MB",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (hasFile)
              SizedBox(
                width: 40,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: onRemove,
                  tooltip: "Remove",
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                ),
              )
            else
              const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}