const std = @import("std");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

// ── Agent data ────────────────────────────────────────────────────────────────

const AgentState = enum { idle, running, done };

const Agent = struct {
    name: []const u8,
    state: AgentState,
    step: u32,
};

// ── Dashboard widget ──────────────────────────────────────────────────────────

/// Root dashboard widget — owns all app state.
const Dashboard = struct {
    allocator: std.mem.Allocator,
    agents: []const Agent,
    log_lines: []const []const u8,
    refresh_count: u32,

    pub fn widget(self: *const Dashboard) vxfw.Widget {
        return .{
            .userdata = @constCast(self),
            .drawFn = typeErasedDraw,
            .eventHandler = typeErasedHandleEvent,
        };
    }

    fn typeErasedDraw(ptr: *anyopaque, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const self: *const Dashboard = @ptrCast(@alignCast(ptr));
        return self.draw(ctx);
    }

    fn typeErasedHandleEvent(ptr: *anyopaque, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        const self: *Dashboard = @ptrCast(@alignCast(ptr));
        return self.handleEvent(ctx, event);
    }

    pub fn handleEvent(self: *Dashboard, ctx: *vxfw.EventContext, event: vxfw.Event) anyerror!void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('q', .{})) {
                    ctx.quit = true;
                    return;
                }
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }
                if (key.matches('r', .{})) {
                    self.refresh_count +%= 1;
                    ctx.redraw = true;
                    return;
                }
            },
            else => {},
        }
    }

    pub fn draw(self: *const Dashboard, ctx: vxfw.DrawContext) std.mem.Allocator.Error!vxfw.Surface {
        const max = ctx.max.size();

        // ── Header (1 row) ──────────────────────────────────────────────
        const header_text = buildHeaderText(ctx.arena, self.refresh_count) catch
            "powerglide v0.1.0 — multi-agent coding dashboard";

        const header = vxfw.Text{
            .text = header_text,
            .style = .{ .bold = true, .fg = .{ .index = 6 } }, // cyan
            .softwrap = false,
            .width_basis = .parent,
        };

        // ── Status bar (1 row) ──────────────────────────────────────────
        const statusbar = vxfw.Text{
            .text = "q/Ctrl+C: quit  r: refresh  h: help",
            .style = .{ .bg = .{ .index = 0 }, .fg = .{ .index = 3 } }, // yellow on black
            .softwrap = false,
            .width_basis = .parent,
        };

        // ── Agent panel text ────────────────────────────────────────────
        const agents_text = buildAgentsText(ctx.arena, self.agents) catch
            "agent-1: idle\nagent-2: running (step 42)\nagent-3: done";

        const agents_widget = vxfw.Text{
            .text = agents_text,
            .style = .{ .fg = .{ .index = 2 } }, // green
            .softwrap = false,
            .width_basis = .parent,
        };

        // ── Log panel text ──────────────────────────────────────────────
        const logs_text = buildLogsText(ctx.arena, self.log_lines) catch
            "[INFO] powerglide started\n[INFO] agents initialised\n[INFO] ready";

        const logs_widget = vxfw.Text{
            .text = logs_text,
            .style = .{ .fg = .{ .index = 7 } }, // white/light-grey
            .softwrap = false,
            .width_basis = .parent,
        };

        // ── Layout ──────────────────────────────────────────────────────
        // We'll build the layout manually using SubSurfaces so we can control
        // the exact dimensions (header=1 row, statusbar=1 row, content=rest).

        const content_height: u16 = if (max.height > 2) max.height - 2 else 0;
        const left_width: u16 = @intCast(max.width * 2 / 5); // ~40 %
        const right_width: u16 = if (max.width > left_width + 1) max.width - left_width - 1 else 0;

        var children = std.ArrayList(vxfw.SubSurface){};

        // Header surface
        {
            const hdr_ctx = ctx.withConstraints(
                .{ .width = max.width, .height = 1 },
                .{ .width = max.width, .height = 1 },
            );
            const hdr_surf = try header.draw(hdr_ctx);
            try children.append(ctx.arena, .{
                .origin = .{ .row = 0, .col = 0 },
                .surface = hdr_surf,
                .z_index = 0,
            });
        }

        // Left (agents) panel
        if (content_height > 0 and left_width > 0) {
            const left_ctx = ctx.withConstraints(
                .{ .width = left_width, .height = content_height },
                .{ .width = left_width, .height = content_height },
            );
            const left_surf = try agents_widget.draw(left_ctx);
            try children.append(ctx.arena, .{
                .origin = .{ .row = 1, .col = 0 },
                .surface = left_surf,
                .z_index = 0,
            });
        }

        // Right (logs) panel
        if (content_height > 0 and right_width > 0) {
            const right_ctx = ctx.withConstraints(
                .{ .width = right_width, .height = content_height },
                .{ .width = right_width, .height = content_height },
            );
            const right_surf = try logs_widget.draw(right_ctx);
            try children.append(ctx.arena, .{
                .origin = .{ .row = 1, .col = left_width + 1 },
                .surface = right_surf,
                .z_index = 0,
            });
        }

        // Status bar
        {
            const sb_ctx = ctx.withConstraints(
                .{ .width = max.width, .height = 1 },
                .{ .width = max.width, .height = 1 },
            );
            const sb_surf = try statusbar.draw(sb_ctx);
            try children.append(ctx.arena, .{
                .origin = .{ .row = max.height - 1, .col = 0 },
                .surface = sb_surf,
                .z_index = 0,
            });
        }

        // Root surface — draw the vertical separator between the two panels
        var surface = try vxfw.Surface.initWithChildren(
            ctx.arena,
            self.widget(),
            max,
            children.items,
        );

        // Draw vertical separator line
        if (content_height > 0 and left_width < max.width) {
            var row: u16 = 1;
            while (row < 1 + content_height) : (row += 1) {
                surface.writeCell(left_width, row, .{
                    .char = .{ .grapheme = "│", .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } }, // dark grey
                });
            }
        }

        // Draw horizontal separator under header
        if (max.width > 0) {
            var col: u16 = 0;
            while (col < max.width) : (col += 1) {
                surface.writeCell(col, 1, .{
                    .char = .{ .grapheme = "─", .width = 1 },
                    .style = .{ .fg = .{ .index = 8 } },
                });
            }
        }

        return surface;
    }
};

