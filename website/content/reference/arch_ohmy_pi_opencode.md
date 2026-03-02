# Architecture Research: oh-my-pi + opencode

**Research Date**: 2026-03-02  
**Target**: powerglide - Zig 0.15.2 CLI coding agent  
**Sources**: oh-my-pi (primary), opencode (secondary)  
**Analysis Method**: Repomix XML pattern extraction

---

## oh-my-pi Key Patterns

### 1. Agent Loop State Machine Design

**Core Files**: `packages/agent/src/agent-loop.ts`, `packages/agent-core/src/types.ts`

**Architecture**:
```typescript
// Two-tier agent execution
export class Agent {
  #state: AgentState
  constructor(opts: AgentOptions = {})
}

// Low-level loop functions
export async function agentLoop(
  messages: UserMessage[],
  ctx: AgentContext,
  config: AgentLoopConfig
): AsyncIterable<AgentEvent>

export async function agentLoopContinue(
  ctx: AgentContext,
  config: AgentLoopConfig
): AsyncIterable<AgentEvent>
```

**Key Insights**:
- **Separate entry points**: `agentLoop()` for new prompts, `agentLoopContinue()` for retry/resume without adding new user message
- **Validation**: `agentLoopContinue()` requires last message to be `user` or `toolResult` (prevents invalid state)
- **Event-driven state**: All state changes emit typed events (`AgentEvent` union):
  - `agent_start` / `agent_end`
  - `message_start` / `message_update` / `message_end`
  - `turn_end`
  - `tool_execution_start` / `tool_execution_end`
- **Streaming integration**: `assistantMessageEvent` carries raw provider stream events for TUI updates
- **Steering**: Queued user messages can interrupt ongoing generation, abort remaining tool calls, emit error tool results

**State Machine** (from documentation):
```
User Prompt → LLM Call → Tool Calls? → Tool Results → LLM Call → Tool Calls... → Done
    ↓              ↓           ↓             ↓          ↓           ↓
agent_start  message_start  tool_exec_*  message_update  turn_end  agent_end
```

**Zig Port Considerations**:
- Use `union` for `AgentEvent` with tag dispatch
- Stream support via `std.io.Reader` and async iteration
- State machine as explicit `enum` with transition validation
- Shared `AbortController`-like cancellation token across all operations

---

### 2. Terminal/PTY Management Implementation

**Core Files**: `pty.rs` (Rust native), `natives-shell-pty-process.md`, `src/exec/bash-executor.ts`

**Architecture**:
- **Native PTY**: Rust N-API module (`lib/pty.napi`) for low-level PTY handling
- **Streaming**: `on_chunk` callback receives UTF-8 chunks via threadsafe function
- **Session isolation**: `Shell.run()` passes `sessionKey: this.sessionId` for per-session process reuse
- **Dual execution paths**:
  - **PTY mode**: Interactive overlay in TUI, full terminal semantics
  - **Non-PTY**: Streamed tail updates, simpler for RPC/headless

**Key Classes**:
```rust
// Rust side
struct PtySession {
  master_fd: RawFd,
  child_pid: pid_t,
  // ... window size, modes
}

#[napi] // exposes to TypeScript
fn run_pty_sync(
  config: RunConfig,
  on_chunk: Option<ThreadsafeFunction<String>>,
  control_rx: Receiver<PtyControlCommand>,
  ct: CancellationToken
) -> Result<ExitStatus>
```

**Output Handling**:
- `OutputSink` (`src/session/streaming-output.ts`): All execution paths use this
  - **Sanitization**: Every chunk sanitized (ANSI codes, invalid UTF-8 → U+FFFD)
  - **Tail buffer**: In-memory ring buffer for live TUI display
  - **Artifact spill**: When output exceeds threshold, full stream written to artifact file
  - **Truncation metadata**: Summary includes `truncated: true`, `artifact: "artifact://<id>"`

**Zig Port Considerations**:
- Use Zig's `std.process.Child` with PTY support (unix: `forkpty`, windows: `CreatePseudoterminal`)
- Streaming via async reader with buffered chunking
- Separate native PTY module (C ABI) if performance critical, else pure Zig
- Output sink pattern: sanitize → buffer → spill/truncate as single pipeline

