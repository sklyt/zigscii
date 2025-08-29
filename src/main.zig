// ANSI escape sequences are special character codes that control terminal behavior.
//They all start with the ESC character (ASCII 27) followed by [ and then command codes.

const d_print = std.debug.print;

fn print(s: []const u8) void {
    d_print("{s}", .{s});
}

fn enableUtf8() void {
    if (builtin.target.os.tag == .windows) {
        // Use Win32 calls to switch console to UTF-8 and enable VT processing
        const c = @cImport({
            @cInclude("windows.h");
        });

        // Set input/output code page to UTF-8
        // UINT SetConsoleOutputCP(UINT wCodePageID);
        _ = c.SetConsoleOutputCP(65001);
        _ = c.SetConsoleCP(65001);

        // Try to enable virtual terminal processing so ANSI escapes work reliably
        const hOut = c.GetStdHandle(c.STD_OUTPUT_HANDLE);
        var mode: u32 = 0;
        if (c.GetConsoleMode(hOut, &mode) != 0) {
            const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;
            _ = c.SetConsoleMode(hOut, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        }
    } else {
        // Ask libc to use the environment locale (so printf/term use UTF-8)
        const c = @cImport({
            @cInclude("locale.h");
        });
        // setlocale returns a C string, ignore return here
        _ = c.setlocale(c.LC_ALL, "");
    }
}

const ESC = "\x1B";
const CSI = ESC ++ "[";

// Cursor movement
const CURSOR_HOME = CSI ++ "H";
const CURSOR_UP = CSI ++ "A";
const CURSOR_DOWN = CSI ++ "B";
const CURSOR_RIGHT = CSI ++ "C";
const CURSOR_LEFT = CSI ++ "D";

// Screen control
const CLEAR_SCREEN = CSI ++ "2J";
const CLEAR_LINE = CSI ++ "2K";
const HIDE_CURSOR = CSI ++ "?25l";
const SHOW_CURSOR = CSI ++ "?25h";

// Colors (4-bit standard colors)
const RESET = CSI ++ "0m";
const RED = CSI ++ "31m";
const GREEN = CSI ++ "32m";
const YELLOW = CSI ++ "33m";
const BLUE = CSI ++ "34m";
const MAGENTA = CSI ++ "35m";
const CYAN = CSI ++ "36m";
const WHITE = CSI ++ "37m";

// Background colors
const BG_RED = CSI ++ "41m";
const BG_GREEN = CSI ++ "42m";
const BG_BLUE = CSI ++ "44m";

const Color = struct {
    const Self = @This();

    pub fn color4bit(allocator: std.mem.Allocator, color: u8) ![]u8 {
        // 30..37 are the 4-bit foreground codes
        return try std.fmt.allocPrint(allocator, "\x1b[{}m", .{30 + color});
    }

    pub fn color8bit(allocator: std.mem.Allocator, color: u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "\x1b[38;5;{}m", .{color});
    }

    pub fn colorRGB(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "\x1b[38;2;{};{};{}m", .{ r, g, b });
    }

    pub fn bgColor4bit(allocator: std.mem.Allocator, color: u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "\x1b[{}m", .{40 + color});
    }

    pub fn bgColor8bit(allocator: std.mem.Allocator, color: u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "\x1b[48;5;{}m", .{color});
    }

    pub fn bgColorRGB(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "\x1b[48;2;{};{};{}m", .{ r, g, b });
    }
};

fn moveCursor(row: u16, col: u16) void {
    d_print(CSI ++ "{d}H", .{row});
    if (col > 1) {
        var i: u16 = 1;
        while (i < col) : (i += 1) {
            d_print("{s}", .{CURSOR_RIGHT});
        }
    }
}

