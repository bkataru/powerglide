# Changelog

All notable changes to the **powerglide** project will be documented in this file.

## [0.2.9] - 2026-03-05

### Added
- **0.8B-BF16 in `trial_quant.zig`** — full precision coverage for all four Qwen3.5 weight classes (0.8B/2B/4B/9B); harness now includes 12 models
- **4B-BF16 measured** — live trial confirms 13/13 in 36 turns / 814s (identical to Q4 and Q8); 4B is saturated at Q4 precision, BF16 runs 2× slower with 45% more RAM — Q8 is the sweet spot
- **0.8B-BF16 confirmed** — 0/13 (same as Q8); failure is a training gap, not quantization noise

### Fixed
- **MCP server type assertion panic** — `handleToolsCall()` accessed `name.string` without validating JSON type; non-string `name` now returns JSON-RPC -32602 instead of crashing
- **MCP server OOM guard** — `run()` stdin accumulation loop now enforces 8 MiB `MAX_LINE_BYTES` limit (matching the client-side guard added in v0.2.8)
- **MCP client error logging** — `sendRequest()` debug print on MCP errors now only logs the `message` field instead of the full `{any}` error object (prevents internal detail leakage)
- **`build.zig.zon` version sync** — was `"0.2.2"` (stale since v0.1.0); now `"0.2.8"`
- **`QuantModel.group` comment** — was `"2B" or "9B"`; updated to reflect all four valid group values
- **`AGENTS.md` velocity example** — stale path `~/.config/powerglide/session-<id>.json`; updated to use actual CLI flag and config file

### Changed
- **`src/main.zig` VERSION** — `"0.2.2"` → `"0.2.8"`; test assertion updated
- **`showcase.smd`** — 2B-BF16 description updated from "predicted" to measured (10/13, worse than Q8 due to memory pressure); 9B-BF16 timing added (1356s vs 484s for Q4); 4B-BF16 confirmed 13/13
- **CLAUDE.md** — trial-quant harness description updated to list all 12 models; version `0.2.8`

## [0.2.8] - 2026-03-05

### Fixed
- **MCP client debug print removed** — `readLine()` was emitting `std.debug.print("MCP RAW: {s}\n")` on every RPC call; removed
- **MCP sendRequest JSON round-trip** — `sendRequest()` was stringifying the result value then callers re-parsed it (4× allocations); now returns a deep-cloned `json.Value` directly via existing `deepCloneValue()`
- **MCP input validation** — replaced force-unwrap `.?` panics in `listTools()` and `callTool()` with explicit `orelse return error.MissingField` / type-tag checks; a malformed MCP server response now returns an error instead of crashing
- **MCP readLine OOM guard** — `readLine()` now enforces an 8 MiB per-message limit; a malicious MCP server that streams without newlines can no longer exhaust memory
- **registry.zig JSON injection** — `listAsJson()` previously interpolated raw `tool.name` / `tool.description` strings into JSON without escaping; replaced with `std.json.fmt()` for both fields
- **tool_bridge.zig indentation** — corrected two mis-indented lines at the top of `mcpToolToTool()`

### Changed
- **CLAUDE.md** — version `0.2.7` → `0.2.8`; roadmap items 16–17 added

## [0.2.7] - 2026-03-04

### Added
- **BF16 trials in `trial_quant.zig`** — `2B-BF16` and `9B-BF16` added to `QUANT_MODELS`; harness now covers the full Q4/Q5/Q6/Q8/BF16 precision curve for both weight classes

### Fixed
- **igllama v0.3.10 — streaming json_mode use-after-free** — streaming handler called `loadGrammar(allocator, "json")` then `defer allocator.free(gs)` inside the if-block, freeing the grammar string while the sampler still held a pointer. Replaced with direct `JSON_GRAMMAR` comptime constant (matching the non-streaming handler); no allocation, no lifetime issue. igllama no longer crashes when `response_format: {"type":"json_object"}` is sent on a streaming endpoint.

