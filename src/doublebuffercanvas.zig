const ESC = "\x1B";
const CSI = ESC ++ "[";
const CLEAR_SCREEN = CSI ++ "2J";
const CURSOR_HOME = CSI ++ "H";
const HIDE_CURSOR = CSI ++ "?25l";
const SHOW_CURSOR = CSI ++ "?25h";

// Core cell structure - what gets stored in each screen position
const Cell = struct {
    character: u8,
    fg_color: Color,
    bg_color: Color,
    dirty: bool, // Has this cell changed since last render?

    const Color = struct {
        r: u8,
        g: u8,
        b: u8,

        pub fn equals(self: Color, other: Color) bool {
            return self.r == other.r and self.g == other.g and self.b == other.b;
        }

        pub const BLACK = Color{ .r = 0, .g = 0, .b = 0 };
        pub const WHITE = Color{ .r = 255, .g = 255, .b = 255 };
        pub const RED = Color{ .r = 255, .g = 0, .b = 0 };
        pub const GREEN = Color{ .r = 0, .g = 255, .b = 0 };
        pub const BLUE = Color{ .r = 0, .g = 0, .b = 255 };
        pub const YELLOW = Color{ .r = 255, .g = 255, .b = 0 };
        pub const CYAN = Color{ .r = 0, .g = 255, .b = 255 };
        pub const MAGENTA = Color{ .r = 255, .g = 0, .b = 255 };
    };

    pub fn init(character: u8, fg: Color, bg: Color) Cell {
        return Cell{
            .character = character,
            .fg_color = fg,
            .bg_color = bg,
            .dirty = true,
        };
    }

    pub fn equals(self: Cell, other: Cell) bool {
        return self.character == other.character and
            self.fg_color.equals(other.fg_color) and
            self.bg_color.equals(other.bg_color);
    }

    pub fn clear() Cell {
        return Cell{
            .character = ' ',
            .fg_color = Color.WHITE,
            .bg_color = Color.BLACK,
            .dirty = true,
        };
    }
};

// Rectangle for dirty region tracking
const Rect = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,

    pub fn init(x: i32, y: i32, width: i32, height: i32) Rect {
        return Rect{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn contains(self: Rect, x: i32, y: i32) bool {
        return x >= self.x and x < self.x + self.width and
            y >= self.y and y < self.y + self.height;
    }

    pub fn intersects(self: Rect, other: Rect) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }

    pub fn union_(self: Rect, other: Rect) Rect {
        const min_x = @min(self.x, other.x);
        const min_y = @min(self.y, other.y);
        const max_x = @max(self.x + self.width, other.x + other.width);
        const max_y = @max(self.y + self.height, other.y + other.height);

        return Rect{
            .x = min_x,
            .y = min_y,
            .width = max_x - min_x,
            .height = max_y - min_y,
        };
    }
};

