import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PhoneAuthTestPage extends StatefulWidget {
  const PhoneAuthTestPage({super.key});

  @override
  State<PhoneAuthTestPage> createState() => _PhoneAuthTestPageState();
}

class _PhoneAuthTestPageState extends State<PhoneAuthTestPage> {
  final _auth = FirebaseAuth.instance;

  final _phoneCtrl = TextEditingController(text: '+63'); // change if needed
  final _codeCtrl = TextEditingController();

  String? _verificationId;
  int? _resendToken;

  bool _isSending = false;
  bool _isVerifying = false;

  String _status = 'Ready';
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    setState(() => _secondsLeft = seconds);

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _sendCode({bool forceResend = false}) async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty || !phone.startsWith('+')) {
      setState(() => _status = 'Use E.164 format e.g. +639xxxxxxxxx');
      return;
    }

    setState(() {
      _isSending = true;
      _status = forceResend ? 'Resending code...' : 'Sending code...';
    });

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: forceResend ? _resendToken : null,
        verificationCompleted: (PhoneAuthCredential credential) async {
          setState(() => _status = 'Auto verification completed. Signing in...');
          try {
            final res = await _auth.signInWithCredential(credential);
            setState(() => _status = 'Signed in! UID: ${res.user?.uid}');
          } catch (e) {
            setState(() => _status = 'Auto sign-in failed: $e');
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _status = 'Failed: ${e.code} - ${e.message}');
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _status = 'Code sent! Enter SMS code.';
          });
          _startTimer(60);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          setState(() {
            _verificationId = verificationId;
            _status = 'Timeout. You can still enter the code.';
          });
        },
      );
    } catch (e) {
      setState(() => _status = 'Send code error: $e');
    } finally {
      setState(() => _isSending = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (_verificationId == null) {
      setState(() => _status = 'Send code first.');
      return;
    }
    if (code.length < 4) {
      setState(() => _status = 'Enter the SMS code.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _status = 'Verifying...';
    });

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      final res = await _auth.signInWithCredential(credential);
      setState(() => _status = 'Signed in! UID: ${res.user?.uid}');
    } on FirebaseAuthException catch (e) {
      setState(() => _status = 'Verify failed: ${e.code} - ${e.message}');
    } catch (e) {
      setState(() => _status = 'Verify error: $e');
    } finally {
      setState(() => _isVerifying = false);
    }
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    setState(() => _status = 'Signed out.');
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _verificationId != null && _secondsLeft == 0 && !_isSending;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Phone SMS Test'),
        actions: [
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text('Phone must be in E.164 format (+countrycode + number).'),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isSending ? null : () => _sendCode(),
              icon: const Icon(Icons.sms),
              label: Text(_isSending ? 'Sending...' : 'Send SMS Code'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: canResend ? () => _sendCode(forceResend: true) : null,
              child: Text(
                canResend
                    ? 'Resend code'
                    : (_verificationId == null ? 'Resend (send first)' : 'Resend in $_secondsLeft s'),
              ),
            ),
            const Divider(height: 28),
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'SMS code',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isVerifying ? null : _verifyCode,
              icon: const Icon(Icons.verified),
              label: Text(_isVerifying ? 'Verifying...' : 'Verify & Sign In'),
            ),
            const SizedBox(height: 24),
            const Text('Status:'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade400),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_status),
            ),
          ],
        ),
      ),
    );
  }
}