### Changed
- **CLAUDE.md** — version `0.2.7`; roadmap item 14–15 updated

## [0.2.6] - 2026-03-04

### Added
- **T14–T17 in trial.zig** — four new agentic task categories: code generation + `zig fmt` validation (T14), JSON round-trip write/read/verify (T15), error recovery from a failed command (T16), and multi-source synthesis from two `head` calls (T17)
- **`examples/trial_quant.zig`** — quantization sensitivity harness; runs T01–T13 × Q4/Q5/Q6/Q8 on 2B and 9B, managing igllama lifecycle sequentially on `:8090`; outputs side-by-side pass-rate table per quant level
- **`zig build trial-quant`** — new build step for the quant sensitivity harness

### Changed
- **`examples/trial.zig`** — doc comment and task count updated to T01–T17
- **`website/content/showcase.smd`** — BF16 case study finalized (removed "pending"/"trial in progress"); 2B-BF16 analytically confirmed capacity-limited; added Future Directions section covering quant curve, speed benchmark, context sensitivity, multi-model routing, and extended task library
- **CLAUDE.md** — version `0.2.6`; roadmap items 14–16 added; trial/quant harness build steps documented

### Removed
- **`examples/trial_bf16.zig`** — removed: BF16 confirmed impractical on CPU-only hardware (0/13 same as Q8 for 0.8B; others already saturated); 2–4× RAM cost with zero task improvement; Q8 is optimal

## [0.2.5] - 2026-03-04

### Added
- **BF16 trial harness** — `examples/trial_bf16.zig` runs T01–T13 × 4 Qwen3.5 models (0.8B/2B/4B/9B) at full BF16 precision; manages igllama lifecycle (spawn, health-poll, kill) per model
- **`zig build trial-bf16`** — new build step mirroring `zig build trial`
- **igllama json_mode** — patched igllama v0.3.9: `response_format: {"type":"json_object"}` now wires `JSON_GRAMMAR` GBNF constraint into the llama.cpp sampler chain via `llama_sampler_init_grammar()`

### Fixed
- **Shell injection in grep/glob tools** — `grep_handler` and `glob_handler` previously interpolated user-controlled `pattern`/`path` into shell command strings via `std.fmt.allocPrint` + `/bin/sh -c`. Replaced with direct `execve`-style argv arrays (`grep -rn -- pattern path`, `find path -name pattern -type f`). Output truncated to 100 lines post-hoc.
- **MCP tool name validation** — `mcpToolToTool` now validates `server_name` and `mcp_tool.name` against `[a-zA-Z0-9_-]` before constructing the prefixed name; returns `error.InvalidToolName` for malformed inputs.
- **README port/model mismatch** — corrected local LLM section: full 4-port lineup (`:8090–:8093`), added 2B/9B models, fixed 4B port (`:8092` not `:8091`).

### Changed
- **CLAUDE.md**: version bumped to 0.2.5; 9B model corrected to `Qwen3.5-9B-UD-Q4_K_XL.gguf`; roadmap items 12–14 added.

## [0.2.4] - 2026-03-04

### Added
- **Q8 quantization for 2B and 9B** — downloaded `Qwen3.5-2B-Q8_0.gguf` (1.9 GB) and `Qwen3.5-9B-Q8_0.gguf` (8.9 GB) via `igllama pull`; both now run at full Q8 precision
- **Quantization sensitivity findings** — Q8 vs Q4 trial: 2B improved from 8/13 to 11/13 (+3 tasks, 42% fewer turns); 9B hallucination on T01 persists but tool-use tasks now all correct; 0.8B and 4B unaffected

### Changed
- **Port layout**: 2B now serves `Qwen3.5-2B-Q8_0.gguf` on :8091; 9B now serves `Qwen3.5-9B-Q8_0.gguf` on :8093
- **trial.zig ENDPOINTS**: updated model filenames from UD-Q4_K_XL to Q8_0 for 2B and 9B
- **CLAUDE.md**: updated local LLM lineup to reflect Q8 models

