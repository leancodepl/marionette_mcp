import 'package:marionette_mcp/src/native_service/ios_native_connector.dart';
import 'package:marionette_mcp/src/native_service/native_connector.dart';
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

  group('parseHtmlDom', () {
    test('extracts interactive tags with id and text', () {
      const html = '''
<html><body>
  <button id="allow_btn">Allow</button>
  <a href="/x" id="nav_link">Go</a>
  <input id="email" type="text" placeholder="Email" />
  <textarea id="bio">Hello</textarea>
  <div>ignored layout</div>
</body></html>
''';

      final elements = parseHtmlDom(html);
      expect(elements.map((e) => e.resourceId), containsAll([
        'allow_btn',
        'nav_link',
        'email',
        'bio',
      ]));

      final button = elements.firstWhere((e) => e.resourceId == 'allow_btn');
      expect(button.className, 'button');
      expect(button.text, 'Allow');
      expect(button.clickable, isTrue);

      final input = elements.firstWhere((e) => e.resourceId == 'email');
      expect(input.text, 'Email');
      expect(input.clickable, isTrue);
    });

    test('keeps role=button and aria-label', () {
      const html = '''
<div role="button" id="custom" aria-label="Save changes"></div>
<span role="link" aria-label="Docs"></span>
''';
      final elements = parseHtmlDom(html);
      expect(elements, hasLength(2));
      expect(elements[0].resourceId, 'custom');
      expect(elements[0].text, 'Save changes');
      expect(elements[0].clickable, isTrue);
      expect(elements[1].text, 'Docs');
    });

    test('skips hidden inputs and script contents', () {
      const html = '''
<script>document.write('<button id="fake">X</button>');</script>
<input type="hidden" id="csrf" value="tok" />
<button id="real">OK</button>
''';
      final elements = parseHtmlDom(html);
      expect(elements.map((e) => e.resourceId), ['real']);
      expect(elements.single.text, 'OK');
    });

    test('toJson shape matches native lane', () {
      final elements = parseHtmlDom('<button id="b">Tap</button>');
      expect(elements.single.toJson(), {
        'type': 'button',
        'text': 'Tap',
        'id': 'b',
        'bounds': {'x': 0, 'y': 0, 'width': 0, 'height': 0},
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
