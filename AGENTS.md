# AGENTS.md — Guide for AI Agents Working on powerglide

## Overview

powerglide is a CLI coding agent written in Zig 0.15.2. It orchestrates swarms of SWE (Software Engineering) agents with:

- Configurable velocity (response speed)
- Reliable exit-code capture
- Fault-tolerant state machines
- Multi-model support (Anthropic, OpenAI, OpenAI-compatible)

## Build Commands

```bash
# Build the project
zig build

# Run with arguments
zig build run -- --help
zig build run -- --version

# Run tests
zig build test
```

## Module Structure

### Core Modules

| Module | Purpose |
|--------|---------|
| `src/main.zig` | Entry point, CLI argument parsing |
| `src/agent/loop.zig` | Ralph loop state machine |
| `src/terminal/pty.zig` | PTY management for interactive sessions |
| `src/models/router.zig` | Multi-model routing |

### Key Interfaces

#### LoopState (src/agent/loop.zig)

```zig
pub const LoopState = enum {
    idle,
    thinking,
    acting,
    observing,
    finished,
    failed,
};
```

The Ralph loop cycles through states: idle → thinking → acting → observing → (repeat or finish)

#### ModelProvider (src/models/router.zig)

```zig
pub const ModelProvider = enum {
    anthropic,
    openai,
    openai_compatible,
};
```

#### Tool (src/tools/tool.zig)

```zig
pub const Tool = struct {
    name: []const u8,
    description: []const u8,
    parameters: ?[]const u8 = null,
};
```

#### ToolResult (src/tools/tool.zig)

```zig
pub const ToolResult = struct {
    success: bool,
    output: []const u8,
    err: ?[]const u8 = null,
};
```

## Testing

All modules should have placeholder tests:

```zig
test "placeholder" {
    try std.testing.expect(true);
}
```

Run all tests with `zig build test`.

## Adding New Modules

1. Create the module file in the appropriate `src/` subdirectory
2. Export the module from `src/root.zig` using `@import()`
3. Add a test block to verify compilation
4. Update this file if adding significant new functionality

## Zig 0.15.2 Compatibility Notes

- `error` is a reserved keyword — use `failed`, `err`, or `failed_state` instead
- Use `std.heap.ArenaAllocator` for temporary allocations
- Use `std.process.argsAlloc()` for command-line arguments
- Reader/Writer API uses `std.io.AnyReader` / `std.io.AnyWriter`

## Architecture Vision

The ultimate goal is a production-ready CLI coding agent that can:

1. Accept high-level tasks from the user
2. Break down tasks into subtasks
3. Orchestrate multiple agents to work in parallel
4. Capture and report exit codes reliably
5. Maintain context across sessions
6. Support multiple LLM providers
7. Provide both CLI and TUI interfaces

This is inspired by projects like:
- [oh-my-pi](https://github.com/oh-my-pi)
- [forge code](https://github.com/forgeai/forge-code)
- [Claude Code](https://github.com/anthropics/claude-code)

## Performance Considerations

- Use `ArenaAllocator` to reduce allocation overhead
- Pool terminal resources with `TerminalPool`
- Configure velocity to balance responsiveness vs. API rate limits
- Consider streaming responses for long outputs

## Debugging Tips

- Use `std.debug.print()` for simple output
- Use `try` for error propagation
- Check `zig build` for compilation errors
- Use `zig build test` to verify changes