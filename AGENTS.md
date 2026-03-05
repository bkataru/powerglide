# powerglide Agent Protocol & Integration Guide

## Overview

**powerglide** is designed to be both a standalone CLI tool and a high-performance substrate for other agents (like Claude Code, oh-my-opencode, etc.) to build upon. This guide details the Ralph Loop protocol, PTY management, and how to integrate with powerglide programmatically.

## The Ralph Loop Protocol

Every session follows an explicit 11-state transition model. Agents MUST NOT skip states or exit implicitly.

![Ralph Loop](docs/svg/ralph-loop.svg)

| State | Purpose | Transition Signal |
|-------|---------|-------------------|
| `idle` | Waiting for initialization | Start session |
| `load_tasks` | Fetching from `task-queue.json` | Queue not empty |
| `pick_task` | Selecting highest priority task | Task assigned |
| `thinking` | LLM cognition / completion | LLM response received |
| `tool_call` | Parsing tool use blocks | Tools ready |
| `executing` | Subprocess in isolated PTY | Tool finished |
| `observing` | Result aggregation / analysis | Next action decided |
| `verify` | Running automated checks | Success/Failure |
| `commit` | State persistence | Task status updated |
| `done` | Clean termination | `<POWERGLIDE_DONE>` |
| `failed` | Unrecoverable error | `<POWERGLIDE_ERROR>` |

### Termination Signals

- **Success**: The session MUST output `<POWERGLIDE_DONE>` to stdout upon completion of all tasks.
- **Failure**: The session MUST output `<POWERGLIDE_ERROR>` followed by a diagnostic message.

## Velocity Control

Velocity is a floating-point multiplier (f64) on a 1000ms base delay.

- Formula: `delay_ms = 1000 / velocity`
- Default: `1.0` (1000ms)
- Speeding up: `2.0` (500ms), `4.0` (250ms)
- Slowing down: `0.5` (2000ms), `0.25` (4000ms)

CLI flags: `--velocity` accepts floating-point values.

Agents can self-throttle via CLI flag or config:
`powerglide run --velocity 0.5 "task"` or set `velocity` in `~/.config/powerglide/config.json`

## Reliable PTY Execution

powerglide runs all tools in a pseudoterminal (PTY). This ensures:
1. **Interactive behavior**: Tools like `git` or `npm` behave as if they are in a real terminal.
2. **ANSI colors**: preserved in logs.
3. **Exit Code capture**: Reliability via `waitpid` with `WNOHANG` polling and `/proc/<pid>/status` fallback.

When building tools for powerglide, assume a standard POSIX environment.

## Module Architecture

![Module Structure](docs/svg/module-structure.svg)

## MCP Integration

powerglide implements the [Model Context Protocol](https://modelcontextprotocol.io/) (JSON-RPC 2.0) over stdin/stdout in both directions.

### Using powerglide as an MCP Server

```bash
powerglide mcp
```

The server exposes all registered tools. Protocol handshake:
1. Send `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"my-client","version":"1.0"}}}`
2. Server responds with `protocolVersion`, `capabilities.tools`, and `serverInfo`
3. Send `{"jsonrpc":"2.0","id":2,"method":"tools/list"}` to enumerate tools
4. Send `{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"bash","arguments":{"command":"ls"}}}` to execute

### Connecting powerglide to External MCP Servers

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

External tools register as `mcp_filesystem_<tool_name>` and are callable through the standard tool dispatch path — indistinguishable from built-in tools to the Ralph Loop.

## Integration Examples

### Spawning from another Agent

```bash
# Launch powerglide in background
powerglide run --agent hephaestus --velocity 2.0 "refactor src/main.zig" > session.log 2>&1 &
PID=$!

# Monitor progress
tail -f session.log | grep --line-buffered "Ralph Loop State"
```

### Checking Heartbeats

Workers write a timestamp to `~/.powerglide/workers/<id>/heartbeat` every 30 seconds. If the timestamp is older than 60 seconds, the worker is considered "stale" and should be SIGKILLed.

---

*Named after the Lamborghini Powerglide transmission — built for maximum throughput. 🦀⚡*
