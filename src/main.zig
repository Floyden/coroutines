const std = @import("std");
const co = @import("coroutine.zig");

pub noinline fn printStack() void {
    const diff = @intFromPtr(co.CONTEXTS.items[co.CONTEXT_CURRENT].rsp) - @intFromPtr(co.CONTEXTS.items[co.CONTEXT_CURRENT].base.ptr);
    const stack: *[co.PAGE_SIZE / 8]usize = @ptrCast(@alignCast(co.CONTEXTS.items[co.CONTEXT_CURRENT].base.ptr));

    std.debug.print("{}: {any}\n {x}\n", .{
        co.CONTEXT_CURRENT,
        co.CONTEXTS.items[co.CONTEXT_CURRENT].rsp,
        stack[@divFloor(diff, 8) + 0x13 + 7 ..],
    });
}

pub fn test_fn1(i: usize) void {
    for (0..i) |value| {
        std.debug.print("Hi 1: {}\n", .{value});
        co.yield();
    }
}

pub fn test_fn2(i: usize) void {
    for (0..i) |value| {
        std.debug.print("Hi 2: {}\n", .{value});
        co.yield();
    }
}

pub fn main() !void {
    co.init();
    co.create(test_fn1, @ptrFromInt(5));
    co.create(test_fn2, @ptrFromInt(10));
    while (co.CONTEXTS.items.len > 1) co.yield();
}