const Canvas = struct {
    const Self = @This();

    width: usize,
    height: usize,

    // Double buffers
    front_buffer: []Cell, // displayed
    back_buffer: []Cell, // draw too

    // Dirty region tracking
    dirty_regions: std.ArrayList(Rect),
    full_redraw: bool,

    // Optimization state
    last_fg_color: Cell.Color,
    last_bg_color: Cell.Color,
    last_cursor_x: usize,
    last_cursor_y: usize,

    allocator: Allocator,

    pub fn Init(allocator: Allocator, width: usize, height: usize) !Self {
        const buffer_size = width * height;

        const front_buffer = try allocator.alloc(Cell, buffer_size);
        const back_buffer = try allocator.alloc(Cell, buffer_size);

        // Initialize with empty cells
        for (front_buffer) |*cell| {
            cell.* = Cell.clear();
        }
        for (back_buffer) |*cell| {
            cell.* = Cell.clear();
        }

        return Self{
            .width = width,
            .front_buffer = front_buffer,
            .back_buffer = back_buffer,
            .dirty_regions = std.ArrayList(Rect).init(allocator),
            .full_redraw = true,
            .last_fg_color = Cell.Color.WHITE,
            .last_bg_color = Cell.Color.BLACK,
            .last_cursor_x = 0,
            .last_cursor_y = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.front_buffer);
        self.allocator.free(self.back_buffer);
        self.dirty_regions.deinit();
    }

    // Get cell at position (bounds checked)
    pub fn getCell(self: *Self, x: i32, y: i32) ?*Cell {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) return null;
        const index = @as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x)); // buffer is single linear array
        return &self.back_buffer[index];
    }

    // Set cell and mark as dirty
    pub fn setCell(self: *Self, x: i32, y: i32, cell: Cell) void {
        if (self.getCell(x, y)) |target_cell| {
            if (!target_cell.equals(cell)) {
                target_cell.* = cell;
                target_cell.dirty = true;
                self.markDirty(x, y, 1, 1);
            }
        }
    }

    // Draw character with colors
    pub fn drawChar(self: *Self, x: i32, y: i32, character: u8, fg: Cell.Color, bg: Cell.Color) void {
        self.setCell(x, y, Cell.init(character, fg, bg));
    }

    // Draw string horizontally
    pub fn drawString(self: *Self, x: i32, y: i32, text: []const u8, fg: Cell.Color, bg: Cell.Color) void {
        for (text, 0..) |char, i| {
            self.drawChar(x + @as(i32, @intCast(i)), y, char, fg, bg);
        }
    }

    // Clear entire screen
    pub fn clear(self: *Self, bg: Cell.Color) void {
        for (self.back_buffer) |*cell| {
            const new_cell = Cell{
                .character = ' ',
                .fg_color = Cell.Color.WHITE,
                .bg_color = bg,
                .dirty = true,
            };

            if (!cell.equals(new_cell)) {
                cell.* = new_cell;
            }
        }
        self.full_redraw = true;
    }

    // Mark region as dirty
    pub fn markDirty(self: *Self, x: i32, y: i32, width: i32, height: i32) void {
        const rect = Rect.init(x, y, width, height);
        self.dirty_regions.append(rect) catch return; // Graceful degradation
    }

        // Optimize dirty regions by merging overlapping ones(understand this, merge overlapping dirty regions into one)
    fn optimizeDirtyRegions(self: *Self) void {
        if (self.dirty_regions.items.len <= 1) return;
        
        var i: usize = 0;
        while (i < self.dirty_regions.items.len) {
            var j: usize = i + 1;
            while (j < self.dirty_regions.items.len) {
                if (self.dirty_regions.items[i].intersects(self.dirty_regions.items[j])) {
                    // Merge rectangles
                    self.dirty_regions.items[i] = self.dirty_regions.items[i].union(self.dirty_regions.items[j]);
                    // Remove the merged one
                    _ = self.dirty_regions.swapRemove(j);
                } else {
                    j += 1;
                }
            }
            i += 1;
        }
    }

     // Present the back buffer to screen (the magic happens here!)
    pub fn present(self: *Self) void {
        // we go full redraw when we cleared the entire screen(back buffer)
        if (self.full_redraw) {
            self.presentFullScreen();
            self.full_redraw = false;
        } else {
            self.presentDirtyRegions();
        }
        
        // Swap buffers
        const temp = self.front_buffer;
        self.front_buffer = self.back_buffer;
        self.back_buffer = temp;
        
        // Clear dirty regions for next frame
        self.dirty_regions.clearRetainingCapacity();
        
        // Mark all cells as clean
        for (self.back_buffer) |*cell| {
            cell.dirty = false;
        }
    }


    fn presentFullScreen(self: *Self) void {
        print(HIDE_CURSOR ++ CLEAR_SCREEN ++ CURSOR_HOME);
        
        var output_buffer = std.ArrayList(u8).init(self.allocator);
        defer output_buffer.deinit();
        
        // Pre-allocate reasonable buffer size
        output_buffer.ensureTotalCapacity(self.width * self.height * 20) catch return;
        
        var current_fg = Cell.Color{ .r = 255, .g = 255, .b = 255 };
        var current_bg = Cell.Color{ .r = 0, .g = 0, .b = 0 };
        
        for (0..self.height) |y| {
            // Move cursor to start of line
            const cursor_seq = std.fmt.allocPrint(self.allocator, CSI ++ "{};1H", .{y + 1}) catch continue;
            defer self.allocator.free(cursor_seq);
            output_buffer.appendSlice(cursor_seq) catch continue;
            
            for (0..self.width) |x| {
                const cell = &self.back_buffer[y * self.width + x]; // pull from back buffer
                
                // Update colors only when they change
                if (!current_fg.equals(cell.fg_color)) {
                    const fg_seq = std.fmt.allocPrint(self.allocator, CSI ++ "38;2;{};{};{}m", 
                                                    .{cell.fg_color.r, cell.fg_color.g, cell.fg_color.b}) catch continue;
                    defer self.allocator.free(fg_seq);
                    output_buffer.appendSlice(fg_seq) catch continue;
                    current_fg = cell.fg_color;
                }
                
                if (!current_bg.equals(cell.bg_color)) {
                    const bg_seq = std.fmt.allocPrint(self.allocator, CSI ++ "48;2;{};{};{}m", 
                                                    .{cell.bg_color.r, cell.bg_color.g, cell.bg_color.b}) catch continue;
                    defer self.allocator.free(bg_seq);
                    output_buffer.appendSlice(bg_seq) catch continue;
                    current_bg = cell.bg_color;
                }
                
                output_buffer.append(cell.character) catch continue;
            }
        }
        
        // Output everything at once
        d_print("{s}", .{output_buffer.items});
    }

     fn presentDirtyRegions(self: *Self) void {
        self.optimizeDirtyRegions();
        
        print(HIDE_CURSOR);
        
        for (self.dirty_regions.items) |region| {
            self.presentRegion(region);
        }
    }

        fn presentRegion(self: *Self, region: Rect) void {
        const start_y = @max(0, region.y);
        const end_y = @min(@as(i32, @intCast(self.height)), region.y + region.height);
        const start_x = @max(0, region.x);
        const end_x = @min(@as(i32, @intCast(self.width)), region.x + region.width);
        
        for (@as(usize, @intCast(start_y))..@as(usize, @intCast(end_y))) |y| {
            // Move cursor to start of dirty line section
            d_print(CSI ++ "{};{}H", .{ y + 1, start_x + 1 });
            
            var current_fg = self.last_fg_color;
            var current_bg = self.last_bg_color;
            
            for (@as(usize, @intCast(start_x))..@as(usize, @intCast(end_x))) |x| {
                const cell = &self.back_buffer[y * self.width + x];
                const front_cell = &self.front_buffer[y * self.width + x];
                
                // Only update if cell actually changed
                if (!cell.equals(front_cell.*)) {
                    // Update colors only when needed
                    if (!current_fg.equals(cell.fg_color)) {
                        print(CSI ++ "38;2;{};{};{}m", .{cell.fg_color.r, cell.fg_color.g, cell.fg_color.b});
                        current_fg = cell.fg_color;
                    }
                    
                    if (!current_bg.equals(cell.bg_color)) {
                        print(CSI ++ "48;2;{};{};{}m", .{cell.bg_color.r, cell.bg_color.g, cell.bg_color.b});
                        current_bg = cell.bg_color;
                    }
                    
                    print("{c}", .{cell.character});
                } else {
                    // Skip unchanged cell but advance cursor
                    print(CSI ++ "C"); // Move cursor right one position
                }
            }
        }
        
        self.last_fg_color = current_fg;
        self.last_bg_color = current_bg;
    }

};

