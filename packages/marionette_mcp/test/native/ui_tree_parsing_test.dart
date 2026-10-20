import 'package:marionette_mcp/src/native_service/ios_native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
import 'package:marionette_mcp/src/native_service/adb_client.dart';
import 'package:marionette_mcp/src/native_service/webdriver_client.dart';
import 'package:test/test.dart';

const androidFixture = '''
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<hierarchy rotation="0">
  <node index="0" text="" resource-id="" class="android.widget.FrameLayout"
      package="com.example.app" content-desc="" checkable="false" checked="false"
      clickable="false" enabled="true" focusable="false" focused="false"
      scrollable="false" long-clickable="false" password="false"
      selected="false" bounds="[0,0][1080,2400]">
    <node index="0" text="" resource-id="" class="android.widget.LinearLayout"
        package="com.example.app" content-desc="" checkable="false" checked="false"
        clickable="false" enabled="true" focusable="false" focused="false"
        scrollable="false" long-clickable="false" password="false"
        selected="false" bounds="[0,100][1080,400]" />
    <node index="1" text="Allow" resource-id="com.android.permissioncontroller:id/permission_allow_button"
        class="android.widget.Button" package="com.android.permissioncontroller"
        content-desc="" checkable="false" checked="false" clickable="true"
        enabled="true" focusable="true" focused="false" scrollable="false"
        long-clickable="false" password="false" selected="false"
        bounds="[100,800][500,920]" />
    <node index="2" text="" resource-id="com.example.app:id/title"
        class="android.widget.TextView" package="com.example.app"
        content-desc="Welcome" checkable="false" checked="false" clickable="false"
        enabled="true" focusable="false" focused="false" scrollable="false"
        long-clickable="false" password="false" selected="false"
        bounds="[40,200][1040,280]" />
    <node index="3" text="" resource-id="" class="android.view.View"
        package="com.example.app" content-desc="" checkable="false" checked="false"
        clickable="true" enabled="true" focusable="true" focused="false"
        scrollable="false" long-clickable="false" password="false"
        selected="false" bounds="[0,1800][1080,2000]" />
    <node index="4" text="Bad" resource-id="bad:id/bounds"
        class="android.widget.TextView" package="com.example.app"
        content-desc="" checkable="false" checked="false" clickable="false"
        enabled="true" focusable="false" focused="false" scrollable="false"
        long-clickable="false" password="false" selected="false"
        bounds="not-a-rect" />
  </node>
</hierarchy>
''';

const wdaFixture = '''
<?xml version="1.0" encoding="UTF-8"?>
<XCUIElementTypeApplication type="XCUIElementTypeApplication" name="SpringBoard"
    label="SpringBoard" enabled="true" visible="true" x="0" y="0" width="390" height="844">
  <XCUIElementTypeWindow type="XCUIElementTypeWindow" enabled="true" visible="true"
      x="0" y="0" width="390" height="844">
    <XCUIElementTypeOther type="XCUIElementTypeOther" enabled="true" visible="true"
        x="0" y="0" width="390" height="844" />
    <XCUIElementTypeButton type="XCUIElementTypeButton" name="Allow"
        label="Allow" enabled="true" visible="true" x="48" y="520" width="294" height="48" />
    <XCUIElementTypeStaticText type="XCUIElementTypeStaticText" name="titleLabel"
        label="Welcome" enabled="true" visible="true" x="20" y="100" width="350" height="24" />
    <XCUIElementTypeTextField type="XCUIElementTypeTextField" name="emailField"
        label="" value="user@example.com" enabled="true" visible="true"
        x="20" y="200" width="350" height="44" />
    <XCUIElementTypeButton type="XCUIElementTypeButton" name="disabledBtn"
        label="Disabled" enabled="false" visible="true" x="20" y="300" width="100" height="40" />
  </XCUIElementTypeWindow>
</XCUIElementTypeApplication>
''';

