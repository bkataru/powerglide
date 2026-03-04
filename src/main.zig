const std = @import("std");
const json = std.json;
// const clap = @import("clap");
const clap = @import("clap");
const pg_lib = @import("powerglide");
const tui_app = pg_lib.tui;

const VERSION = "0.1.1";
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

    if (std.mem.eql(u8, top_level, "mcp")) {
        try handleMcp(allocator);
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
        \\powerglide 0.1.1 — the CLI coding agent that slides
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
        \\ EXAMPLES:
        \\  powerglide run "Fix the bug in auth.zig"
        \\  powerglide run --agent hephaestus --velocity 2.0 "Add unit tests"
        \\  powerglide session list
        \\  powerglide session resume ses_abc123 "Continue adding tests"
        \\  powerglide doctor
        \\  powerglide config get velocity
        \\  powerglide config set velocity 2.0

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
            \\ -v, --velocity <val> Velocity multiplier (default: 1.0)
            \\ -s, --session-id <id> Continue existing session
            \\ -m, --model <provider/model> Model to use
            \\
            \\EXAMPLES:
            \\ powerglide run "Fix the bug in auth.zig"
            \\ powerglide run --agent hephaestus --velocity 2.0 "Add unit tests"
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
            \\ velocity Velocity multiplier (base 1000ms)
            \\ default_agent Default agent name
            \\ model Default model
            \\ max_steps Max steps per session
            \\
            \\EXAMPLES:
            \\ powerglide config get velocity
            \\ powerglide config set velocity 2.0
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
    var velocity: ?f64 = null;
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
                velocity = std.fmt.parseFloat(f64, args[i + 1]) catch {
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

    // Initialize tools registry
    var registry = powerglide.registry.Registry.init(allocator);
    defer registry.deinit();

    // Load MCP servers from config
    for (config.mcp_servers) |mcp_config| {
        // Build command array [command, ...args]
        var full_cmd = std.ArrayList([]const u8){};
        defer full_cmd.deinit(allocator);
        try full_cmd.append(allocator, mcp_config.command);
        for (mcp_config.args) |arg| {
            try full_cmd.append(allocator, arg);
        }

        registry.registerMcpServer(mcp_config.name, full_cmd.items) catch |err| {
            std.debug.print("Warning: Failed to register MCP server '{s}': {}\n", .{mcp_config.name, err});
        };
    }

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
        .velocity = velocity orelse (if (agent) |a| a.velocity else config.velocity),
        .model = model orelse (if (agent) |a| a.model else config.model),
    };

    // Initialize and run the loop
    var loop = powerglide.agent.Loop.init(allocator, loop_config);
    defer loop.deinit();

    std.debug.print("Starting powerglide session\n", .{});
    std.debug.print("  Agent: {s}\n", .{resolved_agent_name});
    std.debug.print("  Model: {s}\n", .{loop_config.model});
    std.debug.print("  Velocity: {d:.1}x\n", .{loop_config.velocity});
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
            "Agent: {s}\n  Model: {s}\n  Role: {s}\n  Velocity: {d:.1}x\n  Instructions: {s}\n",
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
            .velocity = 1.0,
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
    const PersistenceManager = powerglide.persistence.PersistenceManager;


    var persistence = try PersistenceManager.init(allocator);
    defer persistence.deinit();

    const stdout = std.fs.File.stdout().deprecatedWriter();
    const stderr = std.fs.File.stderr().deprecatedWriter();

    if (std.mem.eql(u8, subcommand, "list")) {
        try stdout.writeAll("Sessions:\n");
        const session_ids = try persistence.listSessions(allocator);
        defer {
            for (session_ids) |id| allocator.free(id);
            allocator.free(session_ids);
        }
        
        if (session_ids.len == 0) {
            try stdout.writeAll("  (no active sessions)\n");
            try stdout.writeAll("\nUse 'powerglide run' to start a new session.\n");
        } else {
            for (session_ids) |id| {
                try stdout.print("  {s}\n", .{id});
            }
            try stdout.print("\nTotal: {d} session(s)\n", .{session_ids.len});
        }
    } else if (std.mem.eql(u8, subcommand, "show")) {
        if (args.len < 2) {
            try stderr.print("powerglide session: error: 'show' requires a session ID\n", .{});
            std.process.exit(1);
        }
        const session_id = args[1];
        
        var session = persistence.loadSession(session_id) catch |err| {
            if (err == error.FileNotFound) {
                try stderr.print("powerglide session: error: session '{s}' not found\n", .{session_id});
            } else {
                try stderr.print("powerglide session: error: failed to load session: {}\n", .{err});
            }
            std.process.exit(1);
        };
        defer session.deinit(allocator);
        
        const status_str = @tagName(session.status);
        try stdout.print("Session: {s}\n", .{session.id});
        try stdout.print("Status: {s}\n", .{status_str});
        try stdout.print("Steps: {d}\n", .{session.step_count});
        try stdout.print("Velocity: {d:.1}x\n", .{session.velocity});
        try stdout.print("Tasks: {d}\n", .{session.tasks.items.len});
        try stdout.print("Messages: {d}\n", .{session.messages.items.len});
        try stdout.print("Created: {d}\n", .{session.created_at});
        try stdout.print("Updated: {d}\n", .{session.updated_at});
    } else if (std.mem.eql(u8, subcommand, "resume")) {
        if (args.len < 2) {
            try stderr.print("powerglide session: error: 'resume' requires a session ID\n", .{});
            std.process.exit(1);
        }
        try stdout.print("Resuming session: {s}\n", .{args[1]});
        if (args.len > 2) {
            try stdout.print("Message: {s}\n", .{args[2]});
        }
        try stdout.writeAll("(resume not yet implemented - would use run command with session-id)\n");
    } else if (std.mem.eql(u8, subcommand, "delete")) {
        if (args.len < 2) {
            try stderr.print("powerglide session: error: 'delete' requires a session ID\n", .{});
            std.process.exit(1);
        }
        const session_id = args[1];
        
        persistence.deleteSession(session_id) catch |err| {
            if (err == error.FileNotFound) {
                try stderr.print("powerglide session: error: session '{s}' not found\n", .{session_id});
            } else {
                try stderr.print("powerglide session: error: failed to delete session: {}\n", .{err});
            }
            std.process.exit(1);
        };
        
        try stdout.print("Deleted session: {s}\n", .{session_id});
    } else if (std.mem.eql(u8, subcommand, "export")) {
        if (args.len < 2) {
            try stderr.print("powerglide session: error: 'export' requires a session ID\n", .{});
            std.process.exit(1);
        }
        const session_id = args[1];
        
        var session = try persistence.loadSession(session_id);
        defer session.deinit(allocator);
        
        // Export session to temp file and print to stdout
        const export_path = try std.fmt.allocPrint(allocator, "/tmp/{s}.json", .{session_id});
        defer allocator.free(export_path);
        
        session.save(allocator, export_path) catch |err| {
            try stderr.print("powerglide session: error: failed to export session: {}\n", .{err});
            std.process.exit(1);
        };
        
        const file = std.fs.cwd().openFile(export_path, .{}) catch |err| {
            try stderr.print("powerglide session: error: failed to read exported session: {}\n", .{err});
            std.process.exit(1);
        };
        defer file.close();
        
        const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
        defer allocator.free(content);
        
        try stdout.writeAll(content);
        // Cleanup temp file
        std.fs.cwd().deleteFile(export_path) catch {};
        try stderr.print("powerglide session: unknown subcommand '{s}'\n", .{subcommand});
        try printCommandHelp("session", stdout);
        std.process.exit(1);
    }
}

