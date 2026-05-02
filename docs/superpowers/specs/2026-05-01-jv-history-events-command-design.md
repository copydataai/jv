# JV History / Events Inspection Command Design

## Product Goal

JV should make its generated `.jv/` memory easy to inspect without asking humans or agents to hand-parse JSONL.

The next product slice adds a small CLI inspection surface for recent JV activity:

```bash
jv history
jv events
```

The command should answer the common post-run questions:

- What did JV do recently?
- Did it succeed, fail, or stop before execution?
- Which main class and command did it choose?
- Why did it fail or block, when JV has that information?
- Is the local `.jv/` memory missing, empty, or partly corrupt?

This slice should work with the current runner-core records and remain compatible with richer Agent-Grade JV Events later.

## Command Decision

Primary command: `jv history`.

Alias: `jv events`.

Rationale:

- `history` is the human-facing noun. It matches the thing most users want: recent JV runs.
- `events` is accurate for agents and future richer event streams, but it is implementation-flavored as the primary user command.
- Both commands should call the same implementation path so tests prove they stay equivalent.
- Help text should list `history` first and note `events` as an alias.

Recommended help row:

```text
history [--limit N] [--failures] [--json]  Show recent JV run history
events [--limit N] [--failures] [--json]   Alias for history
```

## MVP Flags

Keep the first implementation intentionally small.

### `--limit N`

Include in MVP.

Default: `10`.

Rationale: run logs are append-only. A bounded default keeps output readable, and agents can request more without reading files directly.

Validation:

- `N` must be a positive integer.
- Invalid values exit non-zero with `Error: --limit must be a positive integer`.

### `--failures`

Include in MVP.

Rationale: the most useful support workflow is "show me recent failures." The current legacy log only records successful executions, but the flag should still be accepted now so the surface is stable before richer failed/blocked events land.

Behavior:

- Show only records normalized to `failure` or `blocked`.
- With current legacy success-only records, print the empty-state message for the filtered view.

### `--json`

Include in MVP.

Rationale: agents need a stable, non-prose surface. `--json` should return normalized records so agents do not need to understand every historical event schema.

Behavior:

- Print a JSON object with `schemaVersion`, `source`, `limit`, `failuresOnly`, `records`, and `warnings`.
- Do not print color or prose in JSON mode.
- Exit status should still be `0` for missing/empty/corrupt-line history unless the flags are invalid or `.jv/runs.jsonl` cannot be read for a permission reason.

## Input Sources

MVP reads:

```text
.jv/runs.jsonl
.jv/state.json
```

`runs.jsonl` is the historical source of truth for the list.

`state.json` is optional enrichment:

- latest successful main class
- latest run command from `lastPlan.run`
- planner-selected main source/reasons when present

The command must not create `.jv/`, write `.jv/state.json`, append events, compile, run, or mutate project files.

## Supported Record Shapes

### Current Simple Record

Current runner-core writes lines like:

```json
{"event":"executed","detail":"java -cp bin Main one two"}
```

Normalize as:

```json
{
  "status": "success",
  "eventType": "result",
  "summary": "Executed java -cp bin Main one two",
  "mainClass": "Main",
  "command": "java -cp bin Main one two",
  "reason": null
}
```

`mainClass` can be inferred best-effort from the command string:

- For `java -cp <classpath> <MainClass> ...`, use the token immediately after the classpath value.
- For `mvn -q exec:java -Dexec.mainClass=<MainClass> ...`, use the `-Dexec.mainClass` value.
- If inference fails, leave `mainClass` blank in text mode and `null` in JSON mode.

### Agent-Grade Event Record

Future records may look like:

```json
{
  "schemaVersion": 1,
  "eventId": "evt_01",
  "runId": "run_01",
  "sequence": 3,
  "timestamp": "2026-05-01T20:12:30Z",
  "command": {"argv": ["jv", "run"], "mode": "run"},
  "eventType": "result",
  "level": "error",
  "summary": "Compilation failed",
  "payload": {
    "status": "failure",
    "phase": "compile",
    "classification": "compile-failure",
    "step": {
      "kind": "build",
      "argv": ["javac", "-d", "bin", "-cp", "bin", "src/Main.java"],
      "exitCode": 1
    },
    "nextAction": "Fix compiler errors and run jv run again"
  }
}
```

