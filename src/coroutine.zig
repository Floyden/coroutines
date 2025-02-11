const std = @import("std");

// Reexport functions to make it callable in a zig context
comptime {
    @export(&__co_yield, .{ .name = "yield", .linkage = .strong });
    @export(&__co_restore, .{ .name = "co_restore", .linkage = .strong });
    @export(&__co_switch, .{ .name = "co_switch", .linkage = .strong });
}

pub extern fn yield() callconv(.C) void;
extern fn co_return() callconv(.C) void;
extern fn co_restore(rsp: *anyopaque) callconv(.C) void;

const Context = struct {
    rsp: [*]usize,
    base: []u8,
    id: usize,
};

const allocator: std.mem.Allocator = std.heap.page_allocator;
var contexts = std.ArrayList(Context).init(allocator);
var dead_contexts = std.ArrayList(Context).init(allocator);

var current: usize = 0;
var next_id: usize = 0;

pub const PAGE_SIZE = 4 * 1024;

pub fn init() callconv(.C) void {
    _ = createContext();
}

// TODO: Make it so that functions with multiple arguments also work
pub fn create(f: *const anyopaque, params: anytype) void {
    var ctx = createContext();

    inline for (params) |param| {
        const PType = @TypeOf(param);
        if (@sizeOf(PType) == 0) {
            continue;
        } else {
            ctx.rsp -= @sizeOf(PType) / @sizeOf(usize);
        }

        if (comptime @typeInfo(PType) == .pointer) {
            ctx.rsp[0] = @intFromPtr(param);
        } else {
            @as([*]PType, ctx.rsp)[0] = param;
        }
    }
    var offset: usize = 9;
    if (@intFromPtr(ctx.rsp) % 0x10 != 0) {
        ctx.rsp -= 1;
        offset += 1;
    ctx.rsp -= 9;
    ctx.rsp[8] = @intFromPtr(&finish);
    ctx.rsp[7] = @intFromPtr(f);
    ctx.rsp[6] = @intFromPtr(&ctx.rsp[offset]); // push rdi
    inline for (0..6) |i|
        // push rbx, rbp, r12-r15
        ctx.rsp[i] = 0;
}

pub fn finish() callconv(.C) void {
    // TODO: Tf why is the stack not aligned
    asm volatile ("sub $0x8, %rsp");
    if (current == 0) {
        contexts.clearRetainingCapacity();
        return;
    }

    const dead = contexts.swapRemove(current);
    current %= contexts.items.len;
    dead_contexts.append(dead) catch @panic("OOM");

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
    contexts.items[current].rsp = @alignCast(@ptrCast(rsp));
    current = (current + 1);
    if (current == contexts.items.len) current = 0;
    co_restore(contexts.items[current].rsp);
}

pub fn numRoutines() usize {
    return contexts.items.len;
}

pub fn currentId() callconv(.C) usize {
    return contexts.items[current].id;
}

pub noinline fn __printStack() void {
    const diff = @intFromPtr(contexts.items[current].rsp) - @intFromPtr(contexts.items[current].base.ptr);
    const stack: *[PAGE_SIZE / 8]usize = @ptrCast(@alignCast(contexts.items[current].base.ptr));

    std.debug.print("{}: {any}\n {x}\n", .{
        current,
        contexts.items[current].rsp,
        stack[@divFloor(diff, 8)..],
    });
}

fn createContext() *Context {
    var base: []u8 = undefined;
    var rsp: [*]usize = undefined;
    if (next_id != 0) {
        if (dead_contexts.items.len > 0) {
            base = dead_contexts.pop().base;
        } else {
            base = std.heap.page_allocator.alloc(u8, PAGE_SIZE) catch @panic("OOM");
        }
        rsp = @ptrFromInt(@intFromPtr(base.ptr) + base.len);
    }

    contexts.append(.{ .base = base, .rsp = rsp, .id = next_id }) catch @panic("OOM");
    next_id += 1;
    return &contexts.items[contexts.items.len - 1];
}
