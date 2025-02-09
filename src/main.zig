const std = @import("std");
const co = @import("coroutine.zig");

pub fn test_fn1() void {
    for (0..5) |value| {
        std.debug.print("[{}]Hi: {}\n", .{ co.currentId(), value });
        co.yield();
    }
}

pub fn test_fn2(i: usize) void {
    for (0..i) |value| {
        std.debug.print("[{}]Hi: {}\n", .{ co.currentId(), value });
        co.yield();
    }
}

pub fn main() !void {
    co.init();
    co.create(test_fn1, @ptrFromInt(5));
    co.create(test_fn2, @ptrFromInt(10));
    while (co.numRoutines() > 2) co.yield();
    co.create(test_fn1, @ptrFromInt(5));
    while (co.numRoutines() > 1) co.yield();
}
