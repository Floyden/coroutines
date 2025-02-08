const std = @import("std");

comptime {
    @export(__co_yield, .{ .name = "yield", .linkage = .strong });
    @export(__co_restore, .{ .name = "co_restore", .linkage = .strong });
    @export(__co_switch, .{ .name = "co_switch", .linkage = .strong });
}

const Context = struct {
    rsp: *anyopaque,
    base: []u8,
};

pub var CONTEXTS = std.ArrayList(Context).init(std.heap.page_allocator);
pub var CONTEXT_CURRENT: usize = 0;
pub const PAGE_SIZE = 4 * 1024;

pub fn init() callconv(.C) void {
    CONTEXTS.append(.{ .rsp = undefined, .base = undefined }) catch @panic("Buy more RAM");
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
    CONTEXTS.items[CONTEXT_CURRENT].rsp = rsp;
    CONTEXT_CURRENT = (CONTEXT_CURRENT + 1) % CONTEXTS.items.len;
    co_restore(CONTEXTS.items[CONTEXT_CURRENT].rsp);
}

pub fn finish() callconv(.C) void {
    // TODO: Tf why is the stack not aligned
    asm volatile ("sub $0x8, %rsp");
    if (CONTEXT_CURRENT == 0) {
        CONTEXTS.clearRetainingCapacity();
        return;
    }

    _ = CONTEXTS.swapRemove(CONTEXT_CURRENT);
    CONTEXT_CURRENT %= CONTEXTS.items.len;
    co_restore(CONTEXTS.items[CONTEXT_CURRENT].rsp);
}

pub fn create(f: *const fn (usize) void, arg: *anyopaque) void {
    const base: []u8 = std.heap.page_allocator.alloc(u8, PAGE_SIZE) catch @panic("OOM");
    @memset(base, 0);
    var rsp: *usize = @ptrFromInt(@intFromPtr(base.ptr) + base.len);
    rsp = @ptrFromInt(@intFromPtr(rsp) - @sizeOf(usize));
    rsp.* = @intFromPtr(&finish);
    rsp = @ptrFromInt(@intFromPtr(rsp) - @sizeOf(usize));
    rsp.* = @intFromPtr(f);
    rsp = @ptrFromInt(@intFromPtr(rsp) - @sizeOf(usize));
    rsp.* = @intFromPtr(arg); // push rdi
    inline for (0..6) |_| {
        // push rbx, rbp, r12-r15
        rsp = @ptrFromInt(@intFromPtr(rsp) - @sizeOf(usize));
        rsp.* = 0;
    }
    CONTEXTS.append(.{ .rsp = rsp, .base = base }) catch @panic("OOM");
}

pub extern fn yield() callconv(.C) void;
extern fn co_restore(rsp: *anyopaque) callconv(.C) void;
extern fn co_return() callconv(.C) void;
