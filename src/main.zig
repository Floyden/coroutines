const std = @import("std");
const co = @import("coroutine.zig");

pub fn test_fn1(_str: *anyopaque) callconv(.C) void {
    // const val: *usize = @as(**usize, @alignCast(@ptrCast(_str))).*;
    const val: [*:0]const u8 = @as(*[*:0]const u8, @alignCast(@ptrCast(_str))).*;
    for (0..5) |_| {
        std.debug.print("[{}]Hi: {s}\n", .{ co.currentId(), val });
        co.yield();
    }
}

pub fn test_fn2(i: *usize) callconv(.C) void {
    for (0..i.*) |value| {
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
    // bench();
    co.create(test_fn1, .{"Hello World"});
    co.create(test_fn2, .{@as(usize, 10)});
    // while (co.numRoutines() > 2) co.yield();
    // co.create(test_fn1, @ptrFromInt(5));
    while (co.numRoutines() > 1) co.yield();
    // std.debug.print("Result {}\n", .{i});
}
