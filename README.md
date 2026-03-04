<div align="center">

<img src="docs/svg/hero-logo.svg" alt="powerglide logo" width="200" height="200" />

**The CLI coding agent that slides**

[![Zig](https://img.shields.io/badge/Zig-0.15.2-F7A41D?logo=zig&logoColor=white)](https://ziglang.org/)
[![Build](https://github.com/bkataru/powerglide/actions/workflows/ci.yml/badge.svg)](https://github.com/bkataru/powerglide/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/badge/tests-195%2F195-brightgreen)](https://github.com/bkataru/powerglide)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/bkataru/powerglide?style=social)](https://github.com/bkataru/powerglide)

*Zig-powered multi-agent harness for extreme coding workflows. Named after the [Rae Sremmurd](https://www.youtube.com/watch?v=gX2lNOZRSuk) track and its namesake Lamborghini transmission. Built for [Barvis](https://www.moltbook.com/u/barvis_da_jarvis) 🦀⚡*

</div>

---

## What is powerglide?

Like a finely tuned transmission at full throttle, **powerglide** swerves through your codebase with precision, force, and grace. It is the layer between you and a swarm of LLM-driven engineers working in parallel — written in [Zig 0.15.2](https://ziglang.org/), compiled to a single static binary with zero runtime dependencies, and built around one non-negotiable constraint: the agent loop must be reliable enough to run unattended.

The foundation is the **Ralph Loop** — an explicit 11-state machine that sequences every agent action from task intake through tool execution to verified completion. No implicit flow, no silent exits. Every session terminates with `<POWERGLIDE_DONE>` or `<POWERGLIDE_ERROR>`. The loop drives the model; the model does not drive the loop.

```bash
$ powerglide run --agent hephaestus --velocity 2.0 "refactor the auth module to use the new session manager"
```

---

## Core Pillars

- **The Ralph Loop** 🔄 — Explicit 11-state machine: `idle → load_tasks → pick_task → thinking → tool_call → executing → observing → verify → commit → done`. Every step is auditable; every session ends with a deterministic terminal signal.
- **Velocity Control** 🚀 — Precision control over agent throughput. `delay_ms = 1000 / velocity`. Speed up (`--velocity 2.0` = 500ms/step) or slow down (`--velocity 0.5` = 2000ms/step) without restarting the session. Agents can self-throttle mid-run.
- **Reliable PTYs** 💻 — Every tool runs in a real pseudoterminal. Exit codes captured via `waitpid` with WNOHANG polling and a `/proc/<pid>/status` fallback — so `zig build`, `pytest`, and `bash` all deliver trustable results to the VERIFY state.
- **Rogue Agent Prevention** 🛡️ — Step limits, heartbeat monitoring (30s), circuit breakers for repeated tool calls, and budget tracking. Stuck agents are killed before they accumulate diverged work.
- **Multi-Model Routing** 🤖 — Anthropic (Claude), OpenAI, and any OpenAI-compatible endpoint (Ollama, [igllama](https://github.com/bkataru/igllama), NVIDIA NIM, Together AI). Fallback chains keep sessions alive through provider outages.
- **MCP Integration** 🔌 — Run as an MCP server (`powerglide mcp`) or connect to external MCP servers as a client. External tools get prefixed names and become first-class tools in the registry.
- **Local LLM Support** 🏠 — Pre-configured agents (`local`, `local2b`, `local4b`, `local9b`) route to the full Qwen3.5 lineup on `:8090–:8093` via igllama. No API keys required for offline inference.

---

## Architecture

### Module Structure

![Module Structure](docs/svg/module-structure.svg)

### Swarm Architecture

![Swarm Architecture](docs/svg/swarm-arch.svg)

### The Ralph Loop

![Ralph Loop](docs/svg/ralph-loop.svg)

---

## Quick Start

### Prerequisites

- [Zig 0.15.2](https://ziglang.org/download/) — `mise install zig@0.15.2` or official binaries
- An API key for your provider (`ANTHROPIC_API_KEY` or `OPENAI_API_KEY`), **or** run [igllama](https://github.com/bkataru/igllama) locally for a fully offline stack

### Build

```bash
git clone https://github.com/bkataru/powerglide
cd powerglide
zig build
# Binary at ./zig-out/bin/powerglide
```

### Run

```bash
# Verify setup — scans :8090-8099 for local igllama instances
./zig-out/bin/powerglide doctor

# Run a session (cloud)
./zig-out/bin/powerglide run "implement a binary search tree in Zig"

# Run fully locally with Qwen3.5-4B via igllama
igllama api Qwen3.5-4B-Q8_0.gguf --port 8092 --no-think &
./zig-out/bin/powerglide run --agent local4b "describe the orchestrator module"

# Run at double speed
./zig-out/bin/powerglide run --velocity 2.0 "add comprehensive unit tests"

# Open multi-agent TUI dashboard
./zig-out/bin/powerglide tui
```

Every completed session emits a structured summary:

```
─────────────────────────────────────────
  Session complete  [done]
  Steps:    9
  Elapsed:  3.4s
  Agent:    local4b  (Qwen3.5-4B-Q8_0.gguf :8092)
  Signal:   <POWERGLIDE_DONE>
─────────────────────────────────────────
```

---

## CLI Reference

| Command | Purpose |
|---------|---------|
| `run` | Launch a coding agent session |
| `session` | Manage sessions — list, show, resume, delete, export |
| `agent` | Manage agent configs — list, add, remove, show |
| `swarm` | Orchestrate parallel worker swarms |
| `config` | View and modify global configuration |
| `tools` | List and test available tools |
| `mcp` | Start powerglide as an MCP server |
| `tui` | Launch the multi-panel vxfw dashboard |
| `doctor` | Run system health checks |
| `version` | Show version |

---

## MCP Integration

powerglide speaks [Model Context Protocol](https://modelcontextprotocol.io/) natively — as both server and client.

### As an MCP Server

```bash
powerglide mcp
```

Exposes all registered tools via JSON-RPC 2.0 over stdin/stdout. Any MCP-compatible client (Claude Desktop, another powerglide instance) can call powerglide tools.

### As an MCP Client

Add `mcp_servers` to `~/.config/powerglide/config.json`:

```json
{
  "mcp_servers": [
    {
      "name": "filesystem",
      "command": ["npx", "-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
    }
  ]
}
```

External tools register as `mcp_filesystem_read_file` etc. and are indistinguishable from built-in tools to the agent loop.

---

## Local LLM Dogfooding

powerglide ships with igllama integration for fully local inference. See the **[Showcase](https://bkataru.github.io/powerglide/showcase/)** for case studies across the full Qwen3.5 lineup — T01–T17 agentic task trials at Q4 and Q8 quantization, quantization sensitivity analysis, tool-call triage, and honest per-model pass-rate tables.

```bash
# Start the full Qwen3.5 lineup (Zig-based local inference via igllama)
igllama api Qwen3.5-0.8B-Q8_0.gguf       --port 8090 --no-think &
igllama api Qwen3.5-2B-Q8_0.gguf         --port 8091 --no-think &
igllama api Qwen3.5-4B-Q8_0.gguf         --port 8092 --no-think &
igllama api Qwen3.5-9B-UD-Q4_K_XL.gguf   --port 8093 --no-think &

# Doctor detects all running instances automatically
powerglide doctor
# OK   igllama: running on :8090 (local   — 0.8B-Q8)
# OK   igllama: running on :8091 (local2b — 2B-Q8)
# OK   igllama: running on :8092 (local4b — 4B-Q8)
# OK   igllama: running on :8093 (local9b — 9B-Q4)

# Run T01-T17 agentic trial harness across all four models
zig build trial

# Run quantization sensitivity trial (Q4/Q5/Q6/Q8 on 2B and 9B)
zig build trial-quant
```

---

## Inspiration

powerglide synthesizes the strongest ideas from the AI coding agent ecosystem:

| Project | What We Took |
|---------|--------------|
| [oh-my-pi](https://github.com/can1357/oh-my-pi) | Multi-agent harness: N workers, one orchestrator, file-based coordination |
| [oh-my-opencode](https://github.com/code-yeongyu/oh-my-opencode) | Autonomous coding agents as invocable CLI subprocesses |
| [ralph](https://github.com/snarktank/ralph) | The Ralph Loop pattern: explicit states, explicit done signal |
| [gastown](https://github.com/steveyegge/gastown) | Per-worker workspace isolation, no write conflicts |
| [opencode](https://github.com/anomalyco/opencode) | CLI structure and multi-model routing with fallback chains |
| [loki](https://github.com/Dark-Alex-17/loki) | Tool registry, provider abstraction, session persistence |
| [plandex](https://github.com/plandex-ai/plandex) | Plan+execute pattern, diff-based application |
| [goose](https://github.com/block/goose) | MCP integration, agent extensibility |
| [crush](https://github.com/charmbracelet/crush) | Terminal UX sensibility, vxfw-based TUI |
| [mem0](https://github.com/mem0ai/mem0) | Persistent memory layer design |
| [igllama](https://github.com/bkataru/igllama) | Local GGUF inference, OpenAI-compatible API for Qwen3.5 |

---

## Documentation

Full docs at **[bkataru.github.io/powerglide](https://bkataru.github.io/powerglide)** — including [Architecture](https://bkataru.github.io/powerglide/architecture/), [CLI Reference](https://bkataru.github.io/powerglide/cli-reference/), [Configuration](https://bkataru.github.io/powerglide/configuration/), and the [Showcase](https://bkataru.github.io/powerglide/showcase/).

For AI agents working with powerglide programmatically, see [AGENTS.md](AGENTS.md).

## License

MIT © [bkataru](https://github.com/bkataru)
