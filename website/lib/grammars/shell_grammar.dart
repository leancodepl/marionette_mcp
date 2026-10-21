/// A minimal TextMate grammar for the shell snippets on the page: a `$`
/// prompt, the command that follows it, flags, strings and comments.
library;

/// Shared between [kShellGrammar] and the console grammar, which shows the
/// same prompt lines above Marionette's own output.
const kShellPatterns = r'''
    {
      "name": "keyword.other.prompt.shell",
      "match": "^\\$(?=\\s)"
    },
    {
      "name": "entity.name.command.shell",
      "match": "(?<=^\\$\\s+)[\\w./-]+"
    },
    {
      "name": "entity.name.command.shell",
      "match": "(?<=^\\$\\s+[\\w./-]+\\s+)(?:run|pub|global|activate|add)\\b"
    },
    {
      "name": "comment.line.number-sign.shell",
      "match": "#.*"
    },
    {
      "name": "string.quoted.single.shell",
      "begin": "'",
      "end": "'"
    },
    {
      "name": "string.quoted.double.shell",
      "begin": "\"",
      "end": "\""
    },
    {
      "name": "variable.other.flag.shell",
      "match": "(?<=\\s)--?[\\w-]+"
    },
    {
      "name": "keyword.operator.pipe.shell",
      "match": "(?<=\\s)\\|(?=\\s)"
    }''';

const kShellGrammar =
    '''
{
  "name": "Shell",
  "scopeName": "source.shell",
  "patterns": [
$kShellPatterns
  ]
}''';