/// Handle the 'swarm' subcommand
fn handleSwarm(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    if (args.len == 0) {
        try printCommandHelp("swarm", std.fs.File.stdout().deprecatedWriter());
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "--help") or std.mem.eql(u8, subcommand, "-h")) {
        try printCommandHelp("swarm", std.fs.File.stdout().deprecatedWriter());
        return;
    }

    const powerglide = @import("powerglide");
    const SwarmManager = powerglide.swarm_manager.SwarmManager;

    var swarm_manager = try SwarmManager.init(allocator);
    defer swarm_manager.deinit();

    swarm_manager.load() catch |err| {
        if (err != error.FileNotFound) {
            try std.fs.File.stderr().deprecatedWriter().print("Warning: Failed to load swarms: {}\n", .{err});
        }
    };

    const stdout = std.fs.File.stdout().deprecatedWriter();
    const stderr = std.fs.File.stderr().deprecatedWriter();

    if (std.mem.eql(u8, subcommand, "list")) {
        try stdout.writeAll("Swarms:\n");
        var it = swarm_manager.listSwarms();
        var count: usize = 0;
        while (it.next()) |entry| {
            const swarm = entry.value_ptr.*;
            try stdout.print("  {s} (agents: {d}, workers: {d})\n", .{swarm.name, swarm.agents.items.len, swarm.max_workers});
            count += 1;
        }
        if (count == 0) {
            try stdout.writeAll("  (no active swarms)\n");
            try stdout.writeAll("\nUse 'powerglide swarm create <name> <working_dir>' to create a new swarm.\n");
        } else {
            try stdout.print("\nTotal: {d} swarm(s)\n", .{count});
        }
    } else if (std.mem.eql(u8, subcommand, "create")) {
        if (args.len < 3) {
            try stderr.print("powerglide swarm: error: 'create' requires a swarm name and working directory\n", .{});
            std.process.exit(1);
        }
        const swarm_name = args[1];
        const working_dir = args[2];
        
        swarm_manager.createSwarm(swarm_name, working_dir) catch |err| {
            if (err == error.SwarmAlreadyExists) {
                try stderr.print("powerglide swarm: error: swarm '{s}' already exists\n", .{swarm_name});
            } else {
                try stderr.print("powerglide swarm: error: failed to create swarm: {}\n", .{err});
            }
            std.process.exit(1);
        };
        
        try swarm_manager.save();
        try stdout.print("Created swarm '{s}' in '{s}'\n", .{swarm_name, working_dir});
    } else if (std.mem.eql(u8, subcommand, "add")) {
        if (args.len < 3) {
            try stderr.print("powerglide swarm: error: 'add' requires swarm name and agent name\n", .{});
            std.process.exit(1);
        }
        const swarm_name = args[1];
        const agent_name = args[2];
        
        swarm_manager.addAgent(swarm_name, agent_name) catch |err| {
            if (err == error.SwarmNotFound) {
                try stderr.print("powerglide swarm: error: swarm '{s}' not found\n", .{swarm_name});
            } else {
                try stderr.print("powerglide swarm: error: failed to add agent: {}\n", .{err});
            }
            std.process.exit(1);
        };
        
        try swarm_manager.save();
        try stdout.print("Added agent '{s}' to swarm '{s}'\n", .{agent_name, swarm_name});
    } else if (std.mem.eql(u8, subcommand, "remove")) {
        if (args.len < 3) {
            try stderr.print("powerglide swarm: error: 'remove' requires swarm name and agent name\n", .{});
            std.process.exit(1);
        }
        const swarm_name = args[1];
        const agent_name = args[2];
        
        swarm_manager.removeAgent(swarm_name, agent_name) catch |err| {
            if (err == error.SwarmNotFound) {
                try stderr.print("powerglide swarm: error: swarm '{s}' not found\n", .{swarm_name});
            } else if (err == error.AgentNotFound) {
                try stderr.print("powerglide swarm: error: agent '{s}' not found in swarm\n", .{agent_name});
            } else {
                try stderr.print("powerglide swarm: error: failed to remove agent: {}\n", .{err});
            }
            std.process.exit(1);
        };
        
        try swarm_manager.save();
        try stdout.print("Removed agent '{s}' from swarm '{s}'\n", .{agent_name, swarm_name});
    } else if (std.mem.eql(u8, subcommand, "run")) {
        if (args.len < 3) {
            try stderr.print("powerglide swarm: error: 'run' requires swarm name and message\n", .{});
            std.process.exit(1);
        }
        const swarm_name = args[1];
        const message = args[2..];
        
        const swarm = swarm_manager.getSwarm(swarm_name) orelse {
            try stderr.print("powerglide swarm: error: swarm '{s}' not found\n", .{swarm_name});
            std.process.exit(1);
        };
        
        try stdout.print("Running swarm: {s}\n", .{swarm_name});
        try stdout.print("  Working dir: {s}\n", .{swarm.working_dir});
        try stdout.print("  Agents: ", .{});
        for (swarm.agents.items, 0..) |agent, i| {
            if (i > 0) try stdout.print(", ", .{});
            try stdout.print("{s}", .{agent});
        }
        try stdout.writeAll("\n");
        try stdout.print("  Message: ", .{});
        for (message) |msg_part| {
            try stdout.print("{s} ", .{msg_part});
        }
        try stdout.writeAll("\n");
        try stdout.writeAll("(swarm run not yet fully implemented - would use orchestrator.Swarm)\n");
    } else if (std.mem.eql(u8, subcommand, "delete")) {
        if (args.len < 2) {
            try stderr.print("powerglide swarm: error: 'delete' requires a swarm name\n", .{});
            std.process.exit(1);
        }
        const swarm_name = args[1];
        
        swarm_manager.deleteSwarm(swarm_name) catch |err| {
            if (err == error.SwarmNotFound) {
                try stderr.print("powerglide swarm: error: swarm '{s}' not found\n", .{swarm_name});
            } else {
                try stderr.print("powerglide swarm: error: failed to delete swarm: {}\n", .{err});
            }
            std.process.exit(1);
        };
        
        try swarm_manager.save();
        try stdout.print("Deleted swarm '{s}'\n", .{swarm_name});
    } else {
        try stderr.print("powerglide swarm: unknown subcommand '{s}'\n", .{subcommand});
        try printCommandHelp("swarm", stdout);
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
        
        const value = if (std.mem.eql(u8, args[1], "velocity")) 
            try std.fmt.allocPrint(allocator, "{d:.1}x", .{config.velocity})
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
        // Load current config
        var config = try powerglide.config.load(allocator);
        defer config.deinit(allocator);
        
        const key = args[1];
        const value = args[2];
        
        // Update the config field based on key
        if (std.mem.eql(u8, key, "velocity")) {
            config.velocity = std.fmt.parseFloat(f64, value) catch {
                try std.fs.File.stderr().deprecatedWriter().print("powerglide config: error: invalid value for velocity\n", .{});
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, key, "max_steps")) {
            config.max_steps = std.fmt.parseInt(u32, value, 10) catch {
                try std.fs.File.stderr().deprecatedWriter().print("powerglide config: error: invalid value for max_steps\n", .{});
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, key, "model") or std.mem.eql(u8, key, "default_model")) {
            config.model = try allocator.dupe(u8, value);
        } else if (std.mem.eql(u8, key, "shell")) {
            config.shell = try allocator.dupe(u8, value);
        } else {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide config: error: unknown key '{s}'\n", .{key});
            try std.fs.File.stderr().deprecatedWriter().writeAll("Valid keys: velocity, max_steps, model, default_model, shell\n");
            std.process.exit(1);
        }
        
        // Save config
        const config_path = try powerglide.config.defaultConfigPath(allocator);
        defer allocator.free(config_path);
        try config.save(allocator, config_path);
        try std.fs.File.stdout().deprecatedWriter().print("Set {s} = {s}\n", .{key, value});
    } else if (std.mem.eql(u8, subcommand, "list")) {
        const config = try powerglide.config.load(allocator);
        defer config.deinit(allocator);
        
        try std.fs.File.stdout().deprecatedWriter().print(
            "Configuration:\n  model: {s}\n  velocity: {d:.1}x\n  max_steps: {d}\n  shell: {s}\n\nConfig file: ~/.config/powerglide/config.json\n\n",
            .{ config.model, config.velocity, config.max_steps, config.shell },
        );
    } else if (std.mem.eql(u8, subcommand, "edit")) {
        const config_path = try powerglide.config.defaultConfigPath(allocator);
        defer allocator.free(config_path);
        
        // Get EDITOR env var, default to vim
        const editor = std.process.getEnvVarOwned(allocator, "EDITOR") catch try allocator.dupe(u8, "vim");
        defer allocator.free(editor);
        
        // Run editor
        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ editor, config_path },
        }) catch |err| {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide config: error: failed to open editor: {}\n", .{err});
            std.process.exit(1);
        };
        defer {
            allocator.free(result.stdout);
            allocator.free(result.stderr);
        }
        
        if (result.term.Exited != 0 and result.term.Exited != 0) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide config: warning: editor exited with non-zero status\n", .{});
        }
        
        try std.fs.File.stdout().deprecatedWriter().print("Edited config file: {s}\n", .{config_path});
    } else if (std.mem.eql(u8, subcommand, "init")) {
        const config_path = try powerglide.config.defaultConfigPath(allocator);
        defer allocator.free(config_path);
        
        // Create default config (overwrites if already exists)
        const default_config = powerglide.config.Config.default();
        try default_config.save(allocator, config_path);
        try std.fs.File.stdout().deprecatedWriter().print("Initialized config at: {s}\n", .{config_path});
        try std.fs.File.stdout().deprecatedWriter().writeAll("You can now edit it with 'powerglide config edit'\n");
    } else {
        try std.fs.File.stderr().deprecatedWriter().print("powerglide config: unknown subcommand '{s}'\n", .{subcommand});
        try printCommandHelp("config", std.fs.File.stdout().deprecatedWriter());
        std.process.exit(1);
    }

}
/// Handle the 'tools' subcommand
fn handleTools(allocator: std.mem.Allocator, args: [][:0]u8) !void {
    const powerglide = @import("powerglide");
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
        // Show tool details - use hardcoded lookup
        const name = args[1];
        
        // Define tools directly to avoid iteration issues  
        const ToolInfo = struct { n: []const u8, d: []const u8, s: []const u8 };
        const tools = &[_]ToolInfo{
            ToolInfo{ .n = "bash", .d = "Execute a shell command and return its output", .s = "{\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"}},\"required\":[\"command\"]}" },
            ToolInfo{ .n = "read", .d = "Read contents of a file", .s = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}" },
            ToolInfo{ .n = "write", .d = "Write content to a file", .s = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"content\":{\"type\":\"string\"}},\"required\":[\"path\",\"content\"]}" },
            ToolInfo{ .n = "edit", .d = "Edit a specific portion of a file (find and replace)", .s = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"old\":{\"type\":\"string\"},\"new\":{\"type\":\"string\"}},\"required\":[\"path\",\"old\",\"new\"]}" },
            ToolInfo{ .n = "grep", .d = "Search for patterns in files", .s = "{\"type\":\"object\",\"properties\":{\"pattern\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"}},\"required\":[\"pattern\"]}" },
            ToolInfo{ .n = "glob", .d = "Find files matching a glob pattern", .s = "{\"type\":\"object\",\"properties\":{\"pattern\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"}},\"required\":[\"pattern\"]}" },
        };
        
        var found = false;
        for (tools) |t| {
            if (std.mem.eql(u8, t.n, name)) {
                try std.fs.File.stdout().deprecatedWriter().print("Tool: {s}\nDescription: {s}\nInput Schema: {s}\n", .{ t.n, t.d, t.s });
                found = true;
                break;
            }
        }
        if (!found) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide tools: tool '{s}' not found\n", .{name});
            std.process.exit(1);
        }
    } else if (std.mem.eql(u8, subcommand, "test")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide tools: error: 'test' requires a tool name\n", .{});
            std.process.exit(1);
        }
        // Test tool - uses BuiltinTools
        const name = args[1];
        const all = powerglide.tools.BuiltinTools.all();
        
        // Get the handler directly by name
        var handler: ?powerglide.tools.ToolFn = null;
        for (all) |t| {
            if (std.mem.eql(u8, t.name, name)) {
                handler = t.handler;
                break;
            }
        }
        
        if (handler == null) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide tools: tool '{s}' not found\n", .{name});
            std.process.exit(1);
        }
        
        // Build test arguments
        var args_map = std.json.ObjectMap.init(allocator);
        defer args_map.deinit();
        
        if (std.mem.eql(u8, name, "bash")) {
            try args_map.put("command", json.Value{ .string = "echo test" });
        } else if (std.mem.eql(u8, name, "read")) {
            try args_map.put("path", json.Value{ .string = "README.md" });
        } else if (std.mem.eql(u8, name, "write")) {
            try args_map.put("path", json.Value{ .string = "/tmp/test.txt" });
            try args_map.put("content", json.Value{ .string = "hello" });
        } else {
            try std.fs.File.stdout().deprecatedWriter().print("Test not implemented for '{s}'\n", .{name});
            return;
        }
        
        const ToolInput = powerglide.tools.ToolInput;
        const inp = ToolInput{ .name = name, .arguments = json.Value{ .object = args_map } };
        
        try std.fs.File.stdout().deprecatedWriter().print("Testing '{s}'...\n", .{name});
        const res = handler.?(allocator, null, inp) catch |e| {
            try std.fs.File.stderr().deprecatedWriter().print("Error: {}\n", .{e});
            std.process.exit(1);
        };
        defer allocator.free(res.content);
        
        if (res.is_error) try std.fs.File.stdout().deprecatedWriter().print("FAILED\n", .{})
        else try std.fs.File.stdout().deprecatedWriter().print("PASSED\n", .{});
    } else if (std.mem.eql(u8, subcommand, "register")) {
        if (args.len < 2) {
            try std.fs.File.stderr().deprecatedWriter().print("powerglide tools: error: 'register' requires a path\n", .{});
            std.process.exit(1);
        }
        try std.fs.File.stdout().deprecatedWriter().writeAll("External tool registration not implemented.\n\n");
        try std.fs.File.stdout().deprecatedWriter().print("Path: {s}\n\n", .{args[1]});
        try std.fs.File.stdout().deprecatedWriter().writeAll("This feature will load custom tools from JSON definition files.\n");
    } else {
        try std.fs.File.stderr().deprecatedWriter().print("powerglide tools: unknown subcommand '{s}'\n", .{subcommand});
        try printCommandHelp("tools", std.fs.File.stdout().deprecatedWriter());
        std.process.exit(1);
    }
}

/// Handle the 'mcp' command (start MCP server)
fn handleMcp(allocator: std.mem.Allocator) !void {
    const powerglide = @import("powerglide");
    var registry = powerglide.registry.Registry.init(allocator);
    defer registry.deinit();

    var server = powerglide.mcp_server.McpServer.init(allocator, &registry);
    try server.run();
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
    try std.testing.expectEqualStrings("0.1.1", VERSION);
}

test "VERSION matches expected format" {
    // Version should start with a number followed by dot
    try std.testing.expect(VERSION.len >= 3);
    try std.testing.expect(VERSION[0] == '0');
    try std.testing.expect(VERSION[1] == '.');
}