pub fn demoCanvas() !void {
    print("=== Double-Buffered Canvas Demo ===\n\n");
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create 80x24 canvas (standard terminal size)
    var canvas = try Canvas.init(allocator, 80, 24);
    defer canvas.deinit();
    
    print("Canvas created: {}x{} = {} cells\n", .{ canvas.width, canvas.height, canvas.width * canvas.height });
    print("Memory usage: {} bytes per buffer, {} total\n", 
          .{ canvas.width * canvas.height * @sizeOf(Cell), canvas.width * canvas.height * @sizeOf(Cell) * 2 });
    
    // Clear with dark blue background
    canvas.clear(Cell.Color{ .r = 0, .g = 0, .b = 64 });
    
    // Draw a border
    for (0..canvas.width) |x| {
        canvas.drawChar(@intCast(x), 0, '#', Cell.Color.GREEN, Cell.Color.BLACK);
        canvas.drawChar(@intCast(x), @intCast(canvas.height - 1), '#', Cell.Color.GREEN, Cell.Color.BLACK);
    }
    
    for (0..canvas.height) |y| {
        canvas.drawChar(0, @intCast(y), '#', Cell.Color.GREEN, Cell.Color.BLACK);
        canvas.drawChar(@intCast(canvas.width - 1), @intCast(y), '#', Cell.Color.GREEN, Cell.Color.BLACK);
    }
    
    // Draw some text
    canvas.drawString(2, 2, "DOUBLE-BUFFERED CANVAS DEMO", Cell.Color.WHITE, Cell.Color.BLACK);
    canvas.drawString(2, 4, "No flicker!", Cell.Color.YELLOW, Cell.Color.BLACK);
    canvas.drawString(2, 5, "Optimized updates!", Cell.Color.CYAN, Cell.Color.BLACK);
    
    // Draw colored squares
    const colors = [_]Cell.Color{
        Cell.Color.RED, Cell.Color.GREEN, Cell.Color.BLUE,
        Cell.Color.YELLOW, Cell.Color.CYAN, Cell.Color.MAGENTA,
    };
    
    for (colors, 0..) |color, i| {
        const x = @as(i32, @intCast(i * 4 + 10));
        const y = 8;
        
        canvas.drawChar(x, y, '█', color, Cell.Color.BLACK);
        canvas.drawChar(x, y + 1, '█', color, Cell.Color.BLACK);
    }
    
    print("\nPress Enter to see the rendered output...\n");
    _ = std.io.getStdIn().reader().readByte() catch {};
    
    // Present to screen
    canvas.present();
    
    print(SHOW_CURSOR);
    print(CSI ++ "25;1H"); // Move cursor below our canvas
    print("\nRendering complete! Canvas features:\n");
    print("✓ Double buffering (no flicker)\n");
    print("✓ Dirty region tracking (performance)\n");
    print("✓ Color optimization (minimal ANSI codes)\n");
    print("✓ Bounds checking (no crashes)\n");
    print("✓ Memory efficient (reusable buffers)\n");
}

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const d_print = std.debug.print;

fn print(s: []const u8) void {
    d_print("{s}", .{s});
}
