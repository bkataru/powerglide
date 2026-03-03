const std = @import("std");
// const clap = @import("clap");
const clap = @import("clap");
const pg_lib = @import("powerglide");
const tui_app = pg_lib.tui;

const VERSION = "0.1.0";
const ConfigDir = ".config/powerglide";

/// Main entry point
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Skip program name
    if (args.len < 2) {
        try printMainHelp(std.fs.File.stdout().deprecatedWriter());
        return;
    }

    const top_level = args[1];

    // Handle top-level --help and --version
    if (std.mem.eql(u8, top_level, "--help") or std.mem.eql(u8, top_level, "-h")) {
        try printMainHelp(std.fs.File.stdout().deprecatedWriter());
        return;
    }

    if (std.mem.eql(u8, top_level, "--version") or std.mem.eql(u8, top_level, "-v")) {
        try std.fs.File.stdout().deprecatedWriter().print("powerglide {s}\n", .{VERSION});
        return;
    }

    // Handle subcommands
    if (std.mem.eql(u8, top_level, "help")) {
        if (args.len > 2) {
            try printCommandHelp(args[2], std.fs.File.stdout().deprecatedWriter());
        } else {
            try printMainHelp(std.fs.File.stdout().deprecatedWriter());
        }
        return;
    }

    if (std.mem.eql(u8, top_level, "version")) {
        try std.fs.File.stdout().deprecatedWriter().print("powerglide {s}\n", .{VERSION});
        return;
    }

    if (std.mem.eql(u8, top_level, "doctor")) {
        try runDoctor(allocator);
        return;
    }

    if (std.mem.eql(u8, top_level, "run")) {
        try handleRun(allocator, args[2..]);
        return;
    }

    if (std.mem.eql(u8, top_level, "agent")) {
        try handleAgent(allocator, args[2..]);
        return;
    }

    if (std.mem.eql(u8, top_level, "session")) {
        try handleSession(allocator, args[2..]);
        return;
    }

    if (std.mem.eql(u8, top_level, "swarm")) {
        try handleSwarm(allocator, args[2..]);
        return;
    }

    if (std.mem.eql(u8, top_level, "config")) {
        try handleConfig(allocator, args[2..]);
        return;
    }

    if (std.mem.eql(u8, top_level, "tools")) {
        try handleTools(allocator, args[2..]);
        return;
    }

    if (std.mem.eql(u8, top_level, "tui")) {
        // Require a real TTY before launching vxfw (avoids Unexpected errno in non-TTY env)
        if (!std.posix.isatty(std.posix.STDIN_FILENO)) {
            try std.fs.File.stderr().deprecatedWriter().writeAll(
                "powerglide tui: requires an interactive terminal (TTY)\n" ++
                "  Run powerglide in an interactive shell to use the TUI dashboard.\n"
            );
            std.process.exit(1);
        }
        var app = tui_app.TUIApp.init(allocator);
        defer app.deinit();
        try app.start();
        return;
    }

    // Unknown command
    try std.fs.File.stdout().deprecatedWriter().print("powerglide: unknown command '{s}'\n", .{top_level});
    try printMainHelp(std.fs.File.stdout().deprecatedWriter());
    std.process.exit(1);
}

