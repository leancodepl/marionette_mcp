// TextMate grammar vendored from package:syntax_highlight 0.5.0
// (https://github.com/serverpod/syntax_highlight), BSD-3-Clause, see
// LICENSE-syntax_highlight in this directory.
// Modified: keys may contain '-' and '.', may follow a list dash and must be
// followed by ':'; added booleans, numbers, CLI flags and ${{ }} expressions.
//
// dart format off

/// YAML grammar.
const kYamlGrammar = r'''
{
 "name": "YAML",
 "fileTypes": [
  "yaml",
  "yml"
 ],
 "scopeName": "source.yaml",
 "patterns": [
  {
   "name": "comment.line.number-sign.yaml",
   "match": "#.*",
   "captures": {
    "0": {
     "name": "punctuation.definition.comment.yaml"
    }
   }
  },
  {
   "name": "constant.language.yaml",
   "match": "\\b(?:true|false|on|off|yes|no|null)\\b"
  },
  {
   "name": "constant.numeric.yaml",
   "match": "(?<![\\w-])\\d+(?:\\.\\d+)?(?![\\w-])"
  },
  {
   "name": "variable.other.flag.yaml",
   "match": "(?<=\\s)--?[\\w-]+"
  },
  {
   "name": "meta.embedded.expression.yaml",
   "match": "\\$\\{\\{.*?\\}\\}"
  },
  {
   "name": "entity.name.tag.yaml",
   "match": "^\\s*(?:- )?[\\w.-]+(?=\\s*:(?:\\s|$))",
   "captures": {
    "0": {
     "name": "punctuation.definition.tag.yaml"
    }
   }
  },
  {
   "name": "punctuation.separator.key-value.yaml",
   "match": ":",
   "captures": {
    "0": {
     "name": "punctuation.separator.key-value.yaml"
    }
   }
  },
  {
   "name": "string.quoted.double.yaml",
   "begin": "\"",
   "end": "\"",
   "patterns": [
    {
     "name": "constant.character.escape.yaml",
     "match": "\\\\(x[0-9A-Fa-f]{2}|u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{6}|.)"
    }
   ]
  },
  {
   "name": "string.quoted.single.yaml",
   "begin": "'",
   "end": "'",
   "patterns": [
    {
     "name": "constant.character.escape.yaml",
     "match": "''"
    }
   ]
  }
 ],
 "repository": {
  "scalar-plain": {
   "patterns": [
    {
     "match": "\\b(\\w+)\\b",
     "name": "scalar.plain.yaml"
    }
   ]
  }
 }
}
''';