fn setCursor(row: u16, col: u16) void {
    d_print(CSI ++ "{d};{d}H", .{ row, col });
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator: std.mem.Allocator = gpa.allocator();
    // enableUtf8();
    print(CLEAR_SCREEN ++ CURSOR_HOME ++ HIDE_CURSOR);

    setCursor(2, 10);
    print(GREEN ++ "+------------+" ++ RESET);

    setCursor(3, 10);
    print(GREEN ++ "|" ++ YELLOW ++ "  TERMINAL  " ++ GREEN ++ "|" ++ RESET);

    setCursor(4, 10);
    print(GREEN ++ "|" ++ YELLOW ++ "   MAGIC!   " ++ GREEN ++ "|" ++ RESET);

    setCursor(5, 10);
    print(GREEN ++ "+------------+" ++ RESET);

    // Demonstrate colors
    setCursor(7, 10);
    print(RED ++ "Red text" ++ RESET);

    setCursor(8, 10);
    print(BG_BLUE ++ WHITE ++ "White on blue" ++ RESET);

    // Draw a simple "game world"
    setCursor(10, 10);
    print("Simple world:");

    var y: u16 = 11;
    while (y <= 15) : (y += 1) {
        setCursor(y, 10);
        var x: u16 = 0;
        while (x < 20) : (x += 1) {
            if (y == 11 or y == 15 or x == 0 or x == 19) {
                print(GREEN ++ "#" ++ RESET);
            } else if (y == 13 and x == 10) {
                print(YELLOW ++ "@" ++ RESET); // Player
            } else if (y == 12 and x == 15) {
                print(RED ++ "E" ++ RESET); // Enemy
            } else {
                print(".");
            }
        }
    }

    // Show cursor position info
    setCursor(17, 10);
    print("@ = Player, E = Enemy, # = Wall");

    setCursor(19, 1);
    print(CLEAR_SCREEN ++ CURSOR_HOME ++ HIDE_CURSOR);
    setCursor(2, 1);
    print("4-bit colors (16 colors):");
    setCursor(3, 1);

    var i: u8 = 0;
    while (i < 8) : (i += 1) {
        const color = try Color.color4bit(allocator, i);
        // print expects a comptime fmt string; pass runtime slices with {s}
        std.debug.print("{s}||{s}", .{ color, RESET });
        allocator.free(color); // free after use
    }

    std.debug.print("  ", .{}); // spacer

    // print with background color applied (foreground color + background 7)
    i = 0;
    while (i < 8) : (i += 1) {
        const fg = try Color.color4bit(allocator, i);
        const bg = try Color.bgColor4bit(allocator, 7);
        std.debug.print("{s}{s}█{s}", .{ fg, bg, RESET });
        allocator.free(fg);
        allocator.free(bg);
    }

    std.debug.print("{s}\n", .{SHOW_CURSOR});
    setCursor(5, 1);
    print("8-bit colors (256 colors) - Sample:");

    // Standard colors (0-15)
    setCursor(6, 1);
    i = 0;
    while (i < 16) : (i += 1) {
        const fg = try Color.color8bit(allocator, i);
        d_print("{s}█{s}", .{ fg, RESET });
        allocator.free(fg);
    }

    // 216 color cube (16-231)
    var row: u16 = 7;
    var color: u16 = 16;
    while (row < 13) : (row += 1) {
        setCursor(row, 1);
        var col: u16 = 0;
        while (col < 36 and color < 232) : ({
            col += 1;
            color += 1;
        }) {
            const fg = try Color.color8bit(allocator, @intCast(color));
            d_print("{s}|{s}", .{ fg, RESET });
            allocator.free(fg);
        }
    }

    // Grayscale (232-255)
    setCursor(13, 1);
    i = 232;
    while (i < 255) : (i += 1) {
        const fg = try Color.color8bit(allocator, i);
        d_print("{s}|{s}", .{ fg, RESET });
        allocator.free(fg);
    }

    // // Demonstrate 24-bit RGB colors
    // setCursor(15, 1);
    // print("24-bit RGB colors (16.7 million colors):");
    // setCursor(16, 1);

    // // Gradient example
    // var x: u16 = 0;
    // while (x < 50) : (x += 1) {
    //     const r = @as(u8, @intCast((x * 255) / 50));
    //     const g = @as(u8, @intCast(((50 - x) * 255) / 50));
    //     const b: u8 = 128;
    //     // print(Color.colorRGB(allocator, r, g, b) ++ "█" ++ RESET);
    //     d_print("{s}|{s}", .{ Color.colorRGB(allocator, r, g, b), RESET });
    // }

    // setCursor(17, 1);
    // // Rainbow gradient
    // x = 0;
    // while (x < 50) : (x += 1) {
    //     const hue = @as(f32, @floatFromInt(x)) / 50.0 * 360.0;
    //     const rgb = hsvToRgb(hue, 1.0, 1.0);
    //     // print(Color.colorRGB(allocator, rgb[0], rgb[1], rgb[2]) ++ "█" ++ RESET);
    //     d_print("{s}|{s}", .{ Color.colorRGB(allocator, rgb[0], rgb[1], rgb[2]), RESET });
    // }

    // // Game-like color demonstration
    // setCursor(19, 1);
    // print("Game colors in action:");

    // setCursor(20, 1);
    // // Health bar
    // print("Health: [");
    // i = 0;
    // while (i < 10) : (i += 1) {
    //     if (i < 7) {
    //         // print(Color.colorRGB(allocator, 255, 0, 0) ++ "█" ++ RESET);
    //         d_print("{s}|{s}", .{ Color.colorRGB(allocator, 255, 0, 0), RESET });
    //     } else {
    //         // print(Color.colorRGB(allocator, 64, 64, 64) ++ "█" ++ RESET);
    //         d_print("{s}|{s}", .{ Color.colorRGB(allocator, 64, 64, 64), RESET });
    //     }
    // }
    // print("] 70/100");

    // setCursor(21, 1);
    // // Mana bar
    // print("Mana:   [");
    // i = 0;
    // while (i < 10) : (i += 1) {
    //     if (i < 5) {
    //         // print(Color.colorRGB(allocator, 0, 0, 255) ++ "█" ++ RESET);
    //         d_print("{s}|{s}", .{ Color.colorRGB(allocator, 0, 0, 255), RESET });
    //     } else {
    //         // print(Color.colorRGB(allocator, 32, 32, 64) ++ "█" ++ RESET);
    //         d_print("{s}|{s}", .{ Color.colorRGB(allocator, 32, 32, 64), RESET });
    //     }
    // }
    // print("] 50/100");

    // setCursor(23, 1);
    // print("Different terrains:");
    // setCursor(24, 1);
    // // print(Color.colorRGB(allocator, 34, 139, 34) ++ "Forest" ++ RESET ++ "  ");
    // d_print("{s}{s}{s}", .{ Color.colorRGB(allocator, 34, 139, 34), "Forest", RESET });

    // // print(Color.colorRGB(allocator, 210, 180, 140) ++ "Desert" ++ RESET ++ "  ");
    // d_print("{s}{s}{s}", .{ Color.colorRGB(allocator, 34, 139, 34), "Desert", RESET });

    // // print(Color.colorRGB(allocator, 70, 130, 180) ++ "Water" ++ RESET ++ "  ");
    // d_print("{s}{s}{s}", .{ Color.colorRGB(allocator, 70, 130, 180), "Water", RESET });

    // // print(Color.colorRGB(allocator, 139, 69, 19) ++ "Mountain" ++ RESET);
    // d_print("{s}{s}{s}", .{ Color.colorRGB(allocator, 139, 69, 19), "Mountain", RESET });

    setCursor(26, 1);
    print(SHOW_CURSOR);
}