/// Print main help message
fn printMainHelp(writer: anytype) !void {
    try writer.writeAll(
        \\powerglide 0.1.0 — the CLI coding agent that slides
        \\
        \\USAGE:
        \\ powerglide [OPTIONS] [COMMAND]
        \\
        \\COMMANDS:
        \\ run [OPTIONS] <message> Run a coding agent session
        \\ agent <subcommand> Manage agent configurations
        \\ session <subcommand> Manage sessions (list/resume/delete)
        \\ swarm <subcommand> Manage agent swarms
        \\ config <subcommand> Manage configuration
        \\ tools <subcommand> List and test tools
        \\ tui Open the interactive multi-agent dashboard
        \\ doctor Check system health and configuration
        \\ version Print version information
        \\ help [COMMAND] Show help for a command
        \\
        \\OPTIONS:
        \\ -h, --help Show this help message
        \\ --version Show version
        \\
        \\EXAMPLES:
        \\ powerglide run "Fix the bug in auth.zig"
        \\ powerglide run --agent hephaestus --velocity 1000 "Add unit tests"
        \\ powerglide session list
        \\ powerglide session resume ses_abc123 "Continue adding tests"
        \\ powerglide doctor
        \\ powerglide config get velocity_ms
        \\ powerglide config set velocity_ms 500
        \\
        \\CONFIG:
        \\ Configuration is read from ~/.config/powerglide/config.json
        \\ Environment variables: ANTHROPIC_API_KEY, OPENAI_API_KEY
        \\
        \\DOCUMENTATION:
        \\ https://github.com/bkataru/powerglide
        \\
    );
}

/// Print help for a specific command
fn printCommandHelp(cmd: []const u8, writer: anytype) !void {
    if (std.mem.eql(u8, cmd, "run")) {
        try writer.writeAll(
            \\powerglide-run — Run a coding agent session
            \\
            \\USAGE:
            \\ powerglide run [OPTIONS] <message>
            \\
            \\DESCRIPTION:
            \\ Starts an interactive agent session with the provided message.
            \\ The agent will analyze your codebase and perform the requested task.
            \\
            \\OPTIONS:
            \\ -h, --help Show this help message
            \\ -a, --agent <name> Agent name to use (default: hephaestus)
            \\ -v, --velocity <ms> Velocity in milliseconds (default: 500)
            \\ -s, --session-id <id> Continue existing session
            \\ -m, --model <provider/model> Model to use (default: anthropic/claude-3-5-sonnet-20241022)
            \\
            \\EXAMPLES:
            \\ powerglide run "Fix the bug in auth.zig"
            \\ powerglide run --agent hephaestus --velocity 1000 "Add unit tests"
            \\ powerglide run --session-id ses_abc123 "Continue working"
            \\ powerglide run -m openai/gpt-4 "Use a different model"
            \\
        );
    } else if (std.mem.eql(u8, cmd, "agent")) {
        try writer.writeAll(
            \\powerglide-agent — Manage agent configurations
            \\
            \\USAGE:
            \\ powerglide agent <subcommand>
            \\
            \\SUBCOMMANDS:
            \\ list List all available agents
            \\ show <name> Show agent configuration
            \\ add <name> Add a new agent configuration
            \\ remove <name> Remove an agent configuration
            \\ set-default <name> Set default agent
            \\
            \\EXAMPLES:
            \\ powerglide agent list
            \\ powerglide agent show hephaestus
            \\ powerglide agent set-default hephaestus
            \\
        );
    } else if (std.mem.eql(u8, cmd, "session")) {
        try writer.writeAll(
            \\powerglide-session — Manage sessions
            \\
            \\USAGE:
            \\ powerglide session <subcommand>
            \\
            \\SUBCOMMANDS:
            \\ list List all sessions
            \\ show <id> Show session details
            \\ resume <id> [message] Resume a session with optional message
            \\ delete <id> Delete a session
            \\ export <id> Export session as JSON
            \\
            \\EXAMPLES:
            \\ powerglide session list
            \\ powerglide session resume ses_abc123
            \\ powerglide session resume ses_abc123 "Continue adding tests"
            \\ powerglide session delete ses_abc123
            \\
        );
    } else if (std.mem.eql(u8, cmd, "swarm")) {
        try writer.writeAll(
            \\powerglide-swarm — Manage agent swarms
            \\
            \\USAGE:
            \\ powerglide swarm <subcommand>
            \\
            \\SUBCOMMANDS:
            \\ list List all swarms
            \\ create <name> Create a new swarm
            \\ add <swarm> <agent> Add agent to swarm
            \\ remove <swarm> <agent> Remove agent from swarm
            \\ run <swarm> <message> Run a swarm session
            \\ delete <swarm> Delete a swarm
            \\
            \\EXAMPLES:
            \\ powerglide swarm list
            \\ powerglide swarm create my-swarm
            \\ powerglide swarm add my-swarm hephaestus
            \\ powerglide swarm run my-swarm "Fix all bugs"
            \\
        );
    } else if (std.mem.eql(u8, cmd, "config")) {
        try writer.writeAll(
            \\powerglide-config — Manage configuration
            \\
            \\USAGE:
            \\ powerglide config <subcommand>
            \\
            \\SUBCOMMANDS:
            \\ get <key> Get configuration value
            \\ set <key> <value> Set configuration value
            \\ list List all configuration
            \\ edit Edit configuration file
            \\ init Initialize default config
            \\
            \\CONFIG KEYS:
            \\ velocity_ms Agent response delay in milliseconds
            \\ default_agent Default agent name
            \\ default_model Default model (provider/model)
            \\ api_timeout API request timeout in seconds
            \\
            \\EXAMPLES:
            \\ powerglide config get velocity_ms
            \\ powerglide config set velocity_ms 500
            \\ powerglide config list
            \\
            \\CONFIG FILE:
            \\ ~/.config/powerglide/config.json
            \\
        );
    } else if (std.mem.eql(u8, cmd, "tools")) {
        try writer.writeAll(
            \\powerglide-tools — List and test tools
            \\
            \\USAGE:
            \\ powerglide tools <subcommand>
            \\
            \\SUBCOMMANDS:
            \\ list List all available tools
            \\ show <name> Show tool details
            \\ test <name> Test a tool
            \\ register <path> Register tools from path
            \\
            \\EXAMPLES:
            \\ powerglide tools list
            \\ powerglide tools show grep
            \\ powerglide tools test grep
            \\
        );
    } else if (std.mem.eql(u8, cmd, "doctor")) {
        try writer.writeAll(
            \\powerglide-doctor — Check system health
            \\
            \\USAGE:
            \\ powerglide doctor
            \\
            \\DESCRIPTION:
            \\ Checks system requirements and configuration:
            \\ - Zig compiler (0.15.2+)
            \\ - oh-my-opencode (optional)
            \\ - Git availability
            \\ - API key configuration
            \\ - Config directory
            \\
        );
    } else {
        try writer.print("Unknown command: {s}\n", .{cmd});
        std.process.exit(1);
    }
}