---

### 3. Multi-Model/Provider Routing

**Core Files**: `packages/ai/src/` (providers, models), `src/config/model-registry.ts`, `src/provider-models/`

**Architecture**:

```
ModelRegistry
├── Built-in providers (from @oh-my-pi/pi-ai)
│   ├── openai, anthropic, google, amazon-bedrock, etc.
│   └── Static descriptors + dynamic discovery
├── Custom provider overrides (models.yml)
│   ├── baseUrl, apiKey, headers
│   └── modelOverrides per provider+model
└── Runtime discovery (from provider /models endpoint)
    └── Cached in SQLite (models.db) with versioning
```

**Key Features**:
- **Provider descriptors** (`descriptors.ts`): Single source of truth for both runtime and catalog generation
  - `catalogDiscovery`: Supports endpoint-based model listing
  - `api`: `"chat"`, `"responses"`, `"completions"`, `"vertex-ga"`, etc.
  - `defaultModels`: Fallback when discovery fails
- **Context promotion**: On overflow, switch to higher-context model (configured via `contextPromotionTarget`)
- **Transport reattachment**: For websocket-based (Codex), session state persisted across model switches; closed and restarted cleanly
- **Compatibility flags**: Per-provider quirks via `compat` field (e.g., `supportsUsageInStreaming`)
- **Round-robin + session affinity**: Multiple API keys per provider → load balance while maintaining session stickiness

**Model Resolution Order**:
1. Explicit CLI `--model provider/modelId`
2. Saved default from previous session
3. `settings.modelRoles.default` expansion (e.g., `pi/smol` → anthropic/claude-sonnet-4)
4. First available from discovered models (with priority sorting)

**Zig Port Considerations**:
- Registry as `std.AutoHashMap(String, Model)` with provider grouping
- Redis or SQLite for caching (SQLite preferred for embedded)
- LLM provider abstraction as trait/interface:
  ```zig
  const Provider = struct {
      chat: fn(ctx: Context, opts: Options) AsyncIter(StreamEvent),
      providers: []const *const Provider,
  };
  ```
- Context promotion logic: pre-request token estimation, overflow detection → switch

---

### 4. Session Save/Resume/Fork

**Core Files**: `packages/coding-agent/src/session/session-manager.ts`, `agent-session.ts`

**Persistence Format**:
- **JSONL** (NDJSON) append-only file
- **Path pattern**: `~/.omp/agent/sessions/--<cwd-encoded>--/<timestamp>_<sessionId>.jsonl`
- **Artifacts**: `<sessionFile>.jsonl` → directory at same path without extension
  - Session-scoped artifacts: `<artifactDir>/subagent-0/`, `full-output-123.md`, etc.
- **Blob store**: Global `~/.omp/agent/blobs/` with SHA256-addressed files for binary data (images)

**Entry Types** (`SessionEntry` union):
```typescript
type SessionEntry = 
  | SessionHeader              // sessionId, cwd, provider, model, thinkingLevel
  | SessionMessageEntry        // { role: "user" | "assistant" | "toolResult", ... }
  | BranchSummaryEntry         // { type: "branch_summary", summary, branchFromId }
  | CompactionEntry            // { type: "compaction", summary, firstKeptEntryIndex }
  | ThinkingLevelChangeEntry   // thinking level changes
  | ModelChangeEntry           // mid-session model switch
  | CustomEntry                // hook messages, labels
```

**Operations**:

**Fork** (`/fork`):
1. `SessionManager.fork()`: creates new .jsonl file with new UUID, copies `parentSession` link
2. `AgentSession.fork()`: copies artifact directory (best-effort, non-fatal on errors)
3. Switches active session to new file
4. Fails in non-persistent (in-memory) mode

