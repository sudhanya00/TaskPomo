import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final provider = GoogleAuthProvider();
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        await FirebaseAuth.instance.signInWithProvider(provider);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = Ledger.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TickDial(progress: .38, size: 64),
              const Spacer(),
              Text('A few minutes', style: Typo.serif(52, color: l.ink)),
              Text(
                'a day, every day.',
                style: Typo.serif(52, color: l.muted, italic: true),
              ),
              const SizedBox(height: 22),
              Text(
                'Set a small daily target for the things you want to get better at. '
                'Show up, keep the streak.',
                style: Typo.sans(15, color: l.muted, height: 1.55),
              ),
              const Spacer(),
              if (_error != null) ...[
                Text(_error!, style: Typo.sans(13, color: l.accent)),
                const SizedBox(height: 12),
              ],
              LedgerButton(
                label: _busy ? 'Signing in…' : 'Continue with Google',
                icon: Ic.google,
                filled: true,
                onPressed: _busy ? null : _signIn,
              ),
              const SizedBox(height: 14),
              Center(child: Eyebrow('TaskPomo')),
            ],
          ),
        ),
      ),
    );
  }
}
