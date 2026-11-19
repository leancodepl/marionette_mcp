import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _marionetteMcpUrl = 'https://github.com/leancodepl/marionette_mcp';
const _formAsset = 'assets/webview_form.html';

/// webview_flutter implements only Android, iOS and macOS; the screen says so
/// on other platforms instead of failing.
bool get isWebViewSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Page shown in the WebView.
enum _Page { form, website }

/// WebView. The default page is a local form (no network needed) with
/// fields, a checkbox, a select, a button and a link, so the native lane's
/// view of web content can be checked; the marionette_mcp website is the
/// alternative.
class WebViewScreen extends StatelessWidget {
  const WebViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebView'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: isWebViewSupported
          ? const _WebViewBody()
          : const Center(
              child: Text('WebView is available on Android, iOS and macOS.'),
            ),
    );
  }
}

class _WebViewBody extends StatefulWidget {
  const _WebViewBody();

  @override
  State<_WebViewBody> createState() => _WebViewBodyState();
}

class _WebViewBodyState extends State<_WebViewBody> {
  late final WebViewController _controller;
  var _isLoading = true;
  var _page = _Page.form;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => _setLoading(true),
          onPageFinished: (_) => _setLoading(false),
          onWebResourceError: (_) => _setLoading(false),
        ),
      );
    _load();
  }

  void _load() {
    switch (_page) {
      case _Page.form:
        _controller.loadFlutterAsset(_formAsset);
      case _Page.website:
        _controller.loadRequest(Uri.parse(_marionetteMcpUrl));
    }
  }

  void _setLoading(bool loading) {
    // The delegate can still report a page after the screen was left.
    if (!mounted || _isLoading == loading) return;
    setState(() => _isLoading = loading);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<_Page>(
            segments: const [
              ButtonSegment(value: _Page.form, label: Text('Local form')),
              ButtonSegment(value: _Page.website, label: Text('Website')),
            ],
            selected: {_page},
            onSelectionChanged: (selection) {
              setState(() => _page = selection.single);
              _load();
            },
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_isLoading) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ],
    );
  }
}
