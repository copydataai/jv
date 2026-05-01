# JV Milestone 2: Agent-Grade `.jv` Events Design

## Product Goal

JV turns hidden IDE and project state into one reliable action: build and run the latest Java code correctly.

Milestone 1 made `jv run` write generated memory after successful runs:

```text
.jv/
  state.json
  runs.jsonl
```

Milestone 2 makes `.jv/` useful as a structured feedback loop for agents and humans. After every meaningful compile, run, diagnosis, or memory decision, JV should leave behind enough local structured evidence for the next actor to understand:

- what JV observed
- what JV planned
- what JV executed
- what succeeded or failed
- what user/project memory was used
- what memory was rejected as stale
- what the next useful action is

`jv explain` is special: the current runner-core contract keeps it side-effect free. This milestone may introduce explicit diagnostic event logging for `explain`, but only if the command output and docs make that behavior clear and the events are never treated as successful execution memory.

The product promise:

> `.jv/` is a local, append-only explanation trail that lets a human or agent resume from the last known project state without guessing.

## Non-Goals

- Replacing compiler, Maven, or runtime output with JV-specific abstractions.
- Making `.jv/` authoritative project configuration.
- Requiring users to edit `.jv/` files by hand.
- Sending event data to a remote service.
- Building a telemetry or analytics system.
- Storing full source file contents in event logs.
- Supporting every Java build system in this milestone.
- Designing a long-term public plugin API.

## Proposed `.jv` Directory Structure

```text
.jv/
  state.json
  runs.jsonl
  diagnostics.jsonl
```

### `state.json`

`state.json` is the latest compact snapshot of JV memory.

It is optimized for fast resume:

- latest detected project shape
- latest known source/build fingerprint
- latest successful main class
- remembered explicit user choices
- latest plan summary
- latest result summary
- pointers into append-only event logs

It is non-authoritative. If source files, build files, or local tools change, JV should detect stale state and regenerate or supersede it.

### `runs.jsonl`

`runs.jsonl` is the append-only event stream for normal user-facing JV actions:

- `jv explain`
- `jv compile`
- `jv run`
- successful plans
- failed plans
- command results
- memory decisions needed to understand a run

Agents should usually read `state.json` first, then inspect recent `runs.jsonl` events if they need detail.

### `diagnostics.jsonl`

`diagnostics.jsonl` is optional append-only detail for verbose diagnostics that may be too noisy for the main run stream:

- tool discovery detail
- source scan detail
- rejected candidates
- classpath construction notes
- long diagnostic chains

The first implementation may write all events to `runs.jsonl` and add `diagnostics.jsonl` later. The schema should allow either file to contain the same event envelope.

## Event Model

Every JSONL line is one complete JSON object. Events are append-only and should remain valid even if later events supersede them.

Events use a common envelope plus type-specific payload.

```json
{
  "schemaVersion": 1,
  "eventId": "evt_01HV7ZJ9Q2YV1E9M8GJ3R6N4SA",
  "runId": "run_01HV7ZJ91BHDYWNSW82J2RC6E4",
  "sequence": 4,
  "timestamp": "2026-04-30T12:00:00Z",
  "cwd": "/Users/alex/project",
  "command": {
    "argv": ["jv", "run"],
    "mode": "run"
  },
  "eventType": "result",
  "level": "info",
  "summary": "Build and run completed successfully",
  "payload": {}
}
```

Envelope fields:

- `schemaVersion`: integer schema version for the event line.
- `eventId`: unique event identifier.
- `runId`: stable identifier shared by events from one JV command invocation.
- `sequence`: monotonic integer within the `runId`, starting at 1.
- `timestamp`: ISO-8601 UTC timestamp.
- `cwd`: project root or command working directory JV used.
- `command.argv`: original JV command arguments.
- `command.mode`: one of `explain`, `compile`, `run`, `doctor`, `remember`, `forget`.
- `eventType`: one of `plan`, `result`, `diagnostic`, `memory`, `stale-state`.
- `level`: one of `debug`, `info`, `warn`, `error`.
- `summary`: short human-readable description.
- `payload`: type-specific structured data.

