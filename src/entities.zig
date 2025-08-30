const Entity = struct {
    x: f32,
    y: f32,
    health: i32,
    entity_type: EntityType,

    const EntityType = enum {
        Player,
        Monster,
        Item,
        Projectile,
    };

    pub fn init(x: f32, y: f32, entity_type: EntityType) Entity {
        return Entity{
            .x = x,
            .y = y,
            .health = switch (entity_type) {
                .Player => 100,
                .Monster => 50,
                .Item => 1,
                .Projectile => 1,
            },
            .entity_type = entity_type,
        };
    }

    pub fn update(self: *Entity) void {
        // Simple movement simulation
        switch (self.entity_type) {
            .Monster => {
                self.x += 0.1;
                self.y += 0.05;
            },
            .Projectile => {
                self.x += 1.0;
            },
            else => {},
        }
    }
};

const EntityPool = struct {
    const Self = @This();

    const POOL_SIZE = 1000;

    entities: [POOL_SIZE]Entity,
    free_list: [POOL_SIZE]bool, // true = free, false = used
    next_free: usize,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !Self {
        return Self{
            .entities = std.mem.zeroes([POOL_SIZE]Entity),
            .free_list = [_]bool{true} ** POOL_SIZE,
            .next_free = 0,
            .allocator = allocator,
        };
    }

    pub fn allocateEntity(self: *Self, x: f32, y: f32, entity_type: Entity.EntityType) ?*Entity {
        // Find next free slot
        var i = self.next_free;
        var attempts: usize = 0;

        while (attempts < POOL_SIZE) {
            if (self.free_list[i]) {
                self.free_list[i] = false;
                self.entities[i] = Entity.init(x, y, entity_type);
                self.next_free = (i + 1) % POOL_SIZE;
                return &self.entities[i];
            }
            i = (i + 1) % POOL_SIZE;
            attempts += 1;
        }

        return null; // Pool exhausted
    }

    pub fn deallocateEntity(self: *Self, entity: *Entity) void {
        // Calculate index from pointer
        const base_addr = @intFromPtr(&self.entities[0]);
        const entity_addr = @intFromPtr(entity);
        const index = (entity_addr - base_addr) / @sizeOf(Entity);

        if (index < POOL_SIZE) {
            self.free_list[index] = true;
        }
    }

    pub fn getActiveEntities(self: *Self) []Entity {
        var active = std.ArrayList(Entity).init(self.allocator);
        defer active.deinit();

        for (self.entities, 0..) |entity, i| {
            if (!self.free_list[i]) {
                active.append(entity) catch continue;
            }
        }

        return active.toOwnedSlice() catch &[_]Entity{};
    }
};

