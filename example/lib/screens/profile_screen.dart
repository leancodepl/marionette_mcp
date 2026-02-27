import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  String _nameValue = '';
  String _emailValue = '';
  String _bioValue = '';
  bool _isFormValid = false;

  void _recomputeFormState() {
    final formIsValid = _formKey.currentState?.validate() ?? false;
    final canSubmit = formIsValid && _nameValue.trim().isNotEmpty;
    if (_isFormValid != canSubmit) {
      setState(() {
        _isFormValid = canSubmit;
      });
    }
  }

  String? _emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final email = value.trim();
    if (!email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email';
    }
    return null;
  }

  String? _bioValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Bio is required';
    }
    if (value.trim().length < 3) {
      return 'Bio must have at least 3 characters';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const ValueKey('name_field'),
              decoration: const InputDecoration(
                labelText: 'Name (TextField)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _nameValue = value;
                });
                _recomputeFormState();
              },
            ),
            const SizedBox(height: 12),
            Text('name_field onChanged: "$_nameValue"'),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('email_field'),
              decoration: const InputDecoration(
                labelText: 'Email (TextFormField)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: _emailValidator,
              onChanged: (value) {
                setState(() {
                  _emailValue = value;
                });
                _recomputeFormState();
              },
            ),
            const SizedBox(height: 12),
            Text('email_field onChanged: "$_emailValue"'),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('bio_field'),
              decoration: const InputDecoration(
                labelText: 'Bio (TextFormField + formatter)',
                border: OutlineInputBorder(),
                helperText: 'Max 20 chars, letters/numbers/spaces only',
              ),
              validator: _bioValidator,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 ]')),
                LengthLimitingTextInputFormatter(20),
              ],
              onChanged: (value) {
                setState(() {
                  _bioValue = value;
                });
                _recomputeFormState();
              },
            ),
            const SizedBox(height: 12),
            Text('bio_field onChanged: "$_bioValue"'),
            const SizedBox(height: 16),
            const TextField(
              key: ValueKey('readonly_field'),
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Read-only field (for edge-case testing)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isFormValid
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Form submitted')),
                      );
                    }
                  : null,
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }
}