void main() {
  _unitTests();

  group('parseAndroidUiDump', () {
    test('parses interactive and labelled nodes with expected fields', () {
      final elements = parseAndroidUiDump(androidFixture);

      expect(elements, hasLength(4));

      final allow = elements.firstWhere((e) => e.text == 'Allow');
      expect(allow.resourceId,
          'com.android.permissioncontroller:id/permission_allow_button');
      expect(allow.className, 'android.widget.Button');
      expect(allow.clickable, isTrue);
      expect(allow.bounds.toJson(), {
        'x': 100,
        'y': 800,
        'width': 400,
        'height': 120,
      });

      final title = elements
          .firstWhere((e) => e.resourceId == 'com.example.app:id/title');
      expect(title.text, 'Welcome'); // content-desc fallback
      expect(title.clickable, isFalse);

      final clickableEmpty = elements.firstWhere(
        (e) => e.className == 'android.view.View' && e.clickable,
      );
      expect(clickableEmpty.text, isNull);
      expect(clickableEmpty.resourceId, isNull);
    });

    test('keeps the toast UIAutomator2 adds without bounds (D19)', () {
      final elements = parseAndroidUiDump(
        '<hierarchy>'
        '<node class="android.widget.Button" clickable="true" text="Save" '
        'bounds="[0,0][100,50]"/>'
        '<android.widget.Toast index="1" package="com.android.settings" '
        'class="android.widget.Toast" text="Saved" displayed="true" />'
        '</hierarchy>',
      );

      final toast = elements.last;
      expect(toast.text, 'Saved');
      expect(toast.isToast, isTrue);
      expect(toast.isVisible, isFalse);
      expect(toast.isListed, isTrue);
      expect(elements.first.isToast, isFalse);
    });

    test('decodes entities and numeric character references in one pass', () {
      final elements = parseAndroidUiDump(
        '<hierarchy>'
        '<node class="android.widget.Button" clickable="true" '
        'text="Home&#10;Tab 1 of 4" bounds="[0,0][1,1]"/>'
        '<node class="android.widget.Button" clickable="true" '
        'text="Don&#x2019;t &amp; won&apos;t" bounds="[0,0][1,1]"/>'
        '<node class="android.widget.Button" clickable="true" '
        'text="&amp;#10; &nbsp; &#xZZ;" bounds="[0,0][1,1]"/>'
        '</hierarchy>',
      );

      expect(elements.map((e) => e.text), [
        'Home\nTab 1 of 4',
        'Don’t & won\'t',
        '&#10; &nbsp; &#xZZ;',
      ]);
    });

    test('a field is labelled by its hint, empty or filled', () {
      final elements = parseAndroidUiDump(
        '<hierarchy>'
        '<android.widget.EditText class="android.widget.EditText" text="" '
        'hint="Amount" clickable="true" bounds="[0,0][10,10]"/>'
        '<android.widget.EditText class="android.widget.EditText" '
        'text="42" hint="Amount" clickable="true" bounds="[0,0][10,10]"/>'
        '</hierarchy>',
      );

      expect(elements.map((e) => e.text), ['Amount', 'Amount']);
      expect(elements.map((e) => e.value), [null, '42']);
    });

    test('drops non-interactive empty container nodes', () {
      final elements = parseAndroidUiDump(androidFixture);
      expect(
        elements.any((e) => e.className == 'android.widget.FrameLayout'),
        isFalse,
      );
      expect(
        elements.any((e) => e.className == 'android.widget.LinearLayout'),
        isFalse,
      );
    });

    test('malformed bounds become a zero rect without throwing', () {
      final elements = parseAndroidUiDump(androidFixture);
      final bad = elements.firstWhere((e) => e.resourceId == 'bad:id/bounds');
      expect(bad.bounds.toJson(), {'x': 0, 'y': 0, 'width': 0, 'height': 0});
    });

    test('toJson mirrors Flutter-lane shape', () {
      final allow = parseAndroidUiDump(androidFixture)
          .firstWhere((e) => e.text == 'Allow');
      expect(allow.toJson(), {
        'type': 'android.widget.Button',
        'text': 'Allow',
        'id': 'com.android.permissioncontroller:id/permission_allow_button',
        'bounds': {'x': 100, 'y': 800, 'width': 400, 'height': 120},
        'clickable': true,
      });
    });
  });

  group('parseWdaSource', () {
    test('parses XCUI elements with expected fields', () {
      final elements = parseWdaSource(wdaFixture);

      final allow = elements.firstWhere((e) => e.text == 'Allow');
      expect(allow.className, 'XCUIElementTypeButton');
      expect(allow.resourceId, 'Allow');
      expect(allow.clickable, isTrue);
      expect(allow.bounds.toJson(), {
        'x': 48,
        'y': 520,
        'width': 294,
        'height': 48,
      });

      final title = elements.firstWhere((e) => e.resourceId == 'titleLabel');
      expect(title.text, 'Welcome');
      expect(title.clickable, isFalse);

      final field = elements.firstWhere((e) => e.resourceId == 'emailField');
      expect(field.text, 'user@example.com'); // value fallback
      expect(field.clickable, isTrue);
    });

    test('drops non-interactive empty nodes; keeps labelled/disabled-with-id',
        () {
      final elements = parseWdaSource(wdaFixture);
      expect(
        elements.any((e) => e.className == 'XCUIElementTypeOther'),
        isFalse,
      );
      expect(
        elements.any((e) => e.className == 'XCUIElementTypeWindow'),
        isFalse,
      );

      // Application has name+label → kept; disabled button has name+label → kept
      // but not clickable.
      final disabled =
          elements.firstWhere((e) => e.resourceId == 'disabledBtn');
      expect(disabled.clickable, isFalse);
      expect(disabled.text, 'Disabled');
    });

    test('missing coordinate attributes become zero without throwing', () {
      const xml = '''
<XCUIElementTypeButton type="XCUIElementTypeButton" name="ok" label="OK"
    enabled="true" />
''';
      final elements = parseWdaSource(xml);
      expect(elements, hasLength(1));
      expect(elements.single.bounds.toJson(), {
        'x': 0,
        'y': 0,
        'width': 0,
        'height': 0,
      });
    });

    test('toJson mirrors Flutter-lane shape', () {
      final allow =
          parseWdaSource(wdaFixture).firstWhere((e) => e.text == 'Allow');
      expect(allow.toJson(), {
        'type': 'XCUIElementTypeButton',
        'text': 'Allow',
        'id': 'Allow',
        'bounds': {'x': 48, 'y': 520, 'width': 294, 'height': 48},
        'clickable': true,
      });
    });
  });

  group('foregroundAppFromWdaSource', () {
    test('prefers bundleId attribute over display name', () {
      const xml = '''
<XCUIElementTypeApplication type="XCUIElementTypeApplication"
    bundleId="com.example.app" name="Example" label="Example" />
''';
      expect(foregroundAppFromWdaSource(xml), 'com.example.app');
    });

    test('accepts bundle-like name when bundleId is absent', () {
      const xml = '''
<XCUIElementTypeApplication type="XCUIElementTypeApplication"
    name="com.example.app" label="Example" />
''';
      expect(foregroundAppFromWdaSource(xml), 'com.example.app');
    });

    test('returns null for SpringBoard display name without bundle id', () {
      expect(foregroundAppFromWdaSource(wdaFixture), isNull);
    });
  });

  group('NativeElement.center', () {
    test('computes integer midpoint of bounds', () {
      const element = NativeElement(
        className: 'android.widget.Button',
        clickable: true,
        bounds: NativeBounds(x: 100, y: 200, width: 50, height: 40),
        text: 'Tap',
      );
      expect(element.center, (x: 125, y: 220));
    });

    test('truncates toward zero for odd dimensions', () {
      const element = NativeElement(
        className: 'XCUIElementTypeButton',
        clickable: true,
        bounds: NativeBounds(x: 10, y: 20, width: 5, height: 7),
      );
      expect(element.center, (x: 12, y: 23));
    });
  });
}