### Fixed
- **9B hallucination partially resolved** — at Q8, 9B correctly runs tools for T07/T12/T13/T06 (was hallucinating from memory at Q4); T01 VERSION still hallucinated in 1-turn responses

## [0.2.3] - 2026-03-04

### Added
- **Zig trial harness** — `examples/trial.zig` runs T01–T13 across the full Qwen3.5 lineup via `zig build trial`; replaces Python scripts; pure Zig, part of the build system
- **Full Qwen3.5 lineup** — 4 weight classes now triaged: 0.8B-Q8 (:8090), 2B-Q4 (:8091), 4B-Q8 (:8092), 9B-Q4 (:8093); GGUFs downloaded via `igllama pull`
- **Showcase rewrite** — Case Studies 5–6 replaced with Zig trial results; 9B added; qwen2.5-coder-0.5b removed throughout; new "9B hallucinates, 4B verifies" finding documented

### Fixed
- **Harness: flat-args fallback** — models that emit `{"tool":"bash","command":"..."}` at top level (no `args` wrapper) now dispatch correctly
- **Harness: PARSE_ERR on pretty-printed JSON** — igllama json_mode emits literal `\n` between tokens; `unescapeControlChars` + retry resolves without model restart
- **Harness: escape-loop prevention** — feeding "unknown tool" back to small models caused exponential backslash escaping; replaced with targeted format reminder

### Changed
- **Port layout updated**: 0.8B→:8090, 2B→:8091, 4B→:8092, 9B→:8093 (was 4B on :8091, 0.5B-coder on :8092)
- **qwen2.5-coder-0.5b removed** from lineup, GGUF deleted, all showcase references purged

## [0.2.2] - 2026-03-04

### Added
- **Session summary output** — `powerglide run` now emits a structured completion block showing steps taken, elapsed time, agent/model name, and `<POWERGLIDE_DONE>` or `<POWERGLIDE_ERROR>` terminal signal
- **igllama port scanning** — `powerglide doctor` scans `:8090–8099` instead of hardcoded `:8090`; reports all running igllama instances
- **`json_mode` on `OpenAIClient`** — sets `response_format: {"type":"json_object"}` for constrained JSON generation on igllama and other local endpoints
- **Showcase page** — `website/content/showcase.smd` with 4 case studies: codebase exploration (0.8B), targeted query (4B), tool calling triage + json_mode, session summary output; performance table; dogfooding verdict
- **Showcase nav link** — added to both `page.shtml` and `home.shtml` nav bars with amber highlight
- **Tests badge** in README (195/195)

### Fixed
- **`Loop step count increments` test** — now uses `/tmp/test_loop_step_count.json` instead of default `.powerglide/session.json`; previously picked up real session state from dogfooding runs and failed
- **README** — updated to v0.2.2 with local LLM section, session summary example, igllama integration, Showcase link, and tests badge

## [0.2.1] - 2026-03-04

### Added
- **SSE parser tests** — 8 tests covering `SseParser`: text_delta, DONE event, multi-event feeds, CRLF handling, non-data line filtering
- **HTTP response tests** — 5 tests for `Response.isSuccess()` and `deinit`
- **Persistence tests** — 5 tests for `PersistenceManager`: init, path generation, save/load roundtrip
- **Root module coverage** — added `stream`, `http`, `anthropic_mod`, `openai_mod`, `mcp_tool_bridge`, `monitor`, `worker`, `terminal_session`, `terminal_pool`, `terminal_exit_code` to `root.zig` so `refAllDecls` catches them

