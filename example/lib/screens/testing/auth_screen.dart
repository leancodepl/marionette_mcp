import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// §5 Auth UI: the system biometric sheet (local_auth) and autofill fields.
/// native_biometrics answers the sheet on emulators / simulators.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _auth = LocalAuthentication();
  String _biometrics = 'checking…';
  String _result = 'none';

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final supported = await _auth.isDeviceSupported();
    final enrolled = await _auth.getAvailableBiometrics();
    if (mounted) {
      setState(() => _biometrics = 'supported: $supported, enrolled: '
          '${enrolled.isEmpty ? 'none' : enrolled.map((b) => b.name).join(', ')}');
    }
  }

  Future<void> _authenticate() async {
    setState(() => _result = 'waiting…');
    String result;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Sign in to the Marionette example',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      result = ok ? 'success' : 'failed';
    } on PlatformException catch (error) {
      result = 'error ${error.code}';
    }
    if (mounted) setState(() => _result = result);
    await _checkBiometrics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auth UI'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Biometrics: $_biometrics'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _authenticate,
            child: const Text('Authenticate with biometrics'),
          ),
          Text('Biometric result: $_result'),
          const SizedBox(height: 24),
          Text(
            'Autofill: focusing these fields shows the system autofill / '
            'QuickType bar (native lane only).',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const AutofillGroup(
            child: Column(
              children: [
                TextField(
                  autofillHints: [AutofillHints.username],
                  decoration: InputDecoration(labelText: 'Username'),
                ),
                TextField(
                  autofillHints: [AutofillHints.password],
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'Password'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
