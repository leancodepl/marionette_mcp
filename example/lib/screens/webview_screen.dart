import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _marionetteMcpUrl = 'https://github.com/leancodepl/marionette_mcp';
const _formAsset = 'assets/webview_form.html';

/// Page shown in the WebView.
enum _Page { form, website }

/// §2 WebView. The default page is a local form (no network needed) with
/// fields, a checkbox, a select, a button and a link, so the native lane's
/// view of web content can be checked; the marionette_mcp website is the
/// alternative.
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
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
    if (_isLoading == loading) return;
    setState(() => _isLoading = loading);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebView'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
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
                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
