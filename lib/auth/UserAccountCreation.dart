import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:path_provider/path_provider.dart';
import 'package:edge_detection_plus/edge_detection_plus.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:ecoscrap_app/security/kyc_cyrpto.dart';
import 'package:ecoscrap_app/security/kyc_shared_key.dart';
import 'package:ecoscrap_app/security/admin_public_key.dart';
import 'package:ecoscrap_app/security/resident_address_crypto.dart';

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

  // Address still becomes one final string
  final _blockController = TextEditingController();
  final _lotController = TextEditingController();

  String? _selectedSubdivision;

  final List<String> _subdivisionOptions = const [
    'San Francisco Heights (Suntrust)',
    'PHirst Park Homes Calamba',
    'Lynville Residences Palo Alto',
    'Palo Alto Executive Village',
    'Southwynd Residences',
    'Pacific Hill Subdivision',
    'Hacienda Hill',
    'Palo Alto Highland 1',
    'Palo Alto Highland 2',
  ];

  String? _scannedIdPath;
  bool _isLoading = false;

  static const Color _bg = Color(0xFF0F172A);
  static const Color _primary = Color(0xFF1FA9A7);

  @override
  void initState() {
    super.initState();

    _passwordController.addListener(() {
      if (_confirmPasswordController.text.isNotEmpty) {
        _formKey.currentState?.validate();
      }
      if (mounted) setState(() {});
    });

    _nameController.addListener(_refresh);
    _emailController.addListener(_refresh);
    _confirmPasswordController.addListener(_refresh);
    _blockController.addListener(_refresh);
    _lotController.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _blockController.dispose();
    _lotController.dispose();
    super.dispose();
  }

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

  bool get _canSubmit {
    return !_isLoading &&
        _nameController.text.trim().isNotEmpty &&
        _emailController.text.trim().isNotEmpty &&
        _passwordController.text.trim().isNotEmpty &&
        _confirmPasswordController.text.trim().isNotEmpty &&
        _blockController.text.trim().isNotEmpty &&
        _lotController.text.trim().isNotEmpty &&
        _selectedSubdivision != null &&
        _selectedSubdivision!.trim().isNotEmpty &&
        _scannedIdPath != null;
  }

  String _buildFormattedAddress() {
    final block = _blockController.text.trim();
    final lot = _lotController.text.trim();
    final subdivision = _selectedSubdivision?.trim() ?? '';

    return "Block $block Lot $lot, $subdivision";
  }

  String _normalizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _doesScannedNameMatch({
    required String scannedText,
    required String declaredName,
  }) {
    final normalizedScanned = _normalizeText(scannedText);
    final normalizedDeclared = _normalizeText(declaredName);

    if (normalizedDeclared.isEmpty) return false;

    if (normalizedScanned.contains(normalizedDeclared)) {
      return true;
    }

    final parts = normalizedDeclared
        .split(' ')
        .where((p) => p.trim().length >= 2)
        .toList();

    if (parts.isEmpty) return false;

    int matches = 0;
    for (final part in parts) {
      if (normalizedScanned.contains(part)) {
        matches++;
      }
    }

    final requiredMatches = parts.length >= 2 ? 2 : 1;
    return matches >= requiredMatches;
  }

  Future<bool> _validateScannedId({
    required String imagePath,
    required String declaredName,
  }) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final recognizedText = await textRecognizer.processImage(inputImage);
      final rawText = recognizedText.text;
      final text = rawText.toLowerCase();

      if (rawText.trim().isEmpty) return false;
      if (rawText.length < 20) return false;

      final hasPaloAlto = text.contains('palo alto');
      final hasMatchingName = _doesScannedNameMatch(
        scannedText: rawText,
        declaredName: declaredName,
      );

      return hasPaloAlto && hasMatchingName;
    } catch (_) {
      return false;
    } finally {
      await textRecognizer.close();
    }
  }

  Future<void> _scanGovernmentId() async {
    await _showInfoDialog(
      title: "Scan ID",
      icon: Icons.document_scanner_outlined,
      message:
"Please scan your ID.\n\n"
"Place it clearly inside the frame and remove any surrounding objects.",
    );

    try {
      final declaredName = _nameController.text.trim();

      if (declaredName.isEmpty) {
        _toast("Please enter your name before scanning your ID.", error: true);
        return;
      }

      final dir = await getTemporaryDirectory();
      final outputPath =
          "${dir.path}/resident_id_${DateTime.now().millisecondsSinceEpoch}.jpg";

      final bool isScanned = await EdgeDetectionPlus.detectEdge(
        outputPath,
        canUseGallery: false,
      );

      if (!isScanned) return;

      final file = File(outputPath);
      if (!await file.exists()) {
        _toast("Failed to get scanned ID. Please try again.", error: true);
        return;
      }

      final size = await file.length();
      if (size > 10 * 1024 * 1024) {
        _toast("Scanned file is too large (Max 10MB). Please rescan.", error: true);
        return;
      }

      final isValid = await _validateScannedId(
        imagePath: outputPath,
        declaredName: declaredName,
      );

      if (!isValid) {
        _toast(
          "Scan rejected. Please make sure you are using your own ID and that it is clearly captured inside the frame.",
          error: true,
        );
        return;
      }

      setState(() => _scannedIdPath = outputPath);

      await _showInfoDialog(
        title: "ID Accepted",
        icon: Icons.check_circle_outline,
        message:
"Your ID has been captured successfully.\n\nIt will be reviewed by the admin.",
      );
    } on PlatformException catch (e) {
      _toast("Scanner failed: ${e.message ?? e.code}", error: true);
    } catch (e) {
      _toast("Failed to scan ID: $e", error: true);
    }
  }

  String _randId([int len = 16]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

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

    final randomId = _randId();
    final storagePath = "kyc_secure/$randomId.enc";

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

  Future<void> _createAccount() async {
    if (_isLoading) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final address = _buildFormattedAddress();

    if (!_formKey.currentState!.validate()) return;

    if (_selectedSubdivision == null || _selectedSubdivision!.trim().isEmpty) {
      _toast("Subdivision is required.", error: true);
      return;
    }

    if (_scannedIdPath == null) {
      _toast("Please scan your ID to continue.", error: true);
      return;
    }

    if (password != confirmPassword) {
      _toast("Passwords do not match.", error: true);
      return;
    }

    setState(() => _isLoading = true);

    String? storagePathForPossibleCleanup;

    try {
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final user = userCredential.user!;
      final uid = user.uid;

      final addressEnc = await ResidentAddressCrypto.encryptForAdmin(
        uid: uid,
        address: address,
      );

      final rid = _randId();
      final kycFileName = "resident_id_$rid.jpg";
      final bytes = await File(_scannedIdPath!).readAsBytes();

      await _uploadEncryptedResidentKyc(
        uid: uid,
        fileBytes: Uint8List.fromList(bytes),
        originalFileName: kycFileName,
      );

      final kycDoc =
          await FirebaseFirestore.instance.collection("residentKYC").doc(uid).get();
      storagePathForPossibleCleanup =
          (kycDoc.data()?["storagePath"] ?? "").toString().trim();

      final db = FirebaseFirestore.instance;
      final userRef = db.collection("Users").doc(uid);
      final reqRef = db.collection("residentRequests").doc(uid);
      final kycRef = db.collection("residentKYC").doc(uid);

      await db.runTransaction((tx) async {
        tx.set(userRef, {
          "UserID": uid,
          "Name": name,
          "Email": email,
          "role": "user",
          "Roles": "user",
          "adminVerified": false,
          "adminStatus": "pending",
          "adminReviewedAt": FieldValue.delete(),
          "residentStatus": "pending",
          "CreatedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

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

        tx.set(kycRef, {
          "uid": uid,
          "addressEnc": addressEnc,
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      await user.updateDisplayName(name);
      await user.sendEmailVerification();

      _toast("Verification email sent! Please check your inbox.");

      await FirebaseAuth.instance.signOut();
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? "Authentication failed", error: true);
    } catch (e) {
      if (storagePathForPossibleCleanup != null &&
          storagePathForPossibleCleanup.isNotEmpty) {
        try {
          await FirebaseStorage.instance.ref(storagePathForPossibleCleanup).delete();
        } catch (_) {}
      }
      _toast("An unexpected error occurred: $e", error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _fileNameOnly(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isObscure = false,
    required _FieldType type,
  }) {
    final isNumeric =
        type == _FieldType.blockNumber || type == _FieldType.lotNumber;

    return TextFormField(
      controller: controller,
      obscureText: isObscure,
      maxLines: 1,
      keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
      inputFormatters:
          isNumeric ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: const TextStyle(color: Colors.white),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: _primary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
        ),
      ),
      validator: (v) {
        final value = (v ?? "").trim();
        if (value.isEmpty) return "Required";

        switch (type) {
          case _FieldType.email:
            if (!value.contains("@") || !value.contains(".")) {
              return "Enter a valid email";
            }
            break;

          case _FieldType.password:
            if (value.length < 6) {
              return "Password must be at least 6 characters";
            }
            break;

          case _FieldType.confirmPassword:
            if (value != _passwordController.text.trim()) {
              return "Passwords do not match";
            }
            break;

          case _FieldType.blockNumber:
          case _FieldType.lotNumber:
            if (int.tryParse(value) == null) {
              return "Numbers only";
            }
            break;

          case _FieldType.name:
            break;
        }
        return null;
      },
    );
  }

  Widget _buildSubdivisionDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedSubdivision,
      dropdownColor: const Color(0xFF1E293B),
      style: const TextStyle(color: Colors.white),
      iconEnabledColor: Colors.white70,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        labelText: "Subdivision",
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: const Icon(Icons.apartment_outlined, color: _primary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
        ),
      ),
      items: _subdivisionOptions
          .map(
            (subdivision) => DropdownMenuItem<String>(
              value: subdivision,
              child: Text(
                subdivision,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          )
          .toList(),
      onChanged: _isLoading
          ? null
          : (value) {
              setState(() {
                _selectedSubdivision = value;
              });
            },
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return "Required";
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          "User Registration",
          style: TextStyle(color: Colors.white),
        ),
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
                      "This app is strictly for residents of Palo Alto.",
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                _InfoCard(
                  title: "ID Verification Required",
                  icon: Icons.badge_outlined,
                  children: const [
                    _Bullet(text: "Scanner must detect and crop the ID"),
                    _Bullet(text: "Make sure the ID is clear and readable"),
                    _Bullet(text: "Use your own ID when registering"),
                    _Bullet(text: "Admin will still review before approval"),
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

                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        _blockController,
                        "Block",
                        Icons.home_work_outlined,
                        type: _FieldType.blockNumber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTextField(
                        _lotController,
                        "Lot",
                        Icons.numbers_outlined,
                        type: _FieldType.lotNumber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                _buildSubdivisionDropdown(),
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

                _ScanTile(
                  requiredLabel: true,
                  pickedFileName:
                      _scannedIdPath == null ? null : _fileNameOnly(_scannedIdPath!),
                  onTap: _isLoading ? null : _scanGovernmentId,
                  onRemove: _isLoading || _scannedIdPath == null
                      ? null
                      : () => setState(() => _scannedIdPath = null),
                ),

                if (_scannedIdPath != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      File(_scannedIdPath!),
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],

                const SizedBox(height: 25),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      disabledBackgroundColor: _primary.withOpacity(0.45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _canSubmit ? _createAccount : null,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            "Create Account",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _FieldType {
  name,
  email,
  blockNumber,
  lotNumber,
  password,
  confirmPassword,
}

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
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  "Scan an ID that clearly shows Palo Alto.",
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
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

class _ScanTile extends StatelessWidget {
  final String? pickedFileName;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final bool requiredLabel;

  const _ScanTile({
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
                hasFile
                    ? Icons.check_circle_outline
                    : Icons.document_scanner_outlined,
                color: hasFile
                    ? const Color(0xFF7CF5F2)
                    : const Color(0xFF1FA9A7),
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
                        hasFile ? "ID accepted" : "Scan ID",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (requiredLabel)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: Colors.redAccent.withOpacity(0.35)),
                          ),
                          child: const Text(
                            "REQUIRED",
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasFile
                        ? pickedFileName!
                        : "Scan your ID for account verification.",
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