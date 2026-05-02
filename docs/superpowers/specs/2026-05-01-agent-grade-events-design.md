# Agent-Grade JV Events Design

## Product Goal

Make every important JV action observable for agents through a stable local event stream at `.jv/runs.jsonl`.

JV already has a shared planner model, `jv doctor`, planner blockers, tool requirements, and `.jv/state.json` planner snapshots. This slice turns those decisions into append-only JSON Lines events so an agent can understand what happened without scraping shell output.

The product promise:

> `.jv/runs.jsonl` is the local, append-only action trail for what JV planned, blocked, executed, remembered, and observed about the local tool environment.

## Non-Goals

- No daemon.
- No database.
- No remote telemetry.
- No background process.
- No file locking beyond best-effort append.
- No full stdout/stderr capture.
- No public plugin API.
- No new implementation files for this slice unless shell-only implementation becomes unreasonably fragile.

## File Contract

`JV_RUNS` remains:

```text
.jv/runs.jsonl
```

Each new event is one JSON object on one line. JV appends events only; it never rewrites old lines. Consumers must treat invalid, truncated, or unknown lines as skippable records.

Existing simple records may already exist:

```json
{"event":"executed","detail":"java -cp bin Main"}
```

Those records remain valid legacy history. New consumers should parse them as `schemaVersion: 0` legacy execution summaries. New JV writes use `schemaVersion: 1`.

## Agent Reader Rules

Agents reading `.jv/runs.jsonl` should:

1. Read line by line.
2. Parse each line independently.
3. Skip blank lines.
4. Skip corrupt JSON lines.
5. Preserve unknown `schemaVersion` and `eventType` records as opaque facts when useful.
6. Treat the last complete event for a `runId` as more recent than earlier events from the same `runId`.
7. Treat `.jv/state.json` as the compact latest snapshot and `.jv/runs.jsonl` as the append-only explanation trail.

This makes the event stream robust if JV is interrupted during an append and leaves a partial final line.

## Event Envelope

All new events use this envelope:

```json
{
  "schemaVersion": 1,
  "eventType": "plan",
  "runId": "run_20260501T120000Z_12345",
  "sequence": 1,
  "timestamp": "2026-05-01T12:00:00Z",
  "cwd": "/Users/josesanchez/Developer/public/jv",
  "command": {
    "name": "run",
    "argv": ["jv", "run", "Main", "alpha"]
  },
  "summary": "Plan selected plain Java main Main",
  "payload": {}
}
```

Envelope fields:

- `schemaVersion`: integer. New events write `1`.
- `eventType`: one of `environment`, `plan`, `blockers`, `execution_start`, `execution_result`, `memory_write`.
- `runId`: stable id shared by all events from one JV process invocation.
- `sequence`: integer starting at `1` and incremented for each event in that invocation.
- `timestamp`: UTC ISO-8601 timestamp.
- `cwd`: working directory where JV was invoked.
- `command.name`: JV command, such as `run`, `explain`, `doctor`, `remember`, `forget`, or `compile`.
- `command.argv`: normalized command vector beginning with `jv`.
- `summary`: short human-readable summary.
- `payload`: event-specific object.

## Event Types

### `environment`

Records local tool versions and project environment summary. JV should write this for `run` and `doctor`; it may write it for `explain` if explain becomes explicitly observable.

```json
{
  "schemaVersion": 1,
  "eventType": "environment",
  "runId": "run_20260501T120000Z_12345",
  "sequence": 1,
  "timestamp": "2026-05-01T12:00:00Z",
  "cwd": "/tmp/app",
  "command": { "name": "doctor", "argv": ["jv", "doctor"] },
  "summary": "Detected plain-java project with java and javac available",
  "payload": {
    "projectShape": "plain-java",
    "sourceRoot": "src",
    "tools": [
      { "name": "java", "required": true, "available": true, "path": "/usr/bin/java", "version": "openjdk version \"21.0.2\"" },
      { "name": "javac", "required": true, "available": true, "path": "/usr/bin/javac", "version": "javac 21.0.2" },
      { "name": "mvn", "required": false, "available": false, "path": "", "version": "" }
    ]
  }
}
```

### `plan`

Records the shared planner decision before execution.

```json
{
  "schemaVersion": 1,
  "eventType": "plan",
  "runId": "run_20260501T120000Z_12345",
  "sequence": 2,
  "timestamp": "2026-05-01T12:00:01Z",
  "cwd": "/tmp/app",
  "command": { "name": "run", "argv": ["jv", "run", "Main", "alpha"] },
  "summary": "Plan selected Main from one detected main class",
  "payload": {
    "projectShape": "plain-java",
    "sourceRoot": "src",
    "mainClass": {
      "selected": "Main",
      "source": "only-candidate",
      "candidates": ["Main"]
    },
    "build": {
      "kind": "javac",
      "display": "javac -d bin -cp bin <sources>"
    },
    "run": {
      "kind": "java",
      "display": "java -cp bin Main alpha",
      "args": ["alpha"]
    },
    "reasons": ["src directory found", "src exists", "exactly one main class detected"],
    "warnings": []
  }
}
```

### `blockers`

Records planner blockers that prevent execution. A `run` command with blockers writes `environment`, `plan`, and `blockers`, then exits non-zero without writing `execution_start`.