**Resume** (`/resume` or `--resume`):
- **Direct path**: open specified .jsonl file
- **ID prefix match**: search sessions by sessionId prefix
- **Picker UI**: list recent sessions, select one
- **Cross-cwd**: prompt to fork into current project if cwd differs
- **Runtime transition**: `AgentSession.switchSession(path)`:
  - Emit `session_before_switch` (cancellable)
  - Disconnect agent event subscription, abort in-flight work
  - Load entries from new file, rebuild context
  - Reconnect subscription, emit `session_switch`

**Branch** (`/tree` navigation):
- Navigate within same file (no file fork)
- `SessionManager.branch(newLeafId)`: create new `branch_summary` entry → updates `leafId`
- `/branch` (different): creates actual new session file (fork variant)

**Compaction**:
- **Trigger**: `contextTokens > contextWindow - reserveTokens`
- **Process**: Summarize entries since last compaction, append `compaction` entry, prune old entries
- **Overflow recovery**: On `context_length_exceeded`, promote model OR compact + retry

**Zig Port Considerations**:
- JSONL with `std.json` parse/stringify; append-only with `std.fs.File.open(.append)`
- Session tree: maintain `parent_session` fields, `leaf_id` pointer
- Artifact dir: strip `.jsonl`, ensure mkdir, copy_recursive
- Blob storage: global dir, SHA256 hash as filename, content-addressable dedup
- Atomic writes: write temp file → fsync → rename

---

### 5. Tool System

**Core Files**: `src/tools/`, `src/mcp/`, `src/session/agent-session.ts`

**Tool Contract**:
```typescript
interface AgentTool<TParams extends TSchema, TDetails = any> {
  readonly name: string;
  readonly description: string; // rendered with prompt templates
  readonly parameters: TSchema; // TypeBox schema
  readonly execute: AgentToolExecFn<TParams, TDetails>;
  // optional: renderers, permission checks
}

type AgentToolExecFn<TParams, TDetails> = (
  toolCallId: string,
  params: TParams,
  onUpdate: AgentToolUpdateCallback<TDetails>,
  ctx: AgentToolContext,
  signal: AbortSignal
) => Promise<TDetails>;
```

**Built-in Tools**:
- `bash`: Shell command executor (PTY or streaming)
- `python`: Kernel-backed, stateful across cells
- `read`, `write`, `edit`: File operations with truncation/artifacts
- `Task`: Subagent delegation (isolated context window)
- `checkpoint` / `rewind`: Context checkpointing before exploration

**MCP Integration** (Model Context Protocol):
- **Discovery**: `loadAllMCPConfigs()` from capability system + explicit `.mcp.json`
- **Transport**: stdio or HTTP/SSE
- **Protocol**: JSON-RPC with MCP methods (`initialize`, `tools/list`, `tools/call`)
- **Lifecycle**:
  1. `MCPManager.connectServers()`: parallel connect + `tools/list`
  2. Tools wrapped as `MCPTool` or `DeferredMCPTool` (cache-first)
  3. Registered as `mcp_<server>_<tool>` in tool registry
  4. `/mcp reload`: disconnect all, rediscover, `session.refreshMCPTools()`
- **Error handling**: Transport errors → tool result with `MCP error: ...`, abort preserved

**Tool Execution Pipeline**:
1. LLM emits `tool_call` with `id`, `name`, `arguments`
2. `HookToolWrapper` (extension interception):
   - Emit `tool_call` event (pre-exec, can block)
   - Execute underlying tool
   - On success: emit `tool_result` (post-exec, can override content/details)
   - On error: emit `tool_result(isError: true)`, rethrow
3. Tool result converted to message role `toolResult` and appended to session
4. Result may be truncated → artifact file + summary notice

**Concurrency**:
- Parallel tool calls enabled by default (`concurrency: "parallel"`)
- Session-level exclusive tools (e.g., `submit_result`) via `concurrency: "exclusive"`
- Steering between tool calls: check `queue.getQueuedMessages()` after each call

