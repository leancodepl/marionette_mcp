---
name: next-task
description: Pick up and implement the next video recording task using red-green-refactor TDD with vertical slicing. Use when user says "next task", "pick up next task", "continue video recording work", or "implement next slice".
argument-hint: [task-number]
---

# Next Task

Implement the next video recording task (or a specific task by number) using strict red/green/refactor TDD with vertical slicing.

## Important

- Follow the `/tdd` skill's philosophy: vertical slices (one failing test, minimal code to pass, next test), never horizontal slices
- Use the Task tool to track every slice as you go — create tasks before starting, update status as you work
- Read the TDD guide and task spec before writing any code

## Workflow

### Step 1: Determine which task to work on

If the user passed a task number as `$ARGUMENTS`, use that task.

Otherwise, read `tasks/video-recording/00-overview.md` and find the first task with status `⬜ Not Started` whose dependencies are all complete (status `✅ Done`). Use the dependency graph in the overview to determine this.

The recommended implementation order respecting dependencies is: 3 → 1 → 4 → 5 → 2 → 6 → 7 → 8 → 9.

### Step 2: Load context

Read these files to understand what to build and how:

1. **Task spec**: `tasks/video-recording/{NN}-{task-name}.md` — the detailed requirements for this task
2. **TDD guide**: `tasks/video-recording/TDD-GUIDE.md` — find the section for this task number, which lists every test slice with its RED assertion and GREEN implementation
3. **Playwright reference** (if needed): `playwright-screen-recording-internals.md` — the architecture being ported

### Step 3: Create tasks for tracking

Use the Task tool to create a task for every test slice listed in the TDD guide for this task. Each task title should be the slice ID and a short description, e.g.:

```
Slice 3.1 — Default size when no args provided
Slice 3.2 — Large viewport scales down
...
Slice 3.REFACTOR — Clean code review
```

Also create a final task for the refactor step.

### Step 4: Execute each slice

For each slice, in order:

1. **Update task status** to `in_progress`
2. **RED**: Write exactly one failing test. Run it. Confirm it fails.
3. **GREEN**: Write the minimal production code to make that test pass. Run it. Confirm it passes.
4. **Update task status** to `completed`
5. Move to the next slice.

Rules (from the TDD guide):
- Never write production code without a failing test first
- Never write more than one failing test at a time
- The GREEN step should be the simplest code that passes
- Run the test command after every RED and GREEN step

Test commands by package:
- `marionette_flutter`: `flutter test test/{test_file}.dart` (run from `packages/marionette_flutter`)
- `marionette_mcp`: `dart test test/video/` (run from `packages/marionette_mcp`)
- `marionette_cli`: `dart test test/` (run from `packages/marionette_cli`)

### Step 5: Refactor

After all slices pass:

1. **Update refactor task** to `in_progress`
2. Review production code for duplication, naming, and clarity
3. Run all tests to confirm nothing broke
4. **Update refactor task** to `completed`

### Step 6: Update the overview

Edit `tasks/video-recording/00-overview.md` — change the completed task's status from `⬜ Not Started` to `✅ Done`.
