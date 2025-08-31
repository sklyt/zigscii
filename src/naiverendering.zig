const ESC = "\x1B";
const CSI = ESC ++ "[";
const CLEAR_SCREEN = CSI ++ "2J";
const CURSOR_HOME = CSI ++ "H";
const HIDE_CURSOR = CSI ++ "?25l";
const SHOW_CURSOR = CSI ++ "?25h";

fn setCursor(row: u16, col: u16) void {
    d_print(CSI ++ "{};{}H", .{ row, col });
}

// problem 1: flickering
fn naiveRender(entities: []const Entity, frame: u32) void {
    // Clear entire screen every frame - causes flicker!
    print(CLEAR_SCREEN ++ CURSOR_HOME);

    // Draw world bounds
    for (0..20) |y| {
        setCursor(@intCast(y + 2), 5);
        for (0..40) |x| {
            if (y == 0 or y == 19 or x == 0 or x == 39) {
                print("#");
            } else {
                print(".");
            }
        }
    }

    // Draw all entities - no layering, no optimization
    for (entities) |entity| {
        setCursor(@intCast(entity.y + 2), @intCast(entity.x + 5));
        d_print("{c}", .{entity.character});
    }

    // Status info redrawn every frame
    setCursor(1, 1);
    d_print("Frame: {} | Entities: {}", .{ frame, entities.len });
}

// PROBLEM 2: String allocation hell - creating ANSI codes repeatedly
fn coloredNaiveRender(entities: []const Entity) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print(CLEAR_SCREEN ++ CURSOR_HOME);

    for (entities) |entity| {
        // Allocating strings every frame - terrible for performance!
        const color_code = try std.fmt.allocPrint(allocator, CSI ++ "38;2;{};{};{}m", .{ entity.color.r, entity.color.g, entity.color.b });
        defer allocator.free(color_code);

        const position_code = try std.fmt.allocPrint(allocator, CSI ++ "{};{}H", .{ entity.y + 2, entity.x + 5 });
        defer allocator.free(position_code);

        d_print("{s}{s}{c}" ++ CSI ++ "0m", .{ position_code, color_code, entity.character });
    }
}

// PROBLEM 3: No state tracking - redundant operations
var last_cursor_x: u16 = 0;
var last_cursor_y: u16 = 0;
var last_color: u32 = 0;

fn inefficientRender(entities: []const Entity) void {
    for (entities) |entity| {
        // Always setting cursor, even if it hasn't moved
        setCursor(@intCast(entity.y + 2), @intCast(entity.x + 5));
        last_cursor_x = @intCast(entity.x + 5);
        last_cursor_y = @intCast(entity.y + 2);

        // Always setting color, even if it's the same
        const color_packed = (@as(u32, entity.color.r) << 16) |
            (@as(u32, entity.color.g) << 8) |
            entity.color.b;

        print(CSI ++ "38;2;{};{};{}m{c}", .{ entity.color.r, entity.color.g, entity.color.b, entity.character });
        last_color = color_packed;
    }
}

const Entity = struct {
    x: i32,
    y: i32,
    character: u8,
    color: Color,
    z_order: i8,

    const Color = struct {
        r: u8,
        g: u8,
        b: u8,
    };
};

pub fn demoNaiverender() !void {
    print("=== Problems with Naive Rendering ===\n\n");

    // Create test entities
    var entities = [_]Entity{
        Entity{ .x = 10, .y = 5, .character = '@', .color = .{ .r = 255, .g = 255, .b = 255 }, .z_order = 10 },
        Entity{ .x = 15, .y = 8, .character = 'E', .color = .{ .r = 255, .g = 0, .b = 0 }, .z_order = 5 },
        Entity{ .x = 8, .y = 12, .character = 'T', .color = .{ .r = 0, .g = 255, .b = 0 }, .z_order = 1 },
        Entity{ .x = 20, .y = 10, .character = '$', .color = .{ .r = 255, .g = 255, .b = 0 }, .z_order = 2 },
    };

    print("Issues with naive approaches:\n\n");

    print("1. FLICKERING:\n");
    print("   - Clearing entire screen causes visible flicker\n");
    print("   - User sees the clear-draw cycle\n");
    print("   - Worse on slower terminals\n\n");

    print("2. PERFORMANCE:\n");
    print("   - Allocating strings every frame\n");
    print("   - Redundant ANSI escape sequences\n");
    print("   - No dirty region tracking\n");
    print("   - Sending unnecessary data to terminal\n\n");

    print("3. VISUAL ISSUES:\n");
    print("   - No z-ordering/layering\n");
    print("   - No transparency or blending\n");
    print("   - Cursor visible during rendering\n");
    print("   - No smooth animations\n\n");

    print("4. MAINTENANCE:\n");
    print("   - Rendering logic scattered everywhere\n");
    print("   - Hard to add new visual features\n");
    print("   - Difficult to optimize\n");
    print("   - No separation of concerns\n\n");

    // Quick demo - comment out to avoid flicker
    //
    print("Running naive render (will flicker):\n");
    print(HIDE_CURSOR);

    for (0..30) |frame| {
        naiveRender(&entities, @intCast(frame));
        std.time.sleep(100_000_000); // 100ms
    }

    print(SHOW_CURSOR);
    //

    print("The solution: A proper rendering engine with:\n");
    print("• Double buffering (eliminate flicker)\n");
    print("• Dirty rectangle tracking (performance)\n");
    print("• State management (avoid redundant operations)\n");
    print("• Layering system (proper z-ordering)\n");
    print("• Memory pools (avoid allocations)\n");
    print("• Batch operations (minimize terminal I/O)\n");
}
const std = @import("std");
const builtin = @import("builtin");

const d_print = std.debug.print;

fn print(s: []const u8) void {
    d_print("{s}", .{s});
}
