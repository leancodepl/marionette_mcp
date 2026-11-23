import 'package:material_ui/material_ui.dart';

/// A `material_ui` app that shows [child] on one scrollable page.
class FixtureMaterialApp extends StatelessWidget {
  const FixtureMaterialApp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}
