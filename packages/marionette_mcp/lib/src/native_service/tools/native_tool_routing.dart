/// Guidance shared by native tool descriptions.
const nativeRoutingPreferFlutter =
    'Prefer Marionette Flutter tools (get_interactive_elements, tap, '
    'enter_text, scroll_to) when the target is a Flutter widget. '
    'Use this native tool only when the target is absent from the Flutter '
    'widget tree OR a system dialog / permission UI covers the app. '
    'Never mix Flutter logical coordinates with native physical coordinates.';