## Event Types

### `plan`

A `plan` event records what JV intends to do before execution.

Payload schema:

```json
{
  "project": {
    "shape": "maven",
    "sourceRoots": ["src/main/java"],
    "buildFiles": ["pom.xml"],
    "libraries": []
  },
  "mainClass": {
    "selected": "com.example.App",
    "source": "detected-single",
    "candidates": ["com.example.App"]
  },
  "steps": [
    {
      "kind": "build",
      "argv": ["mvn", "compile"],
      "cwd": "/Users/alex/project"
    },
    {
      "kind": "run",
      "argv": ["mvn", "exec:java", "-Dexec.mainClass=com.example.App"],
      "cwd": "/Users/alex/project"
    }
  ],
  "fingerprint": {
    "sourceHash": "sha256:...",
    "buildHash": "sha256:...",
    "toolchain": {
      "java": "21.0.2",
      "javac": "21.0.2",
      "mvn": "3.9.6"
    }
  }
}
```

`mainClass.source` values:

- `argument`
- `remembered`
- `detected-single`
- `maven-config`
- `none`

### `result`

A `result` event records the outcome of one command step or the whole JV invocation.

Payload schema:

```json
{
  "status": "success",
  "phase": "run",
  "step": {
    "kind": "run",
    "argv": ["java", "-cp", "bin:lib/*", "Main"],
    "exitCode": 0,
    "durationMs": 214
  },
  "classification": "completed",
  "stdoutPreview": "Hello, world!",
  "stderrPreview": "",
  "nextAction": null
}
```

`status` values:

- `success`
- `failure`
- `skipped`

`phase` values:

- `detect`
- `plan`
- `compile`
- `run`
- `doctor`
- `memory`

`classification` values:

- `completed`
- `compile-failure`
- `runtime-failure`
- `ambiguous-main`
- `missing-tool`
- `missing-source`
- `stale-memory`
- `internal-error`

Preview fields should be bounded. Full compiler/runtime output should still stream to the terminal, not be copied unbounded into JSONL.

### `diagnostic`

A `diagnostic` event records explainable facts that led to a decision.

Payload schema:

```json
{
  "code": "multiple_main_classes",
  "facts": [
    {
      "kind": "main-candidate",
      "value": "com.example.App",
      "source": "src/main/java/com/example/App.java"
    },
    {
      "kind": "main-candidate",
      "value": "com.example.Tools",
      "source": "src/main/java/com/example/Tools.java"
    }
  ],
  "userMessage": "Multiple main classes were found. Run `jv run <MainClass>`.",
  "nextAction": {
    "kind": "choose-main",
    "examples": ["jv run com.example.App", "jv remember main com.example.App"]
  }
}
```

Diagnostics are for both humans and agents. They should be specific enough to support the next action without scraping terminal prose.

### `memory`

A `memory` event records a read, write, acceptance, rejection, or deletion of generated JV memory.

Payload schema:

```json
{
  "operation": "write",
  "key": "lastSuccessfulMainClass",
  "value": "com.example.App",
  "reason": "Run completed successfully",
  "source": "result",
  "stateRevision": 12
}
```

`operation` values:

- `read`
- `write`
- `accept`
- `reject`
- `delete`

Memory events should make it clear whether JV trusted previous memory or ignored it.

### `stale-state`

A `stale-state` event records that existing `.jv/state.json` memory does not match current project truth.

Payload schema:

```json
{
  "staleKeys": ["rememberedMainClass"],
  "reason": "Remembered main class no longer exists in detected source candidates",
  "remembered": {
    "mainClass": "com.example.OldApp",
    "sourceHash": "sha256:old"
  },
  "current": {
    "mainCandidates": ["com.example.App"],
    "sourceHash": "sha256:new"
  },
  "decision": "ignored-memory",
  "nextAction": {
    "kind": "refresh-memory",
    "examples": ["jv remember main com.example.App", "jv run com.example.App"]
  }
}
```