/// Handle the 'run' command
fn handleRun(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    var agent_name: ?[]const u8 = null;
    var velocity: ?u32 = null;
    var session_id: ?[]const u8 = null;
    var model: ?[]const u8 = null;
    var message: ?[]const u8 = null;
    var show_help = false;

    var i: usize = 0;
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            show_help = true;
            break;
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--agent")) {
            if (i + 1 < args.len) {
                agent_name = args[i + 1];
                i += 2;
            } else {
                try std.fs.File.stderr().deprecatedWriter().print("powerglide run: error: --agent requires a value\n", .{});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--velocity")) {
            if (i + 1 < args.len) {
                velocity = std.fmt.parseInt(u32, args[i + 1], 10) catch {
                    try std.fs.File.stderr().deprecatedWriter().print("powerglide run: error: invalid velocity value\n", .{});
                    std.process.exit(1);
                };
                i += 2;
            } else {
                try std.fs.File.stderr().deprecatedWriter().print("powerglide run: error: --velocity requires a value\n", .{});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--session-id")) {
            if (i + 1 < args.len) {
                session_id = args[i + 1];
                i += 2;
            } else {
                try std.fs.File.stderr().deprecatedWriter().print("powerglide run: error: --session-id requires a value\n", .{});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--model")) {
            if (i + 1 < args.len) {
                model = args[i + 1];
                i += 2;
            } else {
                try std.fs.File.stderr().deprecatedWriter().print("powerglide run: error: --model requires a value\n", .{});
                std.process.exit(1);
            }
        } else {
            message = arg;
            break;
        }
    }

    if (show_help) {
        try printCommandHelp("run", std.fs.File.stdout().deprecatedWriter());
        return;
    }

    const powerglide = @import("powerglide");

    // Load agent manager and get the agent
    var agent_manager = try powerglide.agent_manager.AgentManager.init(allocator);
    defer agent_manager.deinit();
    agent_manager.load() catch {};

    const resolved_agent_name = agent_name orelse agent_manager.getDefaultAgent();
    const agent = agent_manager.getAgent(resolved_agent_name);

    // Load config
    const config = try powerglide.config.load(allocator);
    defer config.deinit(allocator);

    // Create session
    const session_identifier = session_id orelse "default";
    var session = try powerglide.agent_session.Session.init(allocator, session_identifier);
    defer session.deinit(allocator);

    // Add initial task from message
    if (message) |msg| {
        try session.addTask(allocator, .{
            .id = "task-1",
            .description = msg,
            .priority = 1,
        });
    }

    // Setup loop configuration
    const loop_config = powerglide.agent.LoopConfig{
        .max_steps = config.max_steps,
        .velocity_ms = velocity orelse (if (agent) |a| a.velocity else config.velocity_ms),
        .model = model orelse (if (agent) |a| a.model else config.model),
    };

    // Initialize and run the loop
    var loop = powerglide.agent.Loop.init(allocator, loop_config);
    defer loop.deinit();

    std.debug.print("Starting powerglide session\n", .{});
    std.debug.print("  Agent: {s}\n", .{resolved_agent_name});
    std.debug.print("  Model: {s}\n", .{loop_config.model});
    std.debug.print("  Velocity: {d}ms\n", .{loop_config.velocity_ms});
    if (message) |msg| {
        std.debug.print("  Task: {s}\n", .{msg});
    }

    // Run the loop (this would normally be async in production)
    try loop.run();
}

/// Handle the 'agent' subcommand
fn handleAgent(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    if (args.len == 0) {
        try printCommandHelp("agent", std.fs.File.stdout().deprecatedWriter());
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "--help") or std.mem.eql(u8, subcommand, "-h")) {
        try printCommandHelp("agent", std.fs.File.stdout().deprecatedWriter());
        return;
    }

    const powerglide = @import("powerglide");
    var manager = try powerglide.agent_manager.AgentManager.init(allocator);
    defer manager.deinit();

    // Load existing agents
    manager.load() catch |err| {
        if (err != error.FileNotFound) {
            try std.fs.File.stderr().deprecatedWriter().print("Warning: Failed to load agents: {}\n", .{err});
        }
    };

    if (std.mem.eql(u8, subcommand, "list")) {
        try std.fs.File.stdout().deprecatedWriter().writeAll("Available agents:\n");
        var it = manager.listAgents();
        while (it.next()) |entry| {
            const agent = entry.value_ptr.*;
            const is_default = if (manager.default_agent) |def| 
                std.mem.eql(u8, agent.name, def) else 
                std.mem.eql(u8, agent.name, "hephaestus");
            try std.fs.File.stdout().deprecatedWriter().print("  {s} - {s} ({s}){s}\n", .{
                agent.name,
                agent.role,
                agent.model,
                if (is_default) " (default)" else "",
            });
        }
    } else if (std.mem.eql(u8, subcommand, "show")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide agent: error: 'show' requires an agent name\n", .{});
            std.process.exit(1);
        }
        const agent = manager.getAgent(args[1]);
        if (agent == null) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide agent: agent '{s}' not found\n", .{args[1]});
            std.process.exit(1);
        }
        const a = agent.?;
        try std.fs.File.stdout().deprecatedWriter().print(
            "Agent: {s}\n  Model: {s}\n  Role: {s}\n  Velocity: {d}ms\n  Instructions: {s}\n",
            .{ a.name, a.model, a.role, a.velocity, a.instructions },
        );
    } else if (std.mem.eql(u8, subcommand, "add")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide agent: error: 'add' requires an agent name\n", .{});
            std.process.exit(1);
        }
        // For now, create a basic agent with defaults
        try manager.addAgent(.{
            .name = args[1],
            .model = "claude-opus-4-6",
            .role = "coding",
            .instructions = "",
            .velocity = 500,
        });
        try manager.save();
        try std.fs.File.stdout().deprecatedWriter().print("Added agent '{s}'\n", .{args[1]});
    } else if (std.mem.eql(u8, subcommand, "remove")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide agent: error: 'remove' requires an agent name\n", .{});
            std.process.exit(1);
        }
        try manager.removeAgent(args[1]);
        try manager.save();
        try std.fs.File.stdout().deprecatedWriter().print("Removed agent '{s}'\n", .{args[1]});
    } else if (std.mem.eql(u8, subcommand, "set-default")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide agent: error: 'set-default' requires an agent name\n", .{});
            std.process.exit(1);
        }
        try manager.setDefaultAgent(args[1]);
        try manager.save();
        try std.fs.File.stdout().deprecatedWriter().print("Set default agent to '{s}'\n", .{args[1]});
    } else {
        try std.fs.File.stderr().deprecatedWriter().print("powerglide agent: unknown subcommand '{s}'\n", .{subcommand});
        try printCommandHelp("agent", std.fs.File.stdout().deprecatedWriter());
        std.process.exit(1);
    }
}

