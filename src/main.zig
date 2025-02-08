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

pub fn yeet(i: usize) void {
    for (0..i) |value| {
        std.debug.print("Hi1: {}\n", .{value});
        co.yield();
    }
}

pub fn main() !void {
    co.init();
    co.create(yeet, @ptrFromInt(5));
    co.create(yeet, @ptrFromInt(10));
    while (co.CONTEXTS.items.len > 1) co.yield();
}