Normalize from richer fields in this order:

- `status`: `payload.status`, else `success` for legacy `event=executed`, else `failure` when `level=error`, else `blocked` when classification or summary indicates a blocker, else `info`.
- `eventType`: `eventType`, else `event`, else `unknown`.
- `summary`: `summary`, else a generated legacy summary from `event` and `detail`.
- `mainClass`: `payload.mainClass.selected`, `payload.mainClass`, `payload.step.mainClass`, `payload.step.argv`, `command.argv`, legacy `detail`, then optional `state.json` fallback only for the latest record.
- `command`: `payload.step.argv` joined with spaces, `command.argv` joined with spaces, legacy `detail`, then optional `state.json.lastPlan.run` fallback only for the latest record.
- `reason`: `payload.classification`, `payload.nextAction`, `payload.reason`, first blocker-like planner field, then blank.
- `timestamp`: event timestamp when present, otherwise blank.
- `runId` and `eventId`: preserve when present.

Do not require `jq` for MVP. Bash string extraction can support known fields, but tests should cover mixed formats and corruption. If future implementation switches to a packaged binary or uses a bundled JSON parser, this command contract should remain the same.

## Text Output

Text output is optimized for scanning.

Format:

```text
JV history
Source: .jv/runs.jsonl

1. success  Main  java -cp bin Main one two
2. failure  Main  javac -d bin -cp bin <sources>
   Reason: compile-failure
3. blocked  -     jv run
   Reason: Multiple main classes found: App, Demo. Pass one explicitly: jv run <MainClass>
```

Rules:

- Newest records first.
- Use 1-based numbering after filtering and limiting.
- Columns are simple spaces, not terminal-width dependent tables.
- Status values are lowercase: `success`, `failure`, `blocked`, `info`, `unknown`.
- Main class prints `-` when unknown.
- Command prints `-` when unknown.
- Reason line is omitted when unavailable.
- Warnings about skipped corrupt lines print after records in text mode.

### Example: Current Legacy Success

Given `.jv/runs.jsonl`:

```json
{"event":"executed","detail":"java -cp bin Main one two"}
```

and `.jv/state.json`:

```json
{
  "schemaVersion": 1,
  "projectShape": "plain-java",
  "lastSuccessfulMainClass": "Main",
  "lastPlan": {
    "build": "javac -d bin -cp bin <sources>",
    "run": "java -cp bin Main one two"
  }
}
```

`jv history` prints:

```text
JV history
Source: .jv/runs.jsonl

1. success  Main  java -cp bin Main one two
```

### Example: Empty Failure Filter

With only legacy success records, `jv history --failures` prints:

```text
JV history
Source: .jv/runs.jsonl

No failed or blocked JV events found.
```

### Example: Mixed Future Events

Given:

```json
{"schemaVersion":1,"eventId":"evt_1","runId":"run_1","timestamp":"2026-05-01T20:00:00Z","command":{"argv":["jv","run"],"mode":"run"},"eventType":"result","level":"info","summary":"Build and run completed successfully","payload":{"status":"success","phase":"run","step":{"kind":"run","argv":["java","-cp","bin","Main"],"exitCode":0},"classification":"completed"}}
{"schemaVersion":1,"eventId":"evt_2","runId":"run_2","timestamp":"2026-05-01T20:05:00Z","command":{"argv":["jv","run"],"mode":"run"},"eventType":"result","level":"error","summary":"Compilation failed","payload":{"status":"failure","phase":"compile","step":{"kind":"build","argv":["javac","-d","bin","-cp","bin","src/Main.java"],"exitCode":1},"classification":"compile-failure","nextAction":"Fix compiler errors and run jv run again"}}
```

`jv history --limit 2` prints:

```text
JV history
Source: .jv/runs.jsonl

1. failure  -     javac -d bin -cp bin src/Main.java
   Reason: compile-failure
2. success  Main  java -cp bin Main
```

### Example: Corrupt JSONL Lines