/// Handle the 'session' subcommand
fn handleSession(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    if (args.len == 0) {
        try printCommandHelp("session", std.fs.File.stdout().deprecatedWriter());
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "--help") or std.mem.eql(u8, subcommand, "-h")) {
        try printCommandHelp("session", std.fs.File.stdout().deprecatedWriter());
        return;
    }

    const powerglide = @import("powerglide");
    var manager = powerglide.agent_session.SessionManager.init(allocator);
    defer manager.deinit();

if (std.mem.eql(u8, subcommand, "list")) {
        try std.fs.File.stdout().deprecatedWriter().writeAll(
            \\Sessions:
            \\ (no active sessions)
            \\
            \\Use 'powerglide run' to start a new session.
            \\
        );
    } else if (std.mem.eql(u8, subcommand, "show")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide session: error: 'show' requires a session ID\n", .{});
            std.process.exit(1);
        }
        try std.fs.File.stdout().deprecatedWriter().print("powerglide session show: {s} — stub (not yet implemented)\n", .{args[1]});
    } else if (std.mem.eql(u8, subcommand, "resume")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide session: error: 'resume' requires a session ID\n", .{});
            std.process.exit(1);
        }
        var buf = std.ArrayList(u8){};
        defer buf.deinit(allocator);
        try buf.writer(allocator).print("powerglide session resume: {s}", .{args[1]});
        if (args.len > 2) {
            try buf.writer(allocator).print(" with message: {s}", .{args[2]});
        }
        try buf.writer(allocator).print("\n", .{});
        try std.fs.File.stdout().deprecatedWriter().writeAll(buf.items);
    } else if (std.mem.eql(u8, subcommand, "delete")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide session: error: 'delete' requires a session ID\n", .{});
            std.process.exit(1);
        }
        try std.fs.File.stdout().deprecatedWriter().print("powerglide session delete: {s} — stub (not yet implemented)\n", .{args[1]});
    } else if (std.mem.eql(u8, subcommand, "export")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide session: error: 'export' requires a session ID\n", .{});
            std.process.exit(1);
        }
        try std.fs.File.stdout().deprecatedWriter().print("powerglide session export: {s} — stub (not yet implemented)\n", .{args[1]});
    } else {
        try std.fs.File.stderr().deprecatedWriter().print("powerglide session: unknown subcommand '{s}'\n", .{subcommand});
        try printCommandHelp("session", std.fs.File.stdout().deprecatedWriter());
        std.process.exit(1);
    }
}

