import 'package:flutter/material.dart';

class PageViewScreen extends StatefulWidget {
  const PageViewScreen({super.key});

  @override
  State<PageViewScreen> createState() => _PageViewScreenState();
}

class _PageViewScreenState extends State<PageViewScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _pageCount = 5;
  static const _pages = [
    (color: Colors.red, icon: Icons.looks_one, label: 'Page 1 of 5'),
    (color: Colors.blue, icon: Icons.looks_two, label: 'Page 2 of 5'),
    (color: Colors.green, icon: Icons.looks_3, label: 'Page 3 of 5'),
    (color: Colors.orange, icon: Icons.looks_4, label: 'Page 4 of 5'),
    (color: Colors.purple, icon: Icons.looks_5, label: 'Page 5 of 5'),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Page View'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              key: const ValueKey('page_view'),
              controller: _controller,
              itemCount: _pageCount,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, index) {
                final page = _pages[index];
                return Container(
                  key: ValueKey('page_$index'),
                  color: page.color.withValues(alpha: 0.15),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(page.icon, size: 80, color: page.color),
                        const SizedBox(height: 24),
                        Text(
                          page.label,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Swipe left or right to navigate',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pageCount, (index) {
                return Container(
                  key: ValueKey('indicator_$index'),
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == _currentPage
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
