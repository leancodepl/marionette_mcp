/// The recorded demo data the landing page and the docs replay: one real
/// session on the repository's example app (`demo/loop.json`) and one
/// element listing of a screen (`demo/xray.json`). `tool/record_demo.sh`
/// records both; the site only reads them, at build time.
library;

import 'dart:convert';

/// One tool call of the recorded session.
class LoopBeat {
  const LoopBeat({
    required this.tool,
    required this.call,
    required this.result,
    required this.step,
    this.frame,
    this.observation,
  });

  factory LoopBeat.fromJson(Map<String, Object?> json) => .new(
    tool: json['tool']! as String,
    call: json['call']! as String,
    result: json['result']! as String,
    step: json['step']! as String,
    frame: json['frame'] as String?,
    observation: json['observation'] as String?,
  );

  /// The tool's name, e.g. `tap`.
  final String tool;

  /// The call as the agent's transcript shows it, e.g. `tap(key: "save")`.
  final String call;

  /// What the tool answered, in one line.
  final String result;

  /// The line the server appended to `steps.md` for this call.
  final String step;

  /// The screenshot taken after this call, in `web/images/loop/`, when the
  /// call changed the screen.
  final String? frame;

  /// What the agent concluded from a call that only reads, in its own words.
  final String? observation;
}

/// The recorded session behind the landing page's replay.
class LoopDemo {
  const LoopDemo({
    required this.deviceName,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.prompt,
    required this.beats,
    required this.report,
    required this.verdict,
  });

  factory LoopDemo.fromJson(Map<String, Object?> json) {
    final device = json['device']! as Map<String, Object?>;
    return .new(
      deviceName: device['name']! as String,
      logicalWidth: (device['logicalWidth']! as num).toDouble(),
      logicalHeight: (device['logicalHeight']! as num).toDouble(),
      prompt: json['prompt']! as String,
      beats: [
        for (final beat in json['beats']! as List<Object?>)
          LoopBeat.fromJson(beat! as Map<String, Object?>),
      ],
      report: (json['report']! as String).trimRight(),
      verdict: (json['verdict']! as String).trimRight(),
    );
  }

  final String deviceName;

  /// The recorded screen's size in logical pixels; the frames share its
  /// aspect ratio.
  final double logicalWidth;
  final double logicalHeight;

  /// What the user typed to start the run.
  final String prompt;
  final List<LoopBeat> beats;

  /// `report.md`, as the agent wrote it.
  final String report;

  /// The chat message the agent closed the run with.
  final String verdict;

  /// The first frame, shown before any call has run.
  String get firstFrame =>
      beats.firstWhere((beat) => beat.frame != null).frame!;
}

/// One element of a `get_interactive_elements` listing.
class XrayElement {
  const XrayElement({required this.raw, this.bounds});

  /// Reads the element from its [raw] line, which carries its bounds as
  /// JSON, e.g. `bounds: {"x":16,"y":96,"width":379,"height":24}`.
  factory XrayElement.fromRaw(String raw) {
    final match = RegExp(r'bounds: (\{[^}]*\})').firstMatch(raw);
    if (match == null) {
      return .new(raw: raw);
    }
    final bounds = jsonDecode(match[1]!) as Map<String, Object?>;
    double read(String key) => (bounds[key]! as num).toDouble();
    return .new(
      raw: raw,
      bounds: (read('x'), read('y'), read('width'), read('height')),
    );
  }

  /// The element's line, exactly as the agent received it.
  final String raw;

  /// `(x, y, width, height)` in logical pixels, when the line has them.
  final (double, double, double, double)? bounds;
}

/// One screen of the example app and its element listing, compacted and in
/// full.
class XrayDemo {
  const XrayDemo({
    required this.screenshot,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.compact,
    required this.none,
    required this.compactChars,
    required this.noneChars,
  });

  factory XrayDemo.fromJson(Map<String, Object?> json) {
    List<XrayElement> elements(String mode) => [
      for (final element
          in (json[mode]! as Map<String, Object?>)['elements']!
              as List<Object?>)
        XrayElement.fromRaw(
          (element! as Map<String, Object?>)['raw']! as String,
        ),
    ];
    return .new(
      screenshot: json['screenshot']! as String,
      logicalWidth: (json['logicalWidth']! as num).toDouble(),
      logicalHeight: (json['logicalHeight']! as num).toDouble(),
      compact: elements('compact'),
      none: elements('none'),
      compactChars: json['compactChars']! as int,
      noneChars: json['noneChars']! as int,
    );
  }

  /// The screenshot in `web/images/xray/`.
  final String screenshot;
  final double logicalWidth;
  final double logicalHeight;
  final List<XrayElement> compact;
  final List<XrayElement> none;

  /// The length of each listing as the agent received it.
  final int compactChars;
  final int noneChars;
}