/// Handle the 'swarm' subcommand
fn handleSwarm(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    _ = allocator;
    if (args.len == 0) {
        try printCommandHelp("swarm", std.fs.File.stdout().deprecatedWriter());
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "--help") or std.mem.eql(u8, subcommand, "-h")) {
        try printCommandHelp("swarm", std.fs.File.stdout().deprecatedWriter());
        return;
    }

    if (std.mem.eql(u8, subcommand, "list")) {
        try std.fs.File.stdout().deprecatedWriter().writeAll(
            \\Swarms:
            \\ (no active swarms)
            \\
            \\Use 'powerglide swarm create <name>' to create a new swarm.
            \\
        );
    } else if (std.mem.eql(u8, subcommand, "create")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide swarm: error: 'create' requires a swarm name\n", .{});
            std.process.exit(1);
        }
        try std.fs.File.stdout().deprecatedWriter().print("powerglide swarm create: {s} — stub (not yet implemented)\n", .{args[1]});
    } else if (std.mem.eql(u8, subcommand, "add")) {
        if (args.len < 3) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide swarm: error: 'add' requires swarm and agent names\n", .{});
            std.process.exit(1);
        }
        try std.fs.File.stdout().deprecatedWriter().print("powerglide swarm add: {s} {s} — stub (not yet implemented)\n", .{ args[1], args[2] });
    } else if (std.mem.eql(u8, subcommand, "remove")) {
        if (args.len < 3) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide swarm: error: 'remove' requires swarm and agent names\n", .{});
            std.process.exit(1);
        }
        try std.fs.File.stdout().deprecatedWriter().print("powerglide swarm remove: {s} {s} — stub (not yet implemented)\n", .{ args[1], args[2] });
    } else if (std.mem.eql(u8, subcommand, "run")) {
        if (args.len < 3) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide swarm: error: 'run' requires swarm name and message\n", .{});
            std.process.exit(1);
        }
        try std.fs.File.stdout().deprecatedWriter().print("powerglide swarm run: {s} \"{s}\" — stub (not yet implemented)\n", .{ args[1], args[2] });
    } else if (std.mem.eql(u8, subcommand, "delete")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide swarm: error: 'delete' requires a swarm name\n", .{});
            std.process.exit(1);
        }
        try std.fs.File.stdout().deprecatedWriter().print("powerglide swarm delete: {s} — stub (not yet implemented)\n", .{args[1]});
    } else {
        try std.fs.File.stderr().deprecatedWriter().print("powerglide swarm: unknown subcommand '{s}'\n", .{subcommand});
        try printCommandHelp("swarm", std.fs.File.stdout().deprecatedWriter());
        std.process.exit(1);
    }
}

