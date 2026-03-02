# Architecture Research: Ralph, Gastown, Loki, Plandex

**Research Date**: 2026-03-02
**Target**: powerglide — Zig 0.15.2 CLI coding agent
**Sources**: ralph (snarktank), gastown (steveyegge), loki (Dark-Alex-17), plandex (plandex-ai)
**Analysis Method**: Pattern extraction from SKILL.md gists + repomix study

---

## 1. The Ralph Loop Pattern

### Core Concept (ralph/snarktank)
Ralph is an autonomous agent loop that runs until all PRD items are complete. The key insight is the **explicit stop condition**:

```
while not all todos "passes: true":
  pick highest-priority story where passes == false
  implement story
  run quality checks (typecheck, lint, test)
  commit changes
  update prd.json → set passes = true
  append to progress.txt
  check if ALL stories passes == true
  if yes: emit <promise>COMPLETE</promise> and stop
```

**Stop signal**: The loop knows it's done when ALL prd.json stories have `passes: true`. The agent emits `<promise>COMPLETE</promise>` as an explicit done signal that the harness can detect.

**Powerglide application**:
- Use a `TODO.json` or `session.json` file to track task completion
- Emit a structured `DONE` marker that the velocity controller can detect
- Max iterations as a hard cap to prevent infinite loops

### Ralph Loop State Machine for powerglide
```
  IDLE ─────────────────────────────────────────────────────────────┐
    │                                                               │
    ▼                                                               │
  LOAD_TASKS ── (all done?) ──────────────────────────────► COMPLETE │
    │                                                               │
    ▼                                                               │
  PICK_TASK (highest priority, passes==false)                       │
    │                                                               │
    ▼                                                               │
  THINKING ── (tool_call) ──► ACTING ── (result) ──► OBSERVING ────┤
    │                                                               │
    ▼                                                               │
  VERIFY (run tests/checks)                                         │
    │                                                               │
    ▼                                                               │
  COMMIT ──► update task status ──► back to LOAD_TASKS ────────────┘
    │
    ▼
  FAILED (on error, with recovery/retry)
```

---

## 2. Gastown Multi-Agent Architecture (steveyegge)

### Key Concepts from gastown
Gastown is a "multi-agent workspace manager" — coordinates multiple specialized agents working in parallel.

**Core architecture**:
- **Workspace**: Isolated environment per agent (git worktree or namespace)
- **Agent roles**: Distinct roles (planner, worker, reviewer, tester) with clear contracts
- **Message bus**: Agents communicate via shared message queue (files or IPC)
- **Leader election**: One orchestrator agent, N worker agents
- **Health monitoring**: Orchestrator tracks worker liveness, respawns on failure

**Key patterns**:
1. **Workspace isolation**: Each worker gets its own working copy to avoid conflicts
2. **Task queue**: Central queue with priority ordering, workers pull tasks
3. **Result aggregation**: Workers push results back to shared store
4. **Circuit breaker**: If a worker fails N times, mark it as unhealthy and skip

**Powerglide application**:
```
Orchestrator (slow, powerful model)
  ├── assigns tasks via task-queue.json
  ├── monitors worker heartbeats
  └── aggregates results

Workers (fast, capable models) × N
  ├── each has isolated workspace (tmpdir or worktree)
  ├── pulls from task queue
  ├── writes progress to worker-{id}.json
  └── signals completion via done-{id}.json
```

---

## 3. Velocity Control

### The "velocity" concept
Velocity = how fast the ralph loop/state machine progresses. Parameters:
- `steps_per_second`: How many loop iterations per second (float, default 1.0)
- `delay_ms`: Pause between tool calls (prevents rate limiting)
- `max_steps`: Hard cap on total iterations
- `think_budget_ms`: Max time for the "thinking" phase before timeout
- `context_limit_fraction`: What % of context window before compaction

**Velocity can be set by**:
1. Human at start: `powerglide run --velocity 2.0 "task"`
2. Agent during session: Write `VELOCITY=0.5` to a control file
3. External orchestrator: Update `session-config.json` which the loop polls