**Zig Port Considerations**:
- Tool registry: `std.StringHashMap(proc: fn(alloc: Allocator, args: json.Value, ctx: *ToolContext) anyerror!json.Value)`
- Schema validation: integrate `TypeBox`-like JSON schema validator (or simplify to struct tags)
- MCP: implement JSON-RPC 2.0, stdio transport with line buffering, HTTP/SSE with HTTP client
- Async execution: all tools async, must support cancellation (`AbortController` equivalent via `std.CancelSignal`)
- Output truncation: configurable tail buffer + artifact spill file

---

### 6. Config Schema Design

**Core Files**: `src/config/settings.ts`, `src/config/settings-schema.ts`, `src/config/model-registry.ts`

**Configuration Layering**:
```
1. Built-in defaults (hardcoded)
2. Global settings: ~/.omp/agent/config.yml
3. Project settings: <cwd>/.omp/settings.json (via capability discovery)
4. Runtime overrides via Settings.set() (writes to global config.yml)
```

**Settings Schema**:
- Type-driven with TypeBox
- Grouped settings (`retry.*`, `compaction.*`, `ttsr.*`, `modelRoles.*`)
- Validation at load time
- Capability providers can contribute settings via `settings` capability

**Discovery Precedence** (per capability type):
1. Built-in defaults
2. Global config-specified extensions (config.yml `extensions: [...]`)
3. Project `settings.json` capabilities
4. Auto-discovery from known paths (`.claude/`, `.omp/`, `extensions/`)
5. Bundled embedded definitions (fallback)

**ModelRegistry Specific**:
- Loads `models.yml` or `~/.config/oh-my-pi/models.yml`
- Structure:
  ```yaml
  providers:
    openai:
      baseUrl: https://api.openai.com/v1
      apiKey: ${OPENAI_API_KEY}
      models:
        gpt-5: { contextWindow: 128000 }
  ```
- Override-only mode: provider exists in builtins, but `models` field empty → only apply overrides

**Zig Port Considerations**:
- Config as `std.json.parse(allocator, []u8, Config)` with explicit structs
- Layered merge: deep copy + override, track provenance for writes
- Schema validation: integrate `zigtags` or custom validator
- Discovery: file system scanning with `std.fs.Dir.walk()` + gitignore filtering
- Env var substitution: `${VAR}` → `std.process.getEnvVar`

---

### 7. Multi-Agent Coordination Patterns

**Core Files**: `src/task/`, `src/extensibility/swarm-extension/`, `src/session/agent-session.ts`

**Subagent (Task tool)**:
- `Task` tool delegates to specialized agent with isolated context
- **Context passing**: `getCompactContext()` excludes system prompts, tool results
- **Context file**: `sessionContextFile` param writes parent context to temp file for subagent to read
- **Output management**: Subagent outputs use `<parent-index>-<requestedId>.md` naming in artifacts
- **Concurrency**: Multiple subagents can run in parallel (handled by parent tool call parallelism)

**Swarm Extension** (multi-agent DAG):
- YAML-defined workflow:
  ```yaml
  pipeline:
    - agent: scout
      output: scout-report
    - agent: worker
      input: scout-report
      parallel: 3
    - agent: reviewer
      input: worker-*
  ```
- **Orchestrator**: `swarm-extension.ts` executes DAG, passes artifacts as context
- **Output aggregation**: Collects all outputs, emits results to parent session

**Agent Discovery**:
- `discoverAgents(cwd, home)`:
  1. Load bundled agents (markdown frontmatter, parsed at startup, cached)
  2. Scan `extensions/agents/`, `.omp/agents/`, project-local
  3. Merge, de-dup by name (higher-priority overrides)
- **Agent definition**: Markdown with YAML frontmatter:
  ```yaml
  ---
  name: code-reviewer
  description: Reviews PRs
  system_prompt: prompts/agents/reviewer.md
  tools: [read, bash, git]
  ---
  ```

**Coordination API** (`AgentSession`):
- `session.fork()`: full session duplication for parallel exploration
- `session.branch(entryId)`: navigate to different point in session tree
- `session.handoff()`: generate handoff document, switch to new session
- Events: `session_before_branch`, `session_branch` for extensions to track

