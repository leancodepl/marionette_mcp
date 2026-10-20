/// A TextMate grammar for what Marionette prints and writes, so transcripts
/// get the same treatment as real languages: `steps.md` lines, `report.md`,
/// the closing verdict, session folder trees and shell prompts.
library;

import 'package:marionette_website/grammars/shell_grammar.dart';

/// Whole-line shapes come first so their pieces are not mistaken for shell
/// tokens; prompt lines fall through to the shared shell patterns.
const kConsoleGrammar =
    '''
{
  "name": "Marionette output",
  "scopeName": "source.marionette",
  "patterns": [
    {
      "name": "comment.timestamp.marionette",
      "match": "(?<=^- )\\\\[\\\\d{2}:\\\\d{2}:\\\\d{2}\\\\]"
    },
    {
      "name": "entity.name.function.tool.marionette",
      "match": "(?<=^- \\\\[\\\\d{2}:\\\\d{2}:\\\\d{2}\\\\] )\\\\w+"
    },
    {
      "name": "support.type.property-name.selector.marionette",
      "match": "\\\\b(?:key|text|identifier|type|uri|input_len|input|ancestor_keys|compaction)(?==)"
    },
    {
      "name": "keyword.operator.arrow.marionette",
      "match": "(?<= )->(?= )"
    },
    {
      "name": "invalid.hint.error.marionette",
      "match": "(?<=-> )error:.*\$"
    },
    {
      "name": "entity.name.command.headline.marionette",
      "match": "^(?:Marionette ·|[✅⚠️🐛]+ Marionette report)"
    },
    {
      "name": "markup.inserted.summary.marionette",
      "match": "\\\\bPASS\\\\b|^✓"
    },
    {
      "name": "markup.changed.ask.marionette",
      "match": "\\\\b(?:SUSPECT|FAIL|BLOCKED)\\\\b"
    },
    {
      "name": "invalid.hint.finding.marionette",
      "match": "^✗"
    },
    {
      "name": "storage.type.annotation.tag.marionette",
      "match": "\\\\[(?:bug|suspicion|blocker|ux)\\\\]"
    },
    {
      "name": "keyword.label.marionette",
      "match": "^\\\\s*(?:Tested|Checks|Repro|Evidence|Not covered):"
    },
    {
      "name": "comment.line.note.marionette",
      "match": "(?<=\\\\S\\\\s{2,})#.*\$"
    },
$kShellPatterns
  ]
}''';