// HSV to RGB conversion for rainbow effects
fn hsvToRgb(h: f32, s: f32, v: f32) [3]u8 {
    const c = v * s;
    const x = c * (1 - @abs(@mod(h / 60.0, 2.0) - 1));
    const m = v - c;

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    if (h < 60) {
        r = c;
        g = x;
        b = 0;
    } else if (h < 120) {
        r = x;
        g = c;
        b = 0;
    } else if (h < 180) {
        r = 0;
        g = c;
        b = x;
    } else if (h < 240) {
        r = 0;
        g = x;
        b = c;
    } else if (h < 300) {
        r = x;
        g = 0;
        b = c;
    } else {
        r = c;
        g = 0;
        b = x;
    }

    return [3]u8{
        @as(u8, @intFromFloat((r + m) * 255)),
        @as(u8, @intFromFloat((g + m) * 255)),
        @as(u8, @intFromFloat((b + m) * 255)),
    };
}

const std = @import("std");
const builtin = @import("builtin");

// ANSI Constants: We define escape sequences as compile-time string constants. The CSI (Control Sequence Introducer) \x1B[ is the start of most ANSI commands.
// Cursor Control: setCursor(row, col) uses the H command to position the cursor anywhere on screen. This is crucial for building our game world.
// Color System: We're using 4-bit colors (the original 16-color terminal palette). Each color has a foreground (31m for red) and background variant (41m for red background).