**Zig Port Considerations**:
- Task tool: spawn subprocess running `powerglide` with isolated session dir, pass context via stdin or file
- Swarm: in-process DAG scheduler, each node = Agent instance with shared or separate memory
- Agent registry: `std.StringHashMap(AgentDef)` loaded at startup from configured paths
- Output coordination: artifact dir with structured naming (parent-index-child)

---

## opencode Key Patterns

Based on file structure analysis (opencode is UI-focused, Electron/React app):

### 1. Session & Agent Structure

**File Organization**:
```
src/
├── agent/
│   ├── agent.ts              // Core agent coordination
│   └── agent.test.ts
├── session/
│   ├── session.tsx           // React component
│   ├── session-context-*.ts  // Context management, metrics
│   ├── session-composer-*.tsx // Message composition UI
│   ├── session-*.test.ts
│   └── use-session-*.tsx     // React hooks
├── tool/
│   ├── tool.ts               // Tool registry/execution
│   └── tool.test.ts
├── provider/
│   ├── provider.ts           // LLM provider abstraction
│   ├── openai-compatible-chat-language-model.ts
│   ├── openai-responses-language-model.ts
│   └── copilot-provider.ts
├── terminal/
│   ├── terminal.tsx          // PTY UI component
│   └── terminal-writer.ts    // Stream writer
├── models.tsx                // Model picker UI
└── use-providers.ts          // Provider discovery hook
```

**Key Differences from oh-my-pi**:
- **UI-coupled**: Session as React component with state hooks
- **Provider abstraction**: Simpler, focused on chat/completions APIs
- **Terminal**: Embedded UI component (xterm.js-style), not headless TUI
- **Session storage**: Likely similar JSONL but integrated with app state

**Patterns to Consider**:
- **React hooks** as state management blueprint: `useSessionCommands`, `useSessionHashScroll`
- **Session state**: Atomic updates, undo/redo (`session-undo-redo.ts`), optimistic UI
- **Composer**: Split-pane message editing (`session-composer-dock.tsx`)

