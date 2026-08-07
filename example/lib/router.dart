import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/about_screen.dart';
import 'screens/dismissible_screen.dart';
import 'screens/home_screen.dart';
import 'screens/items_screen.dart';
import 'screens/mouse_tap_screen.dart';
import 'screens/page_view_screen.dart';
import 'screens/pinch_zoom_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/testing/camera_platform_view_screen.dart';
import 'screens/testing/google_maps_platform_view_screen.dart';
import 'screens/testing/native_controls_platform_view_screen.dart';
import 'screens/testing/permission_dialogs_screen.dart';
import 'screens/testing/pickers_and_sheets_screen.dart';
import 'screens/testing/platform_views_screen.dart';
import 'screens/testing/testing_screen.dart';
import 'screens/testing/video_player_platform_view_screen.dart';
import 'screens/webview_screen.dart';

/// Page name → route path mapping used by the custom VM service extension.
const availablePages = <String, String>{
  'home': '/',
  'profile': '/profile',
  'testing': '/testing',
  'webview': '/testing/webview',
  'platform_views': '/testing/platform-views',
  'native_controls_platform_view': '/testing/platform-views/native-controls',
  'camera_platform_view': '/testing/platform-views/camera',
  'google_maps_platform_view': '/testing/platform-views/google-maps',
  'video_player_platform_view': '/testing/platform-views/video-player',
  'permission_dialogs': '/testing/permission-dialogs',
  'pickers_and_sheets': '/testing/pickers-and-sheets',
  'settings': '/settings',
  'items': '/settings/items',
  'about': '/settings/about',
  'page_view': '/settings/page-view',
  'dismissible': '/settings/dismissible',
  'pinch_zoom': '/settings/pinch-zoom',
  'mouse_tap': '/settings/mouse-tap',
};

final router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => ScaffoldWithNav(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/testing',
          builder: (context, state) => const TestingScreen(),
          routes: [
            GoRoute(
              path: 'webview',
              builder: (context, state) => const WebViewScreen(),
            ),
            GoRoute(
              path: 'platform-views',
              builder: (context, state) => const PlatformViewsScreen(),
              routes: [
                GoRoute(
                  path: 'native-controls',
                  builder: (context, state) =>
                      const NativeControlsPlatformViewScreen(),
                ),
                GoRoute(
                  path: 'camera',
                  builder: (context, state) =>
                      const CameraPlatformViewScreen(),
                ),
                GoRoute(
                  path: 'google-maps',
                  builder: (context, state) =>
                      const GoogleMapsPlatformViewScreen(),
                ),
                GoRoute(
                  path: 'video-player',
                  builder: (context, state) =>
                      const VideoPlayerPlatformViewScreen(),
                ),
              ],
            ),
            GoRoute(
              path: 'permission-dialogs',
              builder: (context, state) => const PermissionDialogsScreen(),
            ),
            GoRoute(
              path: 'pickers-and-sheets',
              builder: (context, state) => const PickersAndSheetsScreen(),
            ),
          ],
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
          routes: [
            GoRoute(
              path: 'items',
              builder: (context, state) => const ItemsScreen(),
            ),
            GoRoute(
              path: 'page-view',
              builder: (context, state) => const PageViewScreen(),
            ),
            GoRoute(
              path: 'dismissible',
              builder: (context, state) => const DismissibleScreen(),
            ),
            GoRoute(
              path: 'pinch-zoom',
              builder: (context, state) => const PinchZoomScreen(),
            ),
            GoRoute(
              path: 'mouse-tap',
              builder: (context, state) => const MouseTapScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/settings/about',
      pageBuilder: (context, state) =>
          const MaterialPage(fullscreenDialog: true, child: AboutScreen()),
    ),
  ],
);

class ScaffoldWithNav extends StatelessWidget {
  const ScaffoldWithNav({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(context),
        onDestinationSelected: (index) => _onTap(context, index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: 'Testing',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/settings')) return 3;
    if (location.startsWith('/testing')) return 2;
    if (location.startsWith('/profile')) return 1;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/');
      case 1:
        context.go('/profile');
      case 2:
        context.go('/testing');
      case 3:
        context.go('/settings');
    }
  }
}
