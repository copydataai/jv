# JV Next Product Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` for implementation. The product areas were designed in parallel, but most core changes touch `jv.sh`; implement in the dependency order below unless using isolated worktrees and an explicit merge plan.

**Goal:** Turn JV from an explainable runner into an agent-ready development loop: structured event memory, retryable failures, machine-readable project health, better main-class guidance, watch mode, and hardened distribution.

**Architecture:** Keep the active product in the tracked Bash CLI (`jv.sh`). Do not use or modify the untracked `cli/` Java prototype in this batch. Preserve generated `.jv/` memory as append-only, backward-compatible state. Avoid runtime dependencies beyond Bash, Java, and existing toolchains.

**Parallelization Strategy:**

- **Spec/design work:** done in parallel across six domains.
- **Implementation work:** parallelize only where write sets do not collide.
- **Core CLI lanes:** event writer, retry, doctor JSON, main-class UX, and watch all touch `jv.sh`; implement these sequentially or in isolated worktrees with careful integration.
- **Distribution lane:** can run mostly in parallel after `JV_VERSION` is added, but it still has small `jv.sh` and docs touchpoints.

---

## Dependency Map

1. **Schema v1 event writer**
   - Foundation for retry, history quality, and future repair briefs.
   - Must happen before `jv retry` so retry can depend on structured, safe fields.

2. **Retry command**
   - Depends on failure/blocker events with stable retry fields.
   - Should also expose `--dry-run` and `--json` for agents.

3. **Main-class selection UX**
   - Independent of event writer, but improves retry commands and blocked-run guidance.
   - Keep ranking suggestive; do not auto-run a guessed class.

4. **Doctor JSON**
   - Machine-readable project health via `jv doctor --json`.
   - Can be implemented after ranking so JSON can include ranked candidates.

5. **Watch mode**
   - Reuses `run_java`, planner failures, retry display, and event writing.
   - Implement after the core loop is stable.

6. **Distribution hardening**
   - Version command, installer improvements, release script, completions, Homebrew template.
   - Can be implemented mostly independently once `JV_VERSION` is introduced.

---

## Task 1: Schema v1 Event Writer Everywhere

**Files:**

- Modify `jv.sh`
- Modify `tests/run-tests.sh`
- Optional docs update only if CLI contract changes

**Behavior:**

- Make `append_event_json` the only writer to `.jv/runs.jsonl`.
- Retire any legacy-shaped writer or keep it only as a schema v1 compatibility wrapper.
- Keep new JSONL records append-only with:
  - `schemaVersion`
  - `eventType`
  - `runId`
  - `sequence`
  - `timestamp`
  - `cwd`
  - `command`
  - `summary`
  - `payload`
- Preserve old and corrupt log lines; never migrate or rewrite history.
- Keep `history` / `events` read-only.
- Keep `explain` side-effect free.
- Add event coverage for standalone `jv compile`.
- Ensure event write failures are non-fatal for otherwise successful user work.

**Tests:**

- `jv compile` success writes `execution_start` and `execution_result`.
- `jv compile` failure writes `execution_result` with `status: failure`, non-zero `exitCode`, and compile classification.
- `jv run` compile failure does not double-write standalone compile events.
- `doctor` with blockers writes diagnostic events only.
- `explain` creates no `.jv/`.
- `remember` / `forget` write valid schema v1 `memory_write` events.
- No new write contains top-level legacy `"event":"executed"`.
- Mixed legacy, corrupt, and schema v1 history still renders.

---

## Task 2: `jv retry`

**Files:**

- Modify `jv.sh`
- Modify `tests/run-tests.sh`
- Modify `README.md`
- Modify `EXAMPLES.md`

**CLI:**

```bash
jv retry
jv retry --dry-run
jv retry --json
```

**Behavior:**

- Scan `.jv/runs.jsonl` newest-first.
- Select the newest failed or blocked retryable run.
- Print a stable preflight block:

```text
JV retry
Source: .jv/runs.jsonl
Reason: compile_failed
Retry command: jv run Main alpha
```

- Execute the retry command for plain `jv retry`.
- Return the retried command exit code.
- Return `1` when no retryable failure exists.
- `--dry-run` and `--json` never execute.
- Never eval arbitrary shell strings. Accept only safe `jv run [simple args...]`, then call `run_java` directly.

**Tests:**

- Missing `.jv/` exits `1`, prints empty state, creates no files.
- Success-only history exits `1`.
- Compile failure then source fix then `jv retry` succeeds.
- `--dry-run` prints reason and retry command without executing.
- `--json` emits parseable selection JSON.
- Corrupt JSONL lines are skipped.
- Unsafe retry command is rejected.
- Help, README, and examples document retry.

---

## Task 3: Ranked Main-Class Guidance

**Files:**

- Modify `jv.sh`
- Modify `tests/run-tests.sh`
- Modify `README.md` / `EXAMPLES.md` if output examples change