// ── Helper: build header text ─────────────────────────────────────────────────

fn buildHeaderText(arena: std.mem.Allocator, refresh_count: u32) ![]const u8 {
    const ts = std.time.timestamp();
    const secs: u64 = @intCast(if (ts < 0) 0 else ts);
    const hours = (secs % 86400) / 3600;
    const minutes = (secs % 3600) / 60;
    const seconds = secs % 60;
    return std.fmt.allocPrint(
        arena,
        "powerglide v0.1.0 — multi-agent coding dashboard  [{d:0>2}:{d:0>2}:{d:0>2} UTC]  [refreshes: {d}]",
        .{ hours, minutes, seconds, refresh_count },
    );
}

// ── Helper: build agents text ─────────────────────────────────────────────────

fn buildAgentsText(arena: std.mem.Allocator, agents: []const Agent) ![]const u8 {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(arena);

    try buf.appendSlice(arena, "=== Agents ===\n");
    for (agents) |ag| {
        const state_str: []const u8 = switch (ag.state) {
            .idle => "idle",
            .running => "running",
            .done => "done",
        };
        if (ag.state == .running) {
            const line = try std.fmt.allocPrint(arena, "{s}: {s} (step {d})\n", .{ ag.name, state_str, ag.step });
            try buf.appendSlice(arena, line);
        } else {
            const line = try std.fmt.allocPrint(arena, "{s}: {s}\n", .{ ag.name, state_str });
            try buf.appendSlice(arena, line);
        }
    }
    return buf.items;
}

// ── Helper: build logs text ───────────────────────────────────────────────────

fn buildLogsText(arena: std.mem.Allocator, lines: []const []const u8) ![]const u8 {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(arena);

    try buf.appendSlice(arena, "=== Log Output ===\n");
    for (lines) |line| {
        try buf.appendSlice(arena, line);
        try buf.append(arena, '\n');
    }
    return buf.items;
}

// ── Public API ────────────────────────────────────────────────────────────────

pub const TUIApp = struct {
    allocator: std.mem.Allocator,
    running: bool = false,

    pub fn init(allocator: std.mem.Allocator) TUIApp {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TUIApp) void {
        _ = self;
    }

    /// Launches the full vxfw TUI event loop.
    /// If there is no TTY (e.g. CI), prints a message and returns gracefully.
    pub fn start(self: *TUIApp) !void {
        self.running = true;
        defer self.running = false;

        const placeholder_agents = [_]Agent{
            .{ .name = "agent-1", .state = .idle, .step = 0 },
            .{ .name = "agent-2", .state = .running, .step = 42 },
            .{ .name = "agent-3", .state = .done, .step = 100 },
        };

        const placeholder_logs = [_][]const u8{
            "[INFO]  powerglide v0.1.0 started",
            "[INFO]  loading configuration",
            "[INFO]  agent-1 initialised (idle)",
            "[INFO]  agent-2 initialised (running, step 42)",
            "[INFO]  agent-3 completed successfully",
            "[DEBUG] memory store ready",
            "[DEBUG] tool registry: 12 tools loaded",
            "[INFO]  dashboard ready — press 'r' to refresh",
        };

        var dashboard = Dashboard{
            .allocator = self.allocator,
            .agents = &placeholder_agents,
            .log_lines = &placeholder_logs,
            .refresh_count = 0,
        };

        var app = vxfw.App.init(self.allocator) catch |err| {
            if (err == error.NotATTY) {
                const stderr = std.fs.File.stderr().deprecatedWriter();
                try stderr.writeAll("powerglide TUI: not a TTY — skipping interactive dashboard\n");
                return;
            }
            return err;
        };
        defer app.deinit();

        try app.run(dashboard.widget(), .{ .framerate = 60 });
    }

    pub fn stop(self: *TUIApp) void {
        self.running = false;
    }

    pub fn render(self: *TUIApp) void {
        _ = self;
    }
};

test "placeholder" {
    try std.testing.expect(true);
}