/// Handle the 'config' subcommand
fn handleConfig(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    if (args.len == 0) {
        try printCommandHelp("config", std.fs.File.stdout().deprecatedWriter());
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "--help") or std.mem.eql(u8, subcommand, "-h")) {
        try printCommandHelp("config", std.fs.File.stdout().deprecatedWriter());
        return;
    }

    const powerglide = @import("powerglide");

    if (std.mem.eql(u8, subcommand, "get")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide config: error: 'get' requires a key\n", .{});
            std.process.exit(1);
        }
        const config = try powerglide.config.load(allocator);
        defer config.deinit(allocator);
        
        const value = if (std.mem.eql(u8, args[1], "velocity_ms")) 
            try std.fmt.allocPrint(allocator, "{d}", .{config.velocity_ms})
        else if (std.mem.eql(u8, args[1], "default_agent")) 
            "hephaestus"
        else if (std.mem.eql(u8, args[1], "default_model")) 
            config.model
        else if (std.mem.eql(u8, args[1], "max_steps")) 
            try std.fmt.allocPrint(allocator, "{d}", .{config.max_steps})
        else
            "(not set)";
        
        try std.fs.File.stdout().deprecatedWriter().print("{s} = {s}\n", .{ args[1], value });
    } else if (std.mem.eql(u8, subcommand, "set")) {
        if (args.len < 3) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide config: error: 'set' requires key and value\n", .{});
            std.process.exit(1);
        }
        try std.fs.File.stdout().deprecatedWriter().print("powerglide config set: {s} = {s} (not yet implemented)\n", .{ args[1], args[2] });
    } else if (std.mem.eql(u8, subcommand, "list")) {
        const config = try powerglide.config.load(allocator);
        defer config.deinit(allocator);
        
try std.fs.File.stdout().deprecatedWriter().print(
            "Configuration:\\n velocity_ms: {d}\\n default_agent: hephaestus\\n default_model: {s}\\n max_steps: {d}\\n\\nConfig file: ~/.config/powerglide/config.json\\n\\n",
            .{ config.velocity_ms, config.model, config.max_steps },
        );
    } else if (std.mem.eql(u8, subcommand, "edit")) {
        try std.fs.File.stdout().deprecatedWriter().writeAll("powerglide config edit: stub (not yet implemented)\n");
    } else if (std.mem.eql(u8, subcommand, "init")) {
        try std.fs.File.stdout().deprecatedWriter().writeAll("powerglide config init: stub (not yet implemented)\n");
    } else {
        try std.fs.File.stderr().deprecatedWriter().print("powerglide config: unknown subcommand '{s}'\n", .{subcommand});
        try printCommandHelp("config", std.fs.File.stdout().deprecatedWriter());
        std.process.exit(1);
    }
}

