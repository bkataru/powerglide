//! powerglide - CLI coding agent that slides
//! By convention, root.zig is the root source file when making a library.

const std = @import("std");

// Re-export all public modules
pub const agent = @import("agent/loop.zig");
pub const agent_session = @import("agent/session.zig");
pub const persistence = @import("agent/persistence.zig");
pub const agent_manager = @import("agent/manager.zig");
pub const terminal = @import("terminal/pty.zig");
pub const models = @import("models/router.zig");
pub const stream = @import("models/stream.zig");
pub const http = @import("models/http.zig");
pub const anthropic_mod = @import("models/anthropic.zig");
pub const openai_mod = @import("models/openai.zig");
pub const mcp_tool_bridge = @import("mcp/tool_bridge.zig");
pub const monitor = @import("orchestrator/monitor.zig");
pub const worker = @import("orchestrator/worker.zig");
pub const terminal_session = @import("terminal/session.zig");
pub const terminal_pool = @import("terminal/pool.zig");
pub const terminal_exit_code = @import("terminal/exit_code.zig");
pub const memory = @import("memory/store.zig");
pub const memory_context = @import("memory/context.zig");
pub const config = @import("config/config.zig");
pub const mcp = @import("mcp/client.zig");
pub const mcp_server = @import("mcp/server.zig");
pub const tools = @import("tools/tool.zig");
pub const registry = @import("tools/registry.zig");
pub const tui = @import("tui/app.zig");
pub const orchestrator = @import("orchestrator/swarm.zig");
pub const swarm_manager = @import("orchestrator/swarm_manager.zig");
test {
    std.testing.refAllDecls(@This());
}

pub fn bufferedPrint() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});
    try stdout.flush();
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