void _unitTests() {
  group('NativeBounds.scaled (D2)', () {
    test('multiplies and rounds every edge', () {
      const bounds = NativeBounds(x: 10, y: 20, width: 101, height: 33);

      expect(bounds.scaled(3).toJson(), {
        'x': 30,
        'y': 60,
        'width': 303,
        'height': 99,
      });
      expect(bounds.scaled(1.5).toJson(), {
        'x': 15,
        'y': 30,
        'width': 152,
        'height': 50,
      });
      expect(identical(bounds.scaled(1), bounds), isTrue);
    });
  });

  group('pngSize', () {
    test('reads width and height from the IHDR chunk', () {
      // 1x1 transparent PNG.
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQ'
          'DwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

      expect(pngSize(png), (width: 1, height: 1));
    });

    test('returns null for non-PNG data', () {
      expect(
          pngSize('aGVsbG8gd29ybGQgdGhpcyBpcyBub3QgYSBwbmcgZmlsZQ=='), isNull);
      expect(pngSize('short'), isNull);
      expect(pngSize('!!!!not base64 at all, definitely not!!!!'), isNull);
    });
  });

  group('parseWmSize', () {
    test('reads the physical size', () {
      expect(parseWmSize('Physical size: 1080x2160\n'),
          (width: 1080, height: 2160));
    });

    test('an override size wins', () {
      expect(
        parseWmSize('Physical size: 1440x3120\nOverride size: 1080x2340\n'),
        (width: 1080, height: 2340),
      );
    });

    test('returns null for unrelated output', () {
      expect(parseWmSize('error: closed'), isNull);
    });
  });

  group('element state (N-01)', () {
    test('Android: field content, focus, checked, selected, scrollable', () {
      final elements = parseAndroidUiDump('''
<hierarchy>
  <node class="android.widget.EditText" text="Zażółć" hint="Name"
      showing-hint="false" focused="true" clickable="true" enabled="true"
      bounds="[0,0][100,50]"/>
  <node class="android.widget.EditText" text="Search" hint="Search"
      showing-hint="true" clickable="true" bounds="[0,50][100,100]"/>
  <node class="android.widget.Switch" text="" content-desc="Wi-Fi"
      checkable="true" checked="true" clickable="true"
      bounds="[0,100][100,150]"/>
  <node class="android.widget.Button" text="Disabled" enabled="false"
      clickable="true" checkable="false" checked="false"
      bounds="[0,150][100,200]"/>
  <node class="android.widget.FrameLayout" content-desc="Home" selected="true"
      clickable="true" bounds="[0,200][100,250]"/>
  <node class="androidx.recyclerview.widget.RecyclerView" scrollable="true"
      clickable="false" bounds="[0,250][100,400]"/>
</hierarchy>''');

      expect(elements, hasLength(6));
      final [typed, hint, toggle, disabled, tab, list] = elements;
      expect((typed.value, typed.focused), ('Zażółć', true));
      expect((hint.value, hint.text), (null, 'Search'));
      expect(toggle.checked, isTrue);
      expect((disabled.enabled, disabled.checked), (false, null));
      expect(tab.selected, isTrue);
      expect(list.scrollable, isTrue);
      expect(list.toJson()['scrollable'], isTrue);
      expect(disabled.toJson(), containsPair('enabled', false));
      expect(tab.toJson().containsKey('enabled'), isFalse);
    });

    test('iOS: value only for inputs, switches checked, selected trait', () {
      final elements = parseWdaSource('''
<XCUIElementTypeApplication>
  <XCUIElementTypeTextField value="typed" label="Name" placeholderValue="Name"
      enabled="true" x="0" y="0" width="10" height="10"/>
  <XCUIElementTypeTextField value="Search" label="" placeholderValue="Search"
      name="search" enabled="true" x="0" y="10" width="10" height="10"/>
  <XCUIElementTypeSwitch value="0" label="Wi-Fi" enabled="true"
      x="0" y="20" width="10" height="10"/>
  <XCUIElementTypeButton value="1" label="Testing" traits="Selected, Button"
      enabled="true" x="0" y="30" width="10" height="10"/>
  <XCUIElementTypeButton label="Disabled action" enabled="false"
      x="0" y="40" width="10" height="10"/>
  <XCUIElementTypeScrollView enabled="true" x="0" y="50" width="10"
      height="10"/>
</XCUIElementTypeApplication>''');

      expect(elements, hasLength(6));
      final [typed, empty, toggle, tab, disabled, scroll] = elements;
      expect((typed.text, typed.value), ('Name', 'typed'));
      expect(empty.value, isNull);
      expect((toggle.checked, toggle.value), (false, null));
      expect((tab.selected, tab.value, tab.checked), (true, null, null));
      expect(disabled.enabled, isFalse);
      expect(scroll.scrollable, isTrue);
      expect(typed.focused, isNull, reason: 'WDA does not report focus');
    });

    test('scaled keeps the state', () {
      const element = NativeElement(
        className: 'XCUIElementTypeSwitch',
        clickable: true,
        bounds: NativeBounds(x: 1, y: 1, width: 1, height: 1),
        value: 'v',
        enabled: false,
        checked: true,
        selected: true,
        scrollable: true,
      );

      final json = element.scaled(3).toJson();

      expect(json, containsPair('value', 'v'));
      expect(json, containsPair('enabled', false));
      expect(json, containsPair('checked', true));
      expect(json, containsPair('selected', true));
      expect(json, containsPair('scrollable', true));
    });
  });

  test('WDA: elements outside the application (screen) are dropped', () {
    final elements = parseWdaSource('''
<XCUIElementTypeApplication name="Counter" label="Counter" x="0" y="0" width="440" height="956">
  <XCUIElementTypeStaticText label="On screen" x="16" y="900" width="100" height="40"/>
  <XCUIElementTypeStaticText label="Partly visible" x="16" y="940" width="100" height="40"/>
  <XCUIElementTypeStaticText label="Section 2" x="16" y="1617" width="106" height="30"/>
  <XCUIElementTypeStaticText label="Flutter off-screen" x="0" y="0" width="0" height="0"/>
</XCUIElementTypeApplication>''');

    expect(elements.map((e) => e.text),
        ['Counter', 'On screen', 'Partly visible']);
    // Partly visible: clipped to the screen, so the center is on it.
    expect(elements[2].bounds.toJson(),
        {'x': 16, 'y': 940, 'width': 100, 'height': 16});
  });

  test('WDA: identical duplicate elements are listed once', () {
    final elements = parseWdaSource('''
<XCUIElementTypeApplication name="Counter" label="Counter" x="0" y="0" width="440" height="956">
  <XCUIElementTypeButton name="cancel" label="Cancel" enabled="true" x="76" y="532" width="288" height="48"/>
  <XCUIElementTypeButton name="cancel" label="Cancel" enabled="true" x="76" y="532" width="288" height="48"/>
  <XCUIElementTypeButton name="cancel" label="Cancel" enabled="true" x="76" y="600" width="288" height="48"/>
</XCUIElementTypeApplication>''');

    expect(elements.where((e) => e.text == 'Cancel'), hasLength(2),
        reason: 'same label elsewhere on screen is a different element');
  });
}