`stale-state` is separate from generic diagnostics because stale generated memory is a first-class agent problem. Agents need to know that `.jv/` existed but was intentionally not trusted.

## `state.json` Schema

`state.json` is the latest snapshot. It should be small, stable, and safe to delete.

```json
{
  "schemaVersion": 1,
  "stateRevision": 12,
  "updatedAt": "2026-04-30T12:00:00Z",
  "projectRoot": "/Users/alex/project",
  "project": {
    "shape": "maven",
    "sourceRoots": ["src/main/java"],
    "buildFiles": ["pom.xml"],
    "libraries": []
  },
  "fingerprint": {
    "sourceHash": "sha256:...",
    "buildHash": "sha256:...",
    "toolchain": {
      "java": "21.0.2",
      "javac": "21.0.2",
      "mvn": "3.9.6"
    }
  },
  "memory": {
    "rememberedMainClass": {
      "value": "com.example.App",
      "source": "user",
      "updatedAt": "2026-04-30T11:55:00Z"
    },
    "lastSuccessfulMainClass": "com.example.App"
  },
  "lastPlan": {
    "runId": "run_01HV7ZJ91BHDYWNSW82J2RC6E4",
    "eventId": "evt_01HV7ZJ9Q2YV1E9M8GJ3R6N4SA",
    "mainClass": "com.example.App",
    "steps": [
      ["mvn", "compile"],
      ["mvn", "exec:java", "-Dexec.mainClass=com.example.App"]
    ]
  },
  "lastResult": {
    "runId": "run_01HV7ZJ91BHDYWNSW82J2RC6E4",
    "eventId": "evt_01HV7ZK8KBVBSJ82RQCFNVZ3D9",
    "status": "success",
    "classification": "completed",
    "updatedAt": "2026-04-30T12:00:04Z"
  },
  "logs": {
    "runs": "runs.jsonl",
    "diagnostics": "diagnostics.jsonl"
  }
}
```

Relationship to `runs.jsonl`:

- `state.json` is a cache and index.
- `runs.jsonl` is the historical record.
- `state.json.lastPlan.eventId` and `state.json.lastResult.eventId` point to event lines in `runs.jsonl`.
- If `state.json` is missing, JV can run from project truth and append new events.
- If `runs.jsonl` is missing but `state.json` exists, JV may use valid state memory but should write a diagnostic event noting history was unavailable.
- If `state.json` conflicts with current source/build fingerprints, JV should emit `stale-state` and prefer current project truth.

## Event Examples

### Successful Run

```jsonl
{"schemaVersion":1,"eventId":"evt_success_1","runId":"run_success","sequence":1,"timestamp":"2026-04-30T12:00:00Z","cwd":"/Users/alex/project","command":{"argv":["jv","run"],"mode":"run"},"eventType":"plan","level":"info","summary":"Planned Maven build and run","payload":{"project":{"shape":"maven","sourceRoots":["src/main/java"],"buildFiles":["pom.xml"],"libraries":[]},"mainClass":{"selected":"com.example.App","source":"detected-single","candidates":["com.example.App"]},"steps":[{"kind":"build","argv":["mvn","compile"],"cwd":"/Users/alex/project"},{"kind":"run","argv":["mvn","exec:java","-Dexec.mainClass=com.example.App"],"cwd":"/Users/alex/project"}],"fingerprint":{"sourceHash":"sha256:source1","buildHash":"sha256:build1","toolchain":{"java":"21.0.2","javac":"21.0.2","mvn":"3.9.6"}}}}
{"schemaVersion":1,"eventId":"evt_success_2","runId":"run_success","sequence":2,"timestamp":"2026-04-30T12:00:04Z","cwd":"/Users/alex/project","command":{"argv":["jv","run"],"mode":"run"},"eventType":"result","level":"info","summary":"Build and run completed successfully","payload":{"status":"success","phase":"run","step":{"kind":"run","argv":["mvn","exec:java","-Dexec.mainClass=com.example.App"],"exitCode":0,"durationMs":973},"classification":"completed","stdoutPreview":"Hello, world!","stderrPreview":"","nextAction":null}}
{"schemaVersion":1,"eventId":"evt_success_3","runId":"run_success","sequence":3,"timestamp":"2026-04-30T12:00:04Z","cwd":"/Users/alex/project","command":{"argv":["jv","run"],"mode":"run"},"eventType":"memory","level":"info","summary":"Updated last successful main class","payload":{"operation":"write","key":"lastSuccessfulMainClass","value":"com.example.App","reason":"Run completed successfully","source":"result","stateRevision":12}}
```