**Behavior:**

- When multiple mains exist, show a ranked, deterministic list and concrete next commands.
- Keep `jv run` non-interactive.
- Do not auto-select a heuristic candidate.
- Preserve explicit main and remembered main semantics.
- Rank using:
  - last successful main first for guidance, but not auto-selection
  - `Main`
  - names ending in `App` or `Application`
  - project-name match
  - shallow path/package depth
  - de-prioritize test/tool/util/helper/example/scratch names
  - lexical tie-breaker
- Include ranked candidates in `doctor` and optionally event/state planner metadata.

**Tests:**

- Ambiguous plain Java mains show numbered candidates.
- `doctor` reports rank reasons.
- `explain` shows the same ranking without side effects.
- Last successful main ranks first but does not auto-select.
- Remembered main still auto-selects.
- Stale remembered main includes ranked replacement suggestions.
- Maven ambiguous mains use the same ranking path.

---

## Task 4: `jv doctor --json`

**Files:**

- Modify `jv.sh`
- Modify `tests/run-tests.sh`
- Modify `README.md`
- Modify `EXAMPLES.md`

**CLI:**

```bash
jv doctor --json
```

**Behavior:**

- Text `jv doctor` remains unchanged.
- JSON mode emits one JSON document and exits `0` even when blockers exist.
- Reject unknown flags and extra args.
- Do not compile, run, create `bin/`, or update `.jv/state.json`.
- Preserve existing doctor diagnostic event behavior unless deliberately changed.

**Schema:**

- `schemaVersion`
- `command`
- `cwd`
- `status`: `ok`, `warn`, or `blocked`
- `project`
- `tools`
- `main`
- `plan`
- `memory`
- `reasons`
- `warnings`
- `blockers`
- `nextAction`

**Tests:**

- Plain project returns `status: ok` and selected main.
- Ambiguous project returns `status: blocked` with candidates and blockers.
- Unknown project returns `status: blocked`.
- Memory fields render after a successful run.
- JSON mode does not create `bin/` or `.jv/state.json`.
- Extra args fail.
- Validate with `jq` when available.

---

## Task 5: `jv watch`

**Files:**

- Modify `jv.sh`
- Modify `tests/run-tests.sh`
- Modify `README.md`
- Modify `EXAMPLES.md`

**CLI:**

```bash
jv watch [ClassName] [args...]
```

**Behavior:**

- Run once immediately using the same planner and execution path as `jv run`.
- Watch Java sources and rerun on content/path changes.
- Plain Java watches `src/**/*.java`.
- Maven watches `src/main/java/**/*.java`.
- No native file watcher dependency; use portable polling with `find`, `sort`, and `cksum`.
- Keep watch alive after compile, runtime, or planner failures when a source root exists.
- `Ctrl-C` exits cleanly with status `130`.

**Tests:**

- Help lists `watch`.
- Bounded process test sees initial output, modifies source, then sees second output.
- Compile failure during watch does not kill the watcher; fixing source reruns successfully.
- Ambiguous-main blocker can recover when one main is removed.
- Non-Java changes do not trigger a rerun if practical to test.

---

## Task 6: Distribution Hardening

**Files:**

- Modify `jv.sh`
- Modify `install.sh`
- Modify `tests/run-tests.sh`
- Modify `README.md`
- Modify `CONTRIBUTING.md`
- Modify `CHANGELOG.md`
- Add `scripts/release.sh`
- Add `packaging/homebrew/jv.rb`
- Add `completions/jv.bash`
- Add `completions/_jv`
- Add `completions/jv.fish`

**Behavior:**

- Add `JV_VERSION="0.1.0"` as a single source of truth.
- `jv version`, `jv --version`, and `jv -v` print `jv 0.1.0 (bash)`.
- Version command should work when Java is missing.
- Default installer target is `${JV_INSTALL_DIR:-$HOME/.local/bin}`.
- Installer creates the target dir, avoids sudo by default, and warns when not on `PATH`.
- Release script builds a deterministic `dist/jv-$version.tar.gz` and checksums.
- Homebrew formula is a template until real release URLs and SHA values exist.
- Static shell completions cover stable commands and flags.

**Tests:**

- Version commands match.
- Installer smoke test installs into a temp dir.
- Release script syntax and smoke behavior.
- Completion files include documented commands.
- `bash -n` and `shellcheck` pass for shell files.

---

## Final Verification

Run after each task and after full integration:

```bash
tests/run-tests.sh
bash -n jv.sh tests/run-tests.sh install.sh
shellcheck jv.sh tests/run-tests.sh install.sh
```

After distribution hardening, include:

```bash
bash -n scripts/release.sh completions/jv.bash
shellcheck scripts/release.sh completions/jv.bash
JV_INSTALL_DIR="$(mktemp -d)/bin" bash install.sh
```

If `jq` is available, validate JSON outputs from:

```bash
jv history --json
jv retry --json
jv doctor --json
```