// why some allocs are faster: https://chatgpt.com/c/68b2e0e2-5f40-832c-800c-54c3668642dd firefox
// summary https://chat.deepseek.com/a/chat/s/2ffe14a0-cc00-444e-9d67-6301d4bd4716
// Demonstrate different allocator types
pub fn demonstrateAllocators() !void {
    print("=== Allocator Demonstration ===\n\n");

    // 1. General Purpose Allocator (uses system malloc)
    print("1. General Purpose Allocator:\n");
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gp_allocator = gpa.allocator();

    // Allocate dynamic array
    var entities = std.ArrayList(Entity).init(gp_allocator);
    defer entities.deinit();

    try entities.append(Entity.init(10.0, 20.0, .Player));
    try entities.append(Entity.init(15.0, 25.0, .Monster));

    d_print("  Allocated {} entities with GPA\n", .{entities.items.len});

    // 2. Arena Allocator (fast allocation, all freed at once)
    print("\n2. Arena Allocator:\n");
    var arena = std.heap.ArenaAllocator.init(gp_allocator);
    defer arena.deinit(); // Frees ALL arena memory at once
    const arena_allocator = arena.allocator();

    // Allocate many small objects - very fast!
    const projectiles = try arena_allocator.alloc(Entity, 100);
    for (projectiles, 0..) |*projectile, i| {
        projectile.* = Entity.init(@floatFromInt(i), @floatFromInt(i * 2), .Projectile);
    }
    d_print("  Allocated {} projectiles with Arena (very fast!)\n", .{projectiles.len});

    // 3. Fixed Buffer Allocator (stack-allocated, no heap)
    print("\n3. Fixed Buffer Allocator:\n");
    var buffer: [8192]u8 = undefined; // 8KB stack buffer
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const fixed_allocator = fba.allocator();

    const items = try fixed_allocator.alloc(Entity, 50);
    for (items, 0..) |*item, i| {
        item.* = Entity.init(@floatFromInt(i * 3), @floatFromInt(i * 4), .Item);
    }
    d_print("  Allocated {} items with Fixed Buffer (no heap allocation!)\n", .{items.len});

    // 4. Custom Entity Pool
    print("\n4. Custom Entity Pool:\n");
    var entity_pool = try EntityPool.init(gp_allocator);

    // Allocate entities very fast
    const player = entity_pool.allocateEntity(0, 0, .Player) orelse return;
    const monster1 = entity_pool.allocateEntity(10, 10, .Monster) orelse return;
    const monster2 = entity_pool.allocateEntity(20, 20, .Monster) orelse return;

    print("  Allocated 3 entities from pool\n");

    // Update them
    player.update();
    monster1.update();
    monster2.update();

    d_print("  Player: ({d:.1}, {d:.1})\n", .{ player.x, player.y });
    d_print("  Monster1: ({d:.1}, {d:.1})\n", .{ monster1.x, monster1.y });

    // Free one
    entity_pool.deallocateEntity(monster1);
    print("  Deallocated monster1\n");

    // Reallocate - should reuse slot
    const new_monster = entity_pool.allocateEntity(5, 5, .Monster) orelse return;
    d_print("  Allocated new monster: ({d:.1}, {d:.1})\n", .{ new_monster.x, new_monster.y });

    print("\n=== Memory Management Best Practices ===\n");
    print("• Use Arena for temporary allocations (level loading, UI)\n");
    print("• Use Fixed Buffer for predictable, bounded allocations\n");
    print("• Use Object Pools for frequently allocated/freed objects\n");
    print("• Use GPA for long-lived, variable-size data\n");
    print("• Always match allocations with deallocations\n");
    print("• Prefer stack allocation when possible\n");
}

// Error handling patterns - crucial for robust games
const GameError = error{
    OutOfMemory,
    InvalidPosition,
    EntityNotFound,
    SaveFileCorrupted,
    NetworkTimeout,
};

const GameResult = union(enum) {
    Success: void,
    Warning: []const u8,
    Error: GameError,

    pub fn isOk(self: GameResult) bool {
        return switch (self) {
            .Success => true,
            .Warning => true,
            .Error => false,
        };
    }
};

fn moveEntity(entity: *Entity, dx: f32, dy: f32) GameError!GameResult {
    const new_x = entity.x + dx;
    const new_y = entity.y + dy;

    // Validate bounds
    if (new_x < 0 or new_x > 100 or new_y < 0 or new_y > 100) {
        return GameError.InvalidPosition;
    }

    // Check for edge case
    if (new_x > 90 or new_y > 90) {
        entity.x = new_x;
        entity.y = new_y;
        return GameResult{ .Warning = "Near boundary!" };
    }

    entity.x = new_x;
    entity.y = new_y;
    return GameResult{ .Success = {} };
}

pub fn demonstrateErrorHandling() !void {
    print("\n=== Error Handling Patterns ===\n\n");

    var entity = Entity.init(50, 50, .Player);

    // Pattern 1: Try and handle specific errors
    if (moveEntity(&entity, 10, 10)) |result| {
        switch (result) {
            .Success => print("✓ Move successful\n"),
            .Warning => |msg| d_print("⚠ Move successful but: {s}\n", .{msg}),
            .Error => unreachable, // We know this won't happen due to the if
        }
    } else |err| {
        switch (err) {
            GameError.InvalidPosition => print("✗ Cannot move there!\n"),
            else => d_print("✗ Unexpected error: {}\n", .{err}),
        }
    }

    // Pattern 2: Try with default
    const move_result = moveEntity(&entity, 100, 100) catch GameResult{ .Error = GameError.InvalidPosition };
    if (!move_result.isOk()) {
        print("✗ Move failed as expected\n");
    }

    // Pattern 3: Defer for cleanup (RAII pattern)
    var temp_entities = std.ArrayList(Entity).init(std.heap.page_allocator);
    defer temp_entities.deinit(); // Always called, even on error!

    // This might fail, but temp_entities will still be cleaned up
    try temp_entities.append(Entity.init(0, 0, .Monster));
    print("✓ Created temporary entity list (will be auto-cleaned)\n");
}

const std = @import("std");
const d_print = std.debug.print;

fn print(s: []const u8) void {
    d_print("{s}", .{s});
}

const Allocator = std.mem.Allocator;