** Zig Adaptation**:
- Separate UI layer (TUI) from core state machine (oh-my-pi's `AgentSession` already does this well)
- Session state as pure struct, UI observes via event subscription
- Undo/redo: command pattern or diff-based state snapshots

---

### 2. Tool & Provider Design

**Provider Pattern** (`provider/`):
- **Language model wrapper**: Implements `chat()` or `stream()` methods
- **Prepare tools**: Convert generic tool definitions to provider-specific format (`openai-compatible-prepare-tools.ts`)
- **Provider registry**: UI-driven discovery, API key storage per provider

**Tool Registry** (`tool/tool.ts`):
- Tool as function with schema
- Execution: async, with streaming updates
- Result: typed structure with `content`, `isError?, `details?`

**Similarities to oh-my-pi**: Conceptually same tool contract, but simpler (no MCP, fewer event hooks)

---

### 3. Terminal Integration

- **Terminal as UI widget**: Renders PTY streams, allows direct interaction
- **Terminal writer**: Manages line buffering, scrollback, output sanitization
- **Integration**: Session commands can execute in terminal context (`!` commands equivalent)

**Takeaway**: oh-my-pi's PTY design is more robust (native Rust, dual streaming/PTY modes). opencode shows UX patterns for interactive terminal UI (if powerglide has TUI).

---

## Zig Module Structure Recommendations

Based on patterns, powerglide (Zig 0.15.2) should adopt this structure:

```
src/
├── main.zig                 // CLI entry, arg parsing, bootstrap
├── agent/
│   ├── agent.zig            // Agent struct, state machine
│   ├── loop.zig             // agent_loop / agent_loop_continue
│   ├── context.zig          // AgentContext, options, config
│   ├── events.zig           // Event enum + emit/subscribe
│   └── tools.zig            // Tool registry, execution pipeline
├── session/
│   ├── session.zig          // SessionManager, AgentSession
│   ├── persistence.zig      // JSONL read/write, append
│   ├── entry.zig            // SessionEntry union + serialization
│   ├── tree.zig             // Branch navigation, leaf management
│   ├── compaction.zig       // Summarization, token budgeting, prune
│   └── artifacts.zig        // Artifact dir mgmt, blob store
├── pty/
│   ├── pty.zig              // PTY session (unix: forkpty, windows: ConPTY)
│   ├── shell.zig            // Persistent shell session wrapper
│   └── output.zig           // OutputSink: sanitize, buffer, truncate, spill
├── provider/
│   ├── registry.zig         // ModelRegistry, provider descriptors
│   ├── chat.zig             // Chat API abstraction
│   ├── openai.zig           // OpenAI-compatible client
│   ├── anthropic.zig        // Anthropic client
│   ├── ollama.zig           // Local inference
│   └── descriptors.zig      // Built-in provider+model metadata
├── config/
│   ├── settings.zig         // Layered config (global/project)
│   ├── schema.zig           // Setting definitions + validation
│   ├── discovery.zig        // File scanning, capability loading
│   └── model_config.zig     // models.yml parsing
├── mcp/
│   ├── client.zig           // MCP protocol client
│   ├── transport.zig        // JSON-RPC over stdio/SSE
│   ├── manager.zig          // Server discovery, connection pool
│   └── tool_bridge.zig      // MCP tools → powerglide tools
├── tool/
│   ├── builtin.zig          // bash, python, read, write, edit
│   ├── custom.zig           // User-defined tool loading
│   └── result.zig           // Tool result + truncation metadata
├── ui/
│   ├── tui.zig              // Terminal UI (use `stdia` or `zoo`)
│   ├── components.zig       // Message list, tool output, prompts
│   ├── renderer.zig         // ANSI, paging, markdown
│   └── controller.zig       // Input handling, command dispatch
├── util/
│   ├── token_counter.zig    // tiktoken-style counting (BPE/CL100K)
│   ├── backoff.zig          // Exponential retry with jitter
│   ├── blob.zig             // SHA256-addressed global storage
│   └── fs.zig               // Globs, gitignore, scanning
└── lib.zig                  // Public API exports

// Optional native addon for performance:
extras/
├── pty_native/              // C library for fast PTY (like oh-my-pi's pty.rs)
└── tokenizer/               // Fast BPE tokenization
```

**Build Strategy**:
- Single executable (static linking)
- Optional dynamic libs for platform-specific PTY (libutil, Windows ConPTY via kernel32)
- Zig 0.15.2 async/await with `std.event.Loop`
- Cross-platform: unix (forkpty/termios), windows (CreateProcess + ConPTY)

---

## Critical Implementation Notes

### Must-Haves (from oh-my-pi lessons)

1. **State Machine Discipline**
   - All state transitions emit events; never mutate state silently
   - Separate `agentLoop` (new) vs `agentLoopContinue` (resume)
   - Guard against invalid `agentLoopContinue` calls (must end in `user` or `toolResult`)

2. **PTY Dual-Mode**
   - Implement both interactive PTY (full terminal) and streaming non-PTY
   - Environment variable `PI_NO_PTY=1` for headless/server mode
   - `OutputSink` pipeline: sanitize → buffer → truncate → artifact spill

3. **Session Format**
   - JSONL append-only with typed `SessionEntry` union
   - Separate artifact directory (same base name without `.jsonl`)
   - Blob store for large binary (images) with SHA256 addressing
   - Transient fields stripped on persistence (`partialJson`, `jsonlEvents`)

4. **Retry vs Compaction**
   - **Retry**: For transient API errors (rate limit, 5xx, usage-limit)
   - **Compaction**: For context overflow (separate path, not in retry)
   - Exponential backoff configurable (default 2s base, max 3 retries)
   - Retry state tracked in `AgentSession`, resets on first successful non-aborted message

5. **Tool Pipeline**
   - Pre-exec `tool_call` event → can block execution (extensions)
   - Post-exec `tool_result` event → can override content/details/isError
   - Tool result truncation: `truncationFromSummary(result, { direction: "tail" })`
   - Artifact allocation for large tool outputs (bash long runs, python plots)

6. **Model Routing**
   - Provider descriptors with discovery capabilities
   - SQLite cache for model metadata (`models.db`)
   - Context promotion before compaction on overflow
   - Session-scoped provider state (WebSocket connections) stored with session

7. **Configuration Layering**
   - Global (`~/.config/powerglide/config.yml`) overrides project (`.powerglide/settings.json`)
   - Capability discovery: providers can contribute settings/hooks/tools
   - Settings schema validated at load, defaults hardcoded

8. **Event System**
   - Publish-subscribe with ordered handlers
   - Errors in event handlers: catch → emit `extension_error` event → continue
   - Session lifecycle events: `session_start`, `session_switch`, `session_before_switch` (cancellable)
   - Agent events forwarded to RPC consumers as JSON

9. **Concurrency Model**
   - Parallel tool calls by default (`concurrency = parallel`)
   - Session-level exclusive tools via `concurrency = exclusive`
   - Use async/await throughout; cancellation tokens shared

10. **MCP Integration** (if needed)
    - JSON-RPC 2.0 over stdio or HTTP/SSE
    - `initialize`, `notifications/initialized`, `tools/list`, `tools/call`
    - Deferred tools: show in registry even if server not ready yet, block on call
    - Cache tool definitions in SQLite
    - Reload via disconnect + rediscover + refresh

### Performance & Correctness

- **Empty-result fast recheck**: Cache negative scan results, recheck on file change or after TTL
- **Token counting**: Use fast BPE implementation (`tiktoken` CL100K_base or o200k_base for code)
- **Streaming**: Throttle high-frequency provider deltas (100ms debounce) before TUI render
- **Artifact I/O**: Stream large outputs directly to file, don't buffer fully in memory
- **Database**: SQLite with WAL mode for concurrent reads/writes (sessions, models cache, settings)

### Zig 0.15.2 Specific

- Use `std.event.Loop` for async runtime; single-threaded unless offloading to native PTY/tokenizer
- `std.process.Child` with PTY requires platform-specific code; wrap in `#ifdef`-like `switch (builtin.os)`
- JSON: `std.json` (slow) → consider fast JSON library (jsontree, rapidjson Zig port) if profiling shows bottleneck
- Memory: arena allocators for request-scope, `std.heap.GeneralPurposeAllocator` for long-lived
- Testing: `std.testing` with fixtures for session JSONL round-trip

### Pitfalls to Avoid

- **Do not** mix PTY and non-PTY in same execution path; select at tool call entry based on UI availability
- **Do not** persist transient fields (`partialJson`, `jsonlEvents`) to session file
- **Do not** block agent loop on `tool_call` events that take long; use async non-blocking handlers
- **Do not** allow compaction to run while agent is streaming (abort first)
- **Do not** assume single-model session: model can change mid-session via promotion or manual switch
- **Do not** use naive string concatenation for prompts; token budget must account for tool descriptions, system prompts, context

---

## Summary

oh-my-pi provides a **battle-tested, feature-rich reference**:
- Full-featured agent state machine with events
- Robust session persistence (JSONL + artifacts + blobs)
- Multi-provider model routing with caching
- Comprehensive tool system (builtin + custom + MCP)
- Dual PTY/streaming modes
- Compaction + branching for long sessions
- Retry, TTSR, checkpointing

opencode shows **UI/UX patterns** for React-based frontend but core agent logic mirrors oh-my-pi's design.

**For Zig implementation**:
- Port oh-my-pi's state machine and session design (proven)
- Keep architecture layered: agent → session → provider → tools
- Use Zig'sasync/await and event loops for concurrency
- Prefer simplicity: MCP optional, bundling optional, but JSONL + artifacts essential
- Implement native PTY early for interactive mode, but keep non-PTY fallback

**Recommended reading from repomix**:
- `packages/agent/src/agent-loop.ts`
- `packages/coding-agent/src/session/agent-session.ts`
- `packages/coding-agent/src/session/session-manager.ts`
- `packages/ai/src/` (provider abstraction)
- `docs/mcp-runtime-lifecycle.md`
- `docs/compaction.md`
- `docs/session-operations-export-share-fork-resume.md`

---
