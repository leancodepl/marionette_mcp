import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

/// Scheme the login page redirects to; separate from the deep-link scheme
/// (marionette-example) so the two never compete.
const _callbackScheme = 'marionette-auth';

const _loginPage = '''
<!DOCTYPE html>
<html><head><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Marionette sign-in</title></head>
<body style="font-family: sans-serif; margin: 24px">
<h1>Marionette sign-in</h1>
<form action="/authorize" method="get">
  <label for="user">User name</label><br>
  <input id="user" name="user" aria-label="User name" style="font-size: 18px; width: 100%"><br><br>
  <button id="sign-in" type="submit" style="font-size: 18px">Sign in</button>
</form>
</body></html>
''';

/// §7 OAuth in the system browser (Custom Tabs / ASWebAuthenticationSession).
/// The login page is served by the app itself on 127.0.0.1, so no network
/// or external server is needed; signing in redirects to
/// marionette-auth://callback, which returns to the app.
class OAuthScreen extends StatefulWidget {
  const OAuthScreen({super.key});

  @override
  State<OAuthScreen> createState() => _OAuthScreenState();
}

class _OAuthScreenState extends State<OAuthScreen> {
  HttpServer? _server;
  String _result = 'none';

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  Future<Uri> _startServer() async {
    final server =
        _server ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
          ..listen((request) async {
            final response = request.response;
            if (request.uri.path == '/authorize') {
              final user = request.uri.queryParameters['user'] ?? '';
              response
                ..statusCode = HttpStatus.found
                ..headers.set(
                  HttpHeaders.locationHeader,
                  '$_callbackScheme://callback?code=demo-code&user='
                  '${Uri.encodeQueryComponent(user)}',
                );
            } else {
              response
                ..headers.contentType = ContentType.html
                ..write(_loginPage);
            }
            await response.close();
          });
    return Uri.parse('http://127.0.0.1:${server.port}/');
  }

  Future<void> _signIn() async {
    setState(() => _result = 'waiting…');
    String result;
    try {
      final url = await _startServer();
      final callback = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: _callbackScheme,
      );
      final query = Uri.parse(callback).queryParameters;
      result = 'code=${query['code']}, user=${query['user']}';
    } catch (error) {
      result = 'error: $error';
    }
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OAuth'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Opens a sign-in page in the system browser (Custom Tab / '
            'ASWebAuthenticationSession). iOS first asks to allow the app to '
            'sign in; fill the form with native_enter_text and submit.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _signIn,
            child: const Text('Sign in with browser'),
          ),
          Text('Sign-in result: $_result'),
        ],
      ),
    );
  }
}
