const std = @import("std");
const co = @import("coroutine.zig");

pub fn test_fn1(_: *anyopaque) callconv(.C) void {
    for (0..5) |value| {
        std.debug.print("[{}]Hi: {}\n", .{ co.currentId(), value });
        co.yield();
    }
}

pub fn test_fn2(i: usize) callconv(.C) void {
    for (0..i) |value| {
        std.debug.print("[{}]Hi: {}\n", .{ co.currentId(), value });
        co.yield();
    }
}

var inc: usize = 0;
const LIMIT: usize = 100_000_000;
fn runner(_: *anyopaque) void {
    while (inc < LIMIT) {
        inc += 1;
        co.yield();
    }
}

fn bench() void {
    co.create(runner, @ptrFromInt(1));
    co.create(runner, @ptrFromInt(1));

    const start = std.time.milliTimestamp();
    while (co.numRoutines() > 1) {
        inc += 1;
        co.yield();
    }
    const end = std.time.milliTimestamp();
    std.debug.print("{}\n", .{end - start});
}

pub fn main() !void {
    co.init();
    bench();
    // co.create(test_fn1, @ptrFromInt(5));
    // co.create(test_fn2, @ptrFromInt(10));
    // while (co.numRoutines() > 2) co.yield();
    // co.create(test_fn1, @ptrFromInt(5));
    // while (co.numRoutines() > 1) co.yield();
}