/// Handle the 'tools' subcommand
fn handleTools(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    _ = allocator;
    if (args.len == 0) {
        try printCommandHelp("tools", std.fs.File.stdout().deprecatedWriter());
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "--help") or std.mem.eql(u8, subcommand, "-h")) {
        try printCommandHelp("tools", std.fs.File.stdout().deprecatedWriter());
        return;
    }

    if (std.mem.eql(u8, subcommand, "list")) {
        try std.fs.File.stdout().deprecatedWriter().writeAll(
            \\Available tools:
            \\ grep - Search files for patterns
            \\ read - Read file contents
            \\ write - Write/modify files
            \\ edit - Edit files with precision
            \\ glob - Find files by pattern
            \\ bash - Execute shell commands
            \\ task - Spawn agent tasks
            \\ lsp_* - LSP operations (goto, rename, etc.)
            \\
        );
} else if (std.mem.eql(u8, subcommand, "show")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide tools: error: 'show' requires a tool name\n", .{});
            std.process.exit(1);
        }
        try std.fs.File.stdout().deprecatedWriter().print("powerglide tools show: {s} — stub (not yet implemented)\n", .{args[1]});
    } else if (std.mem.eql(u8, subcommand, "test")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide tools: error: 'test' requires a tool name\n", .{});
            std.process.exit(1);
        }
        try std.fs.File.stdout().deprecatedWriter().print("powerglide tools test: {s} — stub (not yet implemented)\n", .{args[1]});
    } else if (std.mem.eql(u8, subcommand, "register")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide tools: error: 'register' requires a path\n", .{});
            std.process.exit(1);
        }
        try std.fs.File.stdout().deprecatedWriter().print("powerglide tools register: {s} — stub (not yet implemented)\n", .{args[1]});
    } else {
        try std.fs.File.stderr().deprecatedWriter().print("powerglide tools: unknown subcommand '{s}'\n", .{subcommand});
        try printCommandHelp("tools", std.fs.File.stdout().deprecatedWriter());
        std.process.exit(1);
    }
}