### Fixed
- **Pre-existing bugs uncovered by expanded coverage**:
  - `stream.zig`: `deinit()` and `appendSlice()` missing allocator args (Zig 0.15.2 unmanaged ArrayList)
  - `terminal/pool.zig`: `sessions.size` → `sessions.count()`, stray orphaned test code, `const pool` → `var pool` for mutable methods
  - `terminal/session.zig`: `["/bin/sh", "-c"]` array literal syntax, stray orphaned test code, `const session` → `var session`
  - `models/stream.zig`: `SseParser.init` unused allocator parameter

## [0.2.0] - 2026-03-04

### Added
- **MCP Server** (`src/mcp/server.zig`) — JSON-RPC 2.0 over stdin/stdout; exposes all registered powerglide tools to any MCP-compatible client via `powerglide mcp`.
- **MCP Client** (`src/mcp/client.zig`) — connects to external MCP servers as subprocesses, transparently registering their tools into the powerglide registry.
- **Tool Bridge** (`src/mcp/tool_bridge.zig`) — converts `McpTool` descriptors to powerglide `Tool` structs with prefixed names (`mcp_{server}_{tool}`).
- **`mcp_servers` config array** — configure external MCP server connections in `~/.config/powerglide/config.json`.
- **`powerglide mcp` CLI command** — starts powerglide in MCP server mode.

### Fixed
- **stdin API for Zig 0.15.2** — replaced `std.fs.File.stdin().reader()` (requires buffer arg) with `posix.read()` byte-by-byte pattern.
- **Removed docs/archive from git** — conversation logs untracked to reduce repo noise.
- **Favicon 404** — `docs/favicon.svg` was missing from deployed GitHub Pages site.
- **Homepage title redundancy** — removed duplicate "powerglide" text before hero SVG on index page.

## [0.1.3] - 2026-03-04

### Added
- **Technical Technical Diagrams**: Extracted high-quality SVGs (Ralph Loop, Module Structure, Swarm Architecture) from the Zine website and embedded them directly into `README.md` and `AGENTS.md`.
- **Favicon Support**: Generated a high-quality SVG favicon from the logo and integrated it across all documentation layouts.
- **Integration Tests**: Added `test/integration/cli_test.zig` to automate verification of core CLI subcommands (`version`, `help`, `doctor`, `config`, `tools`).
- **E2E Workflow Script**: Created `test/e2e/workflow.sh` for full-lifecycle verification of the harness.
- **Documentation Archive**: Created `docs/archive/` and `docs/context/` to manage historical logs and project-planning artifacts.

### Changed
- **Velocity Model Overhaul**: Refactored the execution engine to use a **floating-point velocity multiplier** (`delay = 1000 / velocity`) instead of fixed milliseconds. This applies to the Ralph Loop, global Config, and individual Workers.
- **Documentation Refresh**: Rewrote `README.md` and `AGENTS.md` to reflect the supercar-grade technical vision, including the recovery of Barvis context and Rae Sremmurd references.
- **Zig 0.15.2 Patterns**: Standardized `ArrayList` and `HashMap` usage across the codebase to use **unmanaged** patterns, ensuring explicit memory control.
- **Homepage Polish**: Removed redundant titles from the website homepage to prioritize the hero logo and descriptive technical prose.

### Fixed
- **Use-After-Free**: Resolved a critical memory bug in `src/tools/tool.zig` where the `bash` tool was accessing freed output buffers.
- **Memory Leaks**: Fixed leaks in `src/tools/registry.zig` tests where tool output content was not properly deinited.
- **Path Resolution**: Fixed issues with session file persistence in subdirectories.

## [0.1.1] - 2026-03-04

### Added
- Zine-based SSG documentation website under `website/`.
- Deployment automation for GitHub Pages.

## [0.1.0] - 2026-03-02

### Added
- Initial scaffolding of the powerglide multi-agent harness in Zig 0.15.2.
- Ralph Loop 11-state machine implementation.
- Multi-model routing for Anthropic and OpenAI.
- PTY-based tool execution with reliable exit code capture.
- Basic `vxfw` TUI dashboard.