```json
{
  "schemaVersion": 1,
  "eventType": "blockers",
  "runId": "run_20260501T120500Z_12346",
  "sequence": 3,
  "timestamp": "2026-05-01T12:05:00Z",
  "cwd": "/tmp/app",
  "command": { "name": "run", "argv": ["jv", "run"] },
  "summary": "Execution blocked by ambiguous main classes",
  "payload": {
    "blockers": ["Multiple main classes found: App, Tool. Pass one explicitly: jv run <MainClass>"],
    "classification": "ambiguous-main",
    "nextAction": "Run `jv run <MainClass>` or `jv remember main <MainClass>`."
  }
}
```

### `execution_start`

Records that JV is about to invoke a build or run step. This is useful when a later process interruption prevents an execution result.

```json
{
  "schemaVersion": 1,
  "eventType": "execution_start",
  "runId": "run_20260501T121000Z_12347",
  "sequence": 3,
  "timestamp": "2026-05-01T12:10:00Z",
  "cwd": "/tmp/app",
  "command": { "name": "run", "argv": ["jv", "run"] },
  "summary": "Starting build step",
  "payload": {
    "phase": "compile",
    "step": {
      "kind": "javac",
      "display": "javac -d bin -cp bin <sources>"
    }
  }
}
```

### `execution_result`

Records a completed JV step or command outcome. Output previews are bounded and optional; JV should not duplicate full compiler or program output into the event file.

```json
{
  "schemaVersion": 1,
  "eventType": "execution_result",
  "runId": "run_20260501T121000Z_12347",
  "sequence": 4,
  "timestamp": "2026-05-01T12:10:02Z",
  "cwd": "/tmp/app",
  "command": { "name": "run", "argv": ["jv", "run"] },
  "summary": "Run completed successfully",
  "payload": {
    "phase": "run",
    "status": "success",
    "exitCode": 0,
    "classification": "completed",
    "step": {
      "kind": "java",
      "display": "java -cp bin Main"
    }
  }
}
```

Failure example:

```json
{
  "schemaVersion": 1,
  "eventType": "execution_result",
  "runId": "run_20260501T121500Z_12348",
  "sequence": 4,
  "timestamp": "2026-05-01T12:15:04Z",
  "cwd": "/tmp/app",
  "command": { "name": "run", "argv": ["jv", "run"] },
  "summary": "Run failed with exit code 7",
  "payload": {
    "phase": "run",
    "status": "failure",
    "exitCode": 7,
    "classification": "runtime-failure",
    "step": {
      "kind": "java",
      "display": "java -cp bin Main"
    }
  }
}
```

### `memory_write`

Records generated memory decisions in `.jv/state.json` and `.jv/runs.jsonl`.

```json
{
  "schemaVersion": 1,
  "eventType": "memory_write",
  "runId": "run_20260501T121000Z_12347",
  "sequence": 5,
  "timestamp": "2026-05-01T12:10:02Z",
  "cwd": "/tmp/app",
  "command": { "name": "run", "argv": ["jv", "run"] },
  "summary": "Updated JV state after successful run",
  "payload": {
    "target": ".jv/state.json",
    "status": "success",
    "rememberedMainClass": "",
    "lastSuccessfulMainClass": "Main",
    "lastPlan": {
      "build": "javac -d bin -cp bin <sources>",
      "run": "java -cp bin Main"
    }
  }
}
```

Memory write failure example:

```json
{
  "schemaVersion": 1,
  "eventType": "memory_write",
  "runId": "run_20260501T122000Z_12349",
  "sequence": 5,
  "timestamp": "2026-05-01T12:20:00Z",
  "cwd": "/tmp/app",
  "command": { "name": "run", "argv": ["jv", "run"] },
  "summary": "Could not update JV state",
  "payload": {
    "target": ".jv/state.json",
    "status": "failure",
    "classification": "memory-unavailable"
  }
}
```

## Command Behavior

`jv run`:

- Writes `environment`.
- Writes `plan`.
- Writes `blockers` and exits if the planner is blocked.
- Writes `execution_start` before build.
- Writes `execution_result` for build failure or success.
- Writes `execution_start` before run.
- Writes `execution_result` for run failure or success.
- Writes `memory_write` after successful state write, or failure when state write fails.

`jv doctor`:

- Writes `environment`.
- Writes `plan`.
- Writes `blockers` if blockers exist.
- Does not write execution events.
- Does not update `.jv/state.json`.

`jv explain`:

- Current contract is side-effect free. This slice should keep `explain` side-effect free unless the implementation explicitly changes help/docs/tests to say that explain writes diagnostic events.
- Recommended first implementation: no `explain` events.

`jv remember main` and `jv forget main`:

- May write `memory_write` events when they update `.jv/state.json`.
- Do not write plan or execution events.

## Backward Compatibility

Existing `.jv/runs.jsonl` lines are append-only history. JV does not migrate them in place.

Legacy line:

```json
{"event":"executed","detail":"java -cp bin Main"}
```

Agent interpretation:

```json
{
  "schemaVersion": 0,
  "eventType": "execution_result",
  "summary": "java -cp bin Main",
  "payload": {
    "status": "success",
    "phase": "run",
    "legacy": true
  }
}
```

New tests should assert that appending v1 events after legacy lines preserves both records and that simple tools can still find the old `"event":"executed"` string only in pre-existing data.

## Implementation Constraints

- Prefer modifying only `jv.sh` and `tests/run-tests.sh`.
- Keep event construction in Bash using existing `json_escape` and `json_array_from_lines` helpers.
- Keep event payloads compact and deterministic enough for shell tests.
- Do not introduce `jq` as a runtime dependency.
- Do not make event write failure fail a successful Java run; warn like current memory write failures.
- Do not treat `.jv/runs.jsonl` as authoritative input for planning.