/// Run doctor checks
fn runDoctor(allocator: std.mem.Allocator) !void {
    _ = allocator;
    const w = std.fs.File.stdout().deprecatedWriter();
    try w.writeAll("powerglide doctor: running system health checks...\n\n");
    try checkZig(w);
    try checkOhMyOpencode(w);
    try checkGit(w);
    try checkApiKeys(w);
    try checkConfigDir(w);
    try w.writeAll("\nDoctor check complete.\n");
}

fn checkZig(writer: anytype) !void {
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "zig", "version" },
    }) catch {
        try writer.writeAll("FAIL zig: not found\n");
        return;
    };
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);
    if (result.term == .Exited and result.term.Exited == 0) {
        const version = std.mem.trim(u8, result.stdout, " \n\t");
        if (std.mem.indexOf(u8, version, "0.15") != null) {
            try writer.print("OK   zig {s}\n", .{version});
        } else {
            try writer.print("WARN zig {s} (expected 0.15.x)\n", .{version});
        }
    } else {
        try writer.writeAll("FAIL zig: not found or error\n");
    }
}

fn checkOhMyOpencode(writer: anytype) !void {
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "npx", "oh-my-opencode", "--version" },
    }) catch {
        try writer.writeAll("WARN oh-my-opencode: not available\n");
        return;
    };
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);
    if (result.term == .Exited and result.term.Exited == 0) {
        const version = std.mem.trim(u8, result.stdout, " \n\t");
        try writer.print("OK   oh-my-opencode {s}\n", .{version});
    } else {
        try writer.writeAll("WARN oh-my-opencode: not installed\n");
    }
}

fn checkGit(writer: anytype) !void {
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &.{ "git", "--version" },
    }) catch {
        try writer.writeAll("FAIL git: not found\n");
        return;
    };
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);
    if (result.term == .Exited and result.term.Exited == 0) {
        const version = std.mem.trim(u8, result.stdout, " \n\t");
        try writer.print("OK   git: {s}\n", .{version});
    } else {
        try writer.writeAll("FAIL git: not found\n");
    }
}

fn checkApiKeys(writer: anytype) !void {
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "ANTHROPIC_API_KEY")) |key| {
        defer std.heap.page_allocator.free(key);
        try writer.writeAll(if (key.len > 0) "OK   ANTHROPIC_API_KEY is set\n" else "WARN ANTHROPIC_API_KEY is empty\n");
    } else |_| {
        try writer.writeAll("WARN ANTHROPIC_API_KEY is not set\n");
    }
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "OPENAI_API_KEY")) |key| {
        defer std.heap.page_allocator.free(key);
        try writer.writeAll(if (key.len > 0) "OK   OPENAI_API_KEY is set\n" else "WARN OPENAI_API_KEY is empty\n");
    } else |_| {
        try writer.writeAll("WARN OPENAI_API_KEY is not set\n");
    }
}

fn checkConfigDir(writer: anytype) !void {
    const home = std.process.getEnvVarOwned(std.heap.page_allocator, "HOME") catch {
        try writer.writeAll("WARN Could not determine HOME directory\n");
        return;
    };
    defer std.heap.page_allocator.free(home);
    const config_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/.config/powerglide", .{home});
    defer std.heap.page_allocator.free(config_path);
    var config_dir = std.fs.openDirAbsolute(config_path, .{}) catch {
        try writer.print("WARN ~/.config/powerglide: not found (will be created on first run)\n", .{});
        return;
    };
    config_dir.close();
    try writer.writeAll("OK   ~/.config/powerglide: exists\n");
}

test "VERSION constant is defined" {
    try std.testing.expectEqualStrings("0.1.0", VERSION);
}

test "VERSION matches expected format" {
    // Version should start with a number followed by dot
    try std.testing.expect(VERSION.len >= 3);
    try std.testing.expect(VERSION[0] == '0');
    try std.testing.expect(VERSION[1] == '.');
}
