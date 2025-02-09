const std = @import("std");

// Reexport functions to make it callable in a zig context
comptime {
    @export(__co_yield, .{ .name = "yield", .linkage = .strong });
    @export(__co_restore, .{ .name = "co_restore", .linkage = .strong });
    @export(__co_switch, .{ .name = "co_switch", .linkage = .strong });
}

pub extern fn yield() callconv(.C) void;
extern fn co_return() callconv(.C) void;
extern fn co_restore(rsp: *anyopaque) callconv(.C) void;

const Context = struct {
    rsp: *anyopaque,
    base: []u8,
};

const allocator: std.mem.Allocator = std.heap.page_allocator;
var contexts = std.ArrayList(Context).init(allocator);
var current: usize = 0;

pub const PAGE_SIZE = 4 * 1024;

pub fn init() callconv(.C) void {
    contexts.append(.{ .rsp = undefined, .base = undefined }) catch @panic("Buy more RAM");
}

pub fn create(f: *const anyopaque, ctx: *const anyopaque) void {
    const base: []u8 = std.heap.page_allocator.alloc(u8, PAGE_SIZE) catch @panic("OOM");
    @memset(base, 0);
    var rsp: *usize = @ptrFromInt(@intFromPtr(base.ptr) + base.len);
    // TODO: In zig 0.14 we can clean up the pointer arithmetic
    rsp = @ptrFromInt(@intFromPtr(rsp) - @sizeOf(usize));
    rsp.* = @intFromPtr(&finish);
    rsp = @ptrFromInt(@intFromPtr(rsp) - @sizeOf(usize));
    rsp.* = @intFromPtr(f);
    rsp = @ptrFromInt(@intFromPtr(rsp) - @sizeOf(usize));
    rsp.* = @intFromPtr(ctx); // push rdi
    inline for (0..6) |_| {
        // push rbx, rbp, r12-r15
        rsp = @ptrFromInt(@intFromPtr(rsp) - @sizeOf(usize));
        rsp.* = 0;
    }
    contexts.append(.{ .rsp = rsp, .base = base }) catch @panic("OOM");
}

pub fn finish() callconv(.C) void {
    // TODO: Tf why is the stack not aligned
    asm volatile ("sub $0x8, %rsp");
    if (current == 0) {
        contexts.clearRetainingCapacity();
        return;
    }

    _ = contexts.swapRemove(current);
    current %= contexts.items.len;
    co_restore(contexts.items[current].rsp);
}

noinline fn __co_yield() callconv(.Naked) void {
    asm volatile (
        \\    pushq %rdi
        \\    pushq %rbp
        \\    pushq %rbx
        \\    pushq %r12
        \\    pushq %r13
        \\    pushq %r14
        \\    pushq %r15
        \\    movq %rsp, %rdi
        \\    jmp co_switch 
        ::: "memory");
}

noinline fn __co_restore(rsp: *anyopaque) callconv(.Naked) void {
    _ = rsp;
    asm volatile (
        \\    movq %rdi, %rsp
        \\    popq %r15
        \\    popq %r14
        \\    popq %r13
        \\    popq %r12
        \\    popq %rbx
        \\    popq %rbp
        \\    popq %rdi
        \\    ret
        ::: "memory");
}

fn __co_switch(rsp: *anyopaque) callconv(.C) void {
    contexts.items[current].rsp = rsp;
    current = (current + 1) % contexts.items.len;
    co_restore(contexts.items[current].rsp);
}

pub fn num_routines() usize {
    return contexts.items.len;
}

pub noinline fn __printStack() void {
    const diff = @intFromPtr(contexts.items[current].rsp) - @intFromPtr(contexts.items[current].base.ptr);
    const stack: *[PAGE_SIZE / 8]usize = @ptrCast(@alignCast(contexts.items[current].base.ptr));

    std.debug.print("{}: {any}\n {x}\n", .{
        current,
        contexts.items[current].rsp,
        stack[@divFloor(diff, 8) + 7 ..],
    });
}