### Compile Failure

```jsonl
{"schemaVersion":1,"eventId":"evt_compile_1","runId":"run_compile_failure","sequence":1,"timestamp":"2026-04-30T12:05:00Z","cwd":"/Users/alex/project","command":{"argv":["jv","run"],"mode":"run"},"eventType":"plan","level":"info","summary":"Planned plain Java compile and run","payload":{"project":{"shape":"plain-java","sourceRoots":["src"],"buildFiles":[],"libraries":[]},"mainClass":{"selected":"Main","source":"detected-single","candidates":["Main"]},"steps":[{"kind":"build","argv":["javac","-d","bin","src/Main.java"],"cwd":"/Users/alex/project"},{"kind":"run","argv":["java","-cp","bin","Main"],"cwd":"/Users/alex/project"}],"fingerprint":{"sourceHash":"sha256:source2","buildHash":"sha256:none","toolchain":{"java":"21.0.2","javac":"21.0.2","mvn":null}}}}
{"schemaVersion":1,"eventId":"evt_compile_2","runId":"run_compile_failure","sequence":2,"timestamp":"2026-04-30T12:05:01Z","cwd":"/Users/alex/project","command":{"argv":["jv","run"],"mode":"run"},"eventType":"result","level":"error","summary":"Compilation failed","payload":{"status":"failure","phase":"compile","step":{"kind":"build","argv":["javac","-d","bin","src/Main.java"],"exitCode":1,"durationMs":184},"classification":"compile-failure","stdoutPreview":"","stderrPreview":"src/Main.java:7: error: cannot find symbol","nextAction":{"kind":"fix-compile-error","details":"Read compiler output and update source before rerunning `jv run`."}}}
```

### Runtime Failure

```jsonl
{"schemaVersion":1,"eventId":"evt_runtime_1","runId":"run_runtime_failure","sequence":1,"timestamp":"2026-04-30T12:10:00Z","cwd":"/Users/alex/project","command":{"argv":["jv","run"],"mode":"run"},"eventType":"plan","level":"info","summary":"Planned plain Java compile and run","payload":{"project":{"shape":"plain-java","sourceRoots":["src"],"buildFiles":[],"libraries":[]},"mainClass":{"selected":"Main","source":"detected-single","candidates":["Main"]},"steps":[{"kind":"build","argv":["javac","-d","bin","src/Main.java"],"cwd":"/Users/alex/project"},{"kind":"run","argv":["java","-cp","bin","Main"],"cwd":"/Users/alex/project"}],"fingerprint":{"sourceHash":"sha256:source3","buildHash":"sha256:none","toolchain":{"java":"21.0.2","javac":"21.0.2","mvn":null}}}}
{"schemaVersion":1,"eventId":"evt_runtime_2","runId":"run_runtime_failure","sequence":2,"timestamp":"2026-04-30T12:10:02Z","cwd":"/Users/alex/project","command":{"argv":["jv","run"],"mode":"run"},"eventType":"result","level":"error","summary":"Program exited with a runtime error","payload":{"status":"failure","phase":"run","step":{"kind":"run","argv":["java","-cp","bin","Main"],"exitCode":1,"durationMs":88},"classification":"runtime-failure","stdoutPreview":"","stderrPreview":"Exception in thread \"main\" java.lang.NullPointerException","nextAction":{"kind":"fix-runtime-error","details":"The project compiled successfully. Inspect the runtime stack trace before changing JV configuration."}}}
```