Given:

```text
{"event":"executed","detail":"java -cp bin Main"}
not json
{"schemaVersion":1,"eventType":"result","level":"error","summary":"No main class","payload":{"status":"blocked","classification":"missing-main"}}
```

`jv history` prints:

```text
JV history
Source: .jv/runs.jsonl

1. blocked  -     -
   Reason: missing-main
2. success  Main  java -cp bin Main

Warning: skipped 1 corrupt .jv/runs.jsonl line
```

## JSON Output

`jv history --json` prints:

```json
{
  "schemaVersion": 1,
  "source": ".jv/runs.jsonl",
  "limit": 10,
  "failuresOnly": false,
  "records": [
    {
      "status": "success",
      "eventType": "result",
      "timestamp": null,
      "runId": null,
      "eventId": null,
      "mainClass": "Main",
      "command": "java -cp bin Main one two",
      "summary": "Executed java -cp bin Main one two",
      "reason": null
    }
  ],
  "warnings": []
}
```

For corrupt lines:

```json
{
  "schemaVersion": 1,
  "source": ".jv/runs.jsonl",
  "limit": 10,
  "failuresOnly": false,
  "records": [],
  "warnings": [
    {
      "type": "corrupt-line",
      "count": 1,
      "message": "Skipped 1 corrupt .jv/runs.jsonl line"
    }
  ]
}
```

## Missing And Empty State

### Missing `.jv/`

`jv history`:

```text
JV history
Source: .jv/runs.jsonl

No JV history found. Run `jv run` to create .jv/runs.jsonl.
```

Exit `0`.

### Missing `runs.jsonl`

If `.jv/` exists but `.jv/runs.jsonl` does not:

```text
JV history
Source: .jv/runs.jsonl

No JV history found. Run `jv run` to create .jv/runs.jsonl.
```

Exit `0`.

### Empty `runs.jsonl`

```text
JV history
Source: .jv/runs.jsonl

No JV history entries found in .jv/runs.jsonl.
```

Exit `0`.

### Unreadable `runs.jsonl`

```text
Error: Cannot read .jv/runs.jsonl
```

Exit non-zero.

## Robustness Requirements

- Missing `.jv/` is not an error.
- Missing `.jv/runs.jsonl` is not an error.
- Empty `.jv/runs.jsonl` is not an error.
- Corrupt JSONL lines are skipped, counted, and reported.
- A file with only corrupt lines exits `0` and reports no valid entries plus a warning.
- Mixed legacy and schema-versioned events are accepted in one file.
- Unknown event shapes are shown as `info` or `unknown` instead of crashing.
- Missing `state.json` does not prevent history rendering.
- Corrupt `state.json` is ignored for enrichment and should add a warning only if implementation can detect it cheaply.
- The command is read-only and side-effect free.

## Tests To Require In The Implementation Plan

- `jv history` renders a current legacy `executed` record.
- `jv events` renders the same output as `jv history`.
- `jv history --limit 1` shows only the newest normalized record.
- `jv history --failures` filters failures and blocked records.
- `jv history --json` emits parseable JSON with normalized records.
- Missing `.jv/`, missing log, and empty log print clear empty states and exit `0`.
- Corrupt JSONL lines are skipped with a warning.
- Mixed legacy and schema-versioned records render newest-first.
- Invalid flags and invalid `--limit` values fail with clear errors.
- `jv history` does not create `.jv/`, `bin/`, or any files.

## Non-Goals

- Building a full event query language.
- Adding timestamps to legacy records retroactively.
- Rewriting or migrating `.jv/runs.jsonl`.
- Introducing `diagnostics.jsonl` in this slice.
- Logging new failures or blocked runs in this slice unless the implementation naturally needs a tiny support helper. The command must inspect what exists first.
- Replacing `jv doctor`. `doctor` explains the current project plan; `history` explains prior recorded activity.

## Success Definition

This slice is successful when a human or agent can run:

```bash
jv history
jv history --json
jv history --failures
```

and understand recent JV activity from both current simple records and future richer event records, without reading `.jv/runs.jsonl` by hand and without the command mutating the project.
