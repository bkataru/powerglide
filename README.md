# powerglide

**The CLI coding agent that slides**

[![build](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/bkataru/powerglide)
[![license](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

<p align="center">
  <img src=".github/logo.png" alt="powerglide logo" width="400">
</p>

powerglide is a multi-agent CLI coding harness inspired by [oh-my-pi](https://github.com/ohmy pi) and [forge code](https://github.com/forgeai/forge-code). It orchestrates swarms of SWE agents with configurable velocity, reliable exit-code capture, fault-tolerant state machines, and multi-model support.

Like a finely tuned engine, powerglide slides through your codebase with precision and grace.

## Key Features

- **Multi-Agent Orchestration** — Coordinate multiple SWE agents working in parallel
- **Velocity Control** — Tune agent response speed with configurable delays
- **Multi-Model Support** — Switch between Anthropic, OpenAI, and OpenAI-compatible providers
- **Fault-Tolerant State Machines** — Resilient agent loops that recover from failures
- **Reliable Exit-Code Capture** — Properly capture and propagate subprocess exit codes
- **PTY Management** — Full terminal emulation for interactive agent sessions
- **Terminal Pooling** — Efficient resource management for multiple terminal sessions

## Quick Start

```bash
# Build the project
zig build

# Run with help
zig build run -- --help

# Run with version
zig build run -- --version

# Run tests
zig build test
```

## Architecture

### The Ralph Loop

At the heart of powerglide is the **Ralph Loop** — a state machine that drives agent behavior:

```
idle → thinking → acting → observing → (repeat or finish)
```

Each iteration represents one thinking-acting-observing cycle, with configurable velocity (delay between iterations).

### Module Structure

```
src/
├── main.zig              # Entry point and CLI dispatch
├── agent/
│   ├── loop.zig          # Ralph loop state machine
│   └── session.zig       # Session management
├── terminal/
│   ├── pty.zig           # PTY management
│   ├── exit_code.zig     # Exit code capture
│   ├── session.zig       # Terminal session CRUD
│   └── pool.zig          # Multi-terminal pool
├── models/
│   ├── http.zig          # HTTP client
│   ├── anthropic.zig     # Anthropic API
│   ├── openai.zig        # OpenAI-compatible API
│   ├── router.zig        # Multi-model router
│   └── stream.zig        # SSE streaming
├── memory/
│   ├── store.zig         # Memory store
│   └── context.zig       # Context management
├── config/
│   └── config.zig        # Configuration
├── tools/
│   ├── tool.zig          # Tool interface
│   └── registry.zig      # Tool registry
├── tui/
│   └── app.zig           # TUI app
└── orchestrator/
    ├── worker.zig        # Worker agent
    ├── monitor.zig       # Monitor
    └── swarm.zig         # Swarm coordinator
```

## Configuration

powerglide can be configured via environment variables:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
```

Or programmatically through the `Config` struct.

## Documentation

For more details, see:

- [CLAUDE.md](CLAUDE.md) — Guide for Claude Code
- [AGENTS.md](AGENTS.md) — Guide for AI agents

## License

MIT License — see [LICENSE](LICENSE) for details.

---

Built with 🔥 and precision in Zig 0.15.2