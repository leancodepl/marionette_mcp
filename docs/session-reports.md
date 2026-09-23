# Session Reports

Every `connect` opens (or resumes) a **session directory** — a persistent
workspace for the run, separate from the agent's own conversation context.
The server owns the directory, the step log, and the screenshot sink; the
connected agent owns the narrative report written into it.

## Session directory

```
.marionette/                       <- gitignored
  sessions/
    profile-validation-20260922T1412/
      report.md          written once at the end, by the agent
      steps.md            machine-appended, one line per tool call
      screenshots/
        01.png
```

`.marionette/` is added to this repo's `.gitignore` — add the same entry to
your own project's. Committing a session directory (e.g. attaching a report
to a PR) is a deliberate opt-in, not the default.

### Where it's created

The directory's location is resolved from, in order:

1. The `connect` tool's `session_dir` argument (or the CLI's `--session-dir`).
2. The `MARIONETTE_SESSION_DIR` environment variable — an MCP client sets
   this to the project root when it launches the server, since the server
   process's own working directory isn't reliably the repo root.
3. The process's current working directory, as a last resort.

`.marionette/sessions/<name>/` is created under whichever of these applies.

### Naming and resuming a session

`connect` accepts an optional `session_title` (the CLI: `--session <title>`).
The title is slugified and a creation timestamp appended, e.g.
`profile-validation-20260922T1412`. Passing the **same title again** resumes
the most recently used session with that title instead of creating a new
one — `steps.md` keeps growing in the same file rather than starting over.
Omitting the title falls back to `run-<timestamp>`, which is never resumed.

Old session directories are pruned automatically, keeping the most recently
used 20 per project.

## steps.md

The server appends one line per tool call — no agent involvement, so it
can't be skipped or embellished:

```
- [14:12:03] connect uri=ws://127.0.0.1:8181 -> Successfully connected to app at ws://127.0.0.1:8181
- [14:12:07] tap key=dob_field -> Successfully tapped
- [14:12:09] enter_text key=dob_field input_len=10 -> Successfully entered text
- [14:12:11] tap key=save_button -> Successfully tapped
- [14:12:12] get_interactive_elements -> ok
- [14:12:14] tap key=missing_button -> error: Exception: Element matching {key: missing_button} not found [GestureDispatcher.tap (marionette_flutter/src/services/gesture_dispatcher.dart:36) › ...]
```

Each line has the tool name, a short selector summary (key/identifier/text/
coordinates — never the full argument payload — and any `ws://`/`http://` URI
redacted to `scheme://host:port`, since a Flutter VM service URI embeds a
live debug-access token in its path), and the outcome. On success, only a
fixed set of tools whose message is a short, hand-written confirmation
("Successfully tapped") get it echoed verbatim (truncated to ~200
characters); a tool that returns application data
(`get_interactive_elements`, `get_logs`, a custom extension) gets a generic
`ok` instead, so a payload never ends up on disk. On failure, an app-side
crash is detected and unpacked into the exception message plus up to 4
compact stack frames (truncated to ~500 characters) rather than the raw,
JSON-wrapped error text; anything else (a deliberate, expected error) keeps
the plain, truncated (~200 character) message. This is also what a report's
**Tested** line should be rendered from, not the agent's own claim of what
it did — steps.md is the anti-overstatement mechanism.

`enter_text`'s entered value is never written in full: by default only its
length is recorded (`input_len=10`); when the target field's key or
identifier looks sensitive (matches `pass|pin|token|secret|cvv`,
case-insensitive) even the length is withheld (`input=[redacted]`).

## Screenshots

`take_screenshots` returns base64 PNGs inline by default. Pass
`inline: false` to instead save them into the session's `screenshots/`
directory (numbered sequentially, `01.png`, `02.png`, …) and get back their
paths — useful when a screenshot is evidence you plan to cite in a report but
don't need to look at right now, since each inline image costs real visual
tokens.

## report.md

This is **not** written by the server — the connected agent writes it
directly with its own file tools, using the session directory path returned
by `connect`/`disconnect`. `disconnect`'s response includes that path and a
reminder to write `report.md`, since a tool result is a much more reliable
enforcement mechanism than an instruction the agent might skip.

The report *format* — what counts as a finding, how it cites evidence, the
"Tested" line, and so on — lives in the Marionette drive skill, not here: see
["Reporting what you found"](https://github.com/leancodepl/marionette_mcp/blob/main/packages/marionette_flutter/skills/marionette-flutter-drive-app/SKILL.md#reporting-what-you-found)
in `marionette-flutter-drive-app`.

## CLI parity

`marionette` commands open (or resume) the same kind of session directory
and append the same style of `steps.md` line per invocation — pass
`--session <title>` consistently across a script's invocations to log a
multi-step run into one session rather than a fresh, untitled one per
command. See the [CLI reference](./cli.md#command-reference).