### Ambiguous Main

```jsonl
{"schemaVersion":1,"eventId":"evt_ambiguous_1","runId":"run_ambiguous_main","sequence":1,"timestamp":"2026-04-30T12:15:00Z","cwd":"/Users/alex/project","command":{"argv":["jv","run"],"mode":"run"},"eventType":"diagnostic","level":"warn","summary":"Multiple main classes were found","payload":{"code":"multiple_main_classes","facts":[{"kind":"main-candidate","value":"com.example.App","source":"src/main/java/com/example/App.java"},{"kind":"main-candidate","value":"com.example.Tools","source":"src/main/java/com/example/Tools.java"}],"userMessage":"Multiple main classes were found. Run `jv run <MainClass>`.","nextAction":{"kind":"choose-main","examples":["jv run com.example.App","jv remember main com.example.App"]}}}
{"schemaVersion":1,"eventId":"evt_ambiguous_2","runId":"run_ambiguous_main","sequence":2,"timestamp":"2026-04-30T12:15:00Z","cwd":"/Users/alex/project","command":{"argv":["jv","run"],"mode":"run"},"eventType":"result","level":"error","summary":"JV refused to guess a main class","payload":{"status":"failure","phase":"plan","step":null,"classification":"ambiguous-main","stdoutPreview":"","stderrPreview":"","nextAction":{"kind":"choose-main","examples":["jv run com.example.App","jv run com.example.Tools"]}}}
```

### Stale Remembered Main

```jsonl
{"schemaVersion":1,"eventId":"evt_stale_1","runId":"run_stale_main","sequence":1,"timestamp":"2026-04-30T12:20:00Z","cwd":"/Users/alex/project","command":{"argv":["jv","run"],"mode":"run"},"eventType":"memory","level":"info","summary":"Read remembered main class","payload":{"operation":"read","key":"rememberedMainClass","value":"com.example.OldApp","reason":"state.json contained a remembered main class","source":"state","stateRevision":11}}
{"schemaVersion":1,"eventId":"evt_stale_2","runId":"run_stale_main","sequence":2,"timestamp":"2026-04-30T12:20:00Z","cwd":"/Users/alex/project","command":{"argv":["jv","run"],"mode":"run"},"eventType":"stale-state","level":"warn","summary":"Remembered main class is stale","payload":{"staleKeys":["rememberedMainClass"],"reason":"Remembered main class no longer exists in detected source candidates","remembered":{"mainClass":"com.example.OldApp","sourceHash":"sha256:old"},"current":{"mainCandidates":["com.example.App"],"sourceHash":"sha256:new"},"decision":"ignored-memory","nextAction":{"kind":"refresh-memory","examples":["jv remember main com.example.App","jv run com.example.App"]}}}
{"schemaVersion":1,"eventId":"evt_stale_3","runId":"run_stale_main","sequence":3,"timestamp":"2026-04-30T12:20:01Z","cwd":"/Users/alex/project","command":{"argv":["jv","run"],"mode":"run"},"eventType":"plan","level":"info","summary":"Planned run using current detected main class","payload":{"project":{"shape":"maven","sourceRoots":["src/main/java"],"buildFiles":["pom.xml"],"libraries":[]},"mainClass":{"selected":"com.example.App","source":"detected-single","candidates":["com.example.App"]},"steps":[{"kind":"build","argv":["mvn","compile"],"cwd":"/Users/alex/project"},{"kind":"run","argv":["mvn","exec:java","-Dexec.mainClass=com.example.App"],"cwd":"/Users/alex/project"}],"fingerprint":{"sourceHash":"sha256:new","buildHash":"sha256:build2","toolchain":{"java":"21.0.2","javac":"21.0.2","mvn":"3.9.6"}}}}
```