**Implementation**:
```zig
pub const Velocity = struct {
    steps_per_second: f64 = 1.0,
    delay_ms: u32 = 500,
    max_steps: u32 = 100,
    think_budget_ms: u32 = 30_000,

    pub fn computeDelay(self: Velocity) u64 {
        // Base delay from velocity, plus any per-call delay
        const base_ms: u64 = @intFromFloat(1000.0 / self.steps_per_second);
        return base_ms + self.delay_ms;
    }
};
```

---

## 4. Rogue Agent Prevention

### The problem
A rogue/runaway agent is one that:
- Continues past its task completion
- Consumes excessive resources (API calls, time, money)
- Gets into an infinite error recovery loop
- Spawns unbounded sub-agents

### Prevention strategies (from oh-my-opencode observations)
1. **Hard step limit**: `max_steps: u32` — agent is killed after N steps regardless
2. **Heartbeat timeout**: Worker must write `heartbeat.json` every M seconds
3. **Budget tracking**: Track tokens/cost, stop if over budget
4. **Circuit breaker**: If agent calls same tool with same args 3+ times, stop
5. **Completion oracle**: External validator checks if task is truly done
6. **Explicit done signal**: Agent must emit `<POWERGLIDE_DONE>` to terminate cleanly
7. **Parent approval**: For destructive actions, require orchestrator approval

### Implementation
```zig
pub const RogueGuard = struct {
    max_steps: u32,
    heartbeat_interval_ms: u32,
    max_cost_cents: u32,
    repeated_call_limit: u32 = 3,

    last_heartbeat: i64 = 0,
    step_count: u32 = 0,
    cost_cents_used: u32 = 0,

    pub fn check(self: *RogueGuard) !void {
        if (self.step_count >= self.max_steps) return error.StepLimitExceeded;
        const now = std.time.milliTimestamp();
        if (now - self.last_heartbeat > self.heartbeat_interval_ms) {
            return error.HeartbeatTimeout;
        }
    }
};
```

---

## 5. Loki CLI Architecture (Dark-Alex-17)

### Key patterns
- **Plugin/tool system**: Tools registered via a registry with name + schema + handler
- **Provider abstraction**: Multiple LLM providers behind a unified interface
- **Session persistence**: Sessions saved to disk with full message history
- **Interactive mode**: REPL-style loop with readline support
- **Non-interactive mode**: Pipe-friendly, reads prompt from stdin

**Powerglide application**:
- Tool registry as a `HashMap([]const u8, ToolDef)` in Zig
- Provider interface as a Zig `comptime` interface (vtable pattern)
- Session as a JSON file with message history + metadata

---

## 6. Plandex Plan+Execute Pattern (plandex-ai)

### Key concepts
- **Separate planning phase**: Agent produces a structured plan before writing code
- **Diff-based application**: Changes are expressed as diffs, not full rewrites
- **Conflict detection**: Before applying, check for conflicts with existing code
- **Rollback support**: Each plan step is atomic and reversible

**Powerglide application**:
- Before starting a task, emit a `plan.md` with numbered steps
- Each step has a success criterion
- Steps are applied one by one with verification after each

---

## 7. Recommendations for powerglide

### Ralph Loop Design
```
1. Load session state (TODO.json)
2. Select highest-priority incomplete task
3. Enter the thinking → acting → observing loop
4. After each tool call, check stop conditions:
   - Did model emit POWERGLIDE_DONE? → stop
   - All tasks passes==true? → stop
   - Step limit exceeded? → stop with error
   - Budget exceeded? → stop with warning
5. After completing a task, update TODO.json
6. Commit progress
7. Loop back to step 1
```

### Velocity Control Implementation
- Store velocity in `~/.config/powerglide/session-{id}.json`
- Poll this file every N steps for dynamic velocity adjustment
- Expose `powerglide session velocity 2.0` command to adjust live

### Rogue Agent Prevention
- Hard limit: `max_steps = 200` (configurable)
- Heartbeat: worker writes timestamp every 30 seconds
- Monitor watches all workers, kills any with missed heartbeat
- Circuit breaker on repeated identical tool calls

### Inter-Agent Communication
- File-based messages: `~/.powerglide/teams/{team-id}/messages/`
- Simple JSON format: `{ from, to, type, payload, timestamp }`
- No complex IPC needed for initial version