## Compatibility And Migration

Current runner-core writes simple `state.json` and `runs.jsonl` data after successful runs. Milestone 2 should preserve that data where possible and avoid breaking users who already have `.jv/`.

Migration rules:

- Treat missing `schemaVersion` as legacy schema version `0`.
- Read legacy `state.json.lastSuccessfulMainClass` as `memory.lastSuccessfulMainClass`.
- Read legacy `state.json.lastPlan` as a best-effort `lastPlan` snapshot.
- Preserve existing `runs.jsonl` lines. Do not rewrite append-only history in place.
- New events should use `schemaVersion: 1`.
- If legacy JSONL lines have no envelope, consumers should treat them as historical diagnostic facts, not as full event records.
- On the first Milestone 2 write, upgrade `state.json` to schema version `1`.
- If upgrade fails, JV should ignore `.jv/state.json`, append a `stale-state` or `diagnostic` event when possible, and continue from project truth.

Legacy event example:

```json
{"event":"executed","command":["mvn","compile"],"exitCode":0}
```

Compatible interpretation:

```json
{
  "schemaVersion": 0,
  "eventType": "result",
  "summary": "Legacy executed event",
  "payload": {
    "legacy": {
      "event": "executed",
      "command": ["mvn", "compile"],
      "exitCode": 0
    }
  }
}
```

JV does not need to physically rewrite the line. This interpretation is for readers.

## Privacy And Local-Only Concerns

`.jv/` is local generated memory. It may contain project paths, class names, command arguments, tool versions, and bounded output previews. That is useful for agents, but it can still reveal private project structure.

Rules:

- JV must not transmit `.jv/` data anywhere.
- JV should not store full source file contents.
- JV should bound `stdoutPreview` and `stderrPreview`.
- JV should avoid logging environment variables by default.
- JV should redact obvious secrets from command previews and output previews where practical.
- JV should assume `.jv/` may be committed accidentally and keep contents low-risk.
- Docs should recommend adding `.jv/` to `.gitignore` for normal projects.

Local-only does not mean harmless. The event schema should make useful debugging possible without turning `.jv/` into a broad local data dump.

## Testing And Success Criteria

Schema and compatibility:

- New `runs.jsonl` lines are valid JSON objects with `schemaVersion: 1`.
- Every event has `eventId`, `runId`, `sequence`, `timestamp`, `eventType`, `level`, `summary`, and `payload`.
- `sequence` is monotonic within one `runId`.
- Legacy `state.json` can be read without crashing.
- Legacy `runs.jsonl` lines remain untouched.
- First schema version `1` write upgrades `state.json` without requiring user action.

Behavioral events:

- Successful run writes `plan`, `result`, and `memory` events.
- Compile failure writes a `result` event with `classification: compile-failure`.
- Runtime failure writes a `result` event with `classification: runtime-failure`.
- Ambiguous main writes a `diagnostic` event and a failed `result` event with `classification: ambiguous-main`.
- Stale remembered main writes a `memory` read event, a `stale-state` event, and then plans from current project truth if possible.

State relationship:

- `state.json.lastPlan.eventId` points to the latest plan event.
- `state.json.lastResult.eventId` points to the latest terminal result event.
- Deleting `.jv/state.json` does not prevent `jv run` from working.
- Deleting `.jv/runs.jsonl` does not make valid current `state.json` unusable, but the next JV command starts a new event history.

Privacy:

- Output previews are bounded.
- Source contents are not stored.
- Environment variables are not logged by default.
- `.jv/` data remains local unless the user explicitly moves or commits it.

Milestone 2 is successful when an agent can inspect `.jv/state.json` and the recent tail of `.jv/runs.jsonl` after any run attempt and reliably answer:

1. What project did JV think this was?
2. What main class did JV select, and why?
3. What commands did JV plan to run?
4. Which phase failed, if any?
5. Was generated memory trusted, updated, or rejected as stale?
6. What is the next useful action?
