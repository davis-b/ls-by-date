const std = @import("std");
const os = std.os;

const utils = @import("utils.zig");
// Shorthand for comparing a [*:0] to a []const u8
const eql = utils.eql;
const print = utils.print;
// Changes terminal output color by printing an escape sequence to stderr.
const setColor = utils.setColor;

const Files = std.ArrayList(File);
const File = struct {
    time: i128,
    name: []const u8,
    kind: std.fs.Dir.Entry.Kind,
};

const Args = struct {
    dir: []const u8 = "./",
    reverse: bool = false,
    recursive: bool = false,
    verbose: bool = false,
};

pub fn main() !void {
    const args = parseArgs(os.argv[1..os.argv.len]) orelse os.exit(2);

    var gp = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gp.allocator;
    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();
    const arena = &arena_allocator.allocator;

    var files = Files.init(arena);

    const fd = try os.open(args.dir, 0, os.O_RDONLY);
    defer os.close(fd);
    try searchDir(arena, args, fd, null, &files);

    if (args.verbose) {
        std.debug.warn("found {} files\n", .{files.items.len});
    }
    utils.insertionSort(File, files.items);
    if (args.reverse) {
        std.mem.reverse(File, files.items);
    }
    for (files.items) |file| {
        switch (file.kind) {
            .Directory => {
                setColor(.red);
                print("{}", .{file.name});
                setColor(.default);
                print("\n", .{});
            },
            .SymLink => {
                setColor(.green);
                print("{}", .{file.name});
                setColor(.default);
                print("\n", .{});
            },
            .File => {
                print("{}\n", .{file.name});
            },
            else => @panic("unexpected file type!"),
        }
    }
}

fn searchDir(allocator: *std.mem.Allocator, args: Args, fd: os.fd_t, prefix: ?[]const u8, files: *Files) anyerror!void {
    var dir = std.fs.Dir{ .fd = fd };
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .File, .Directory, .SymLink => {
                const file = dir.openFile(entry.name, .{}) catch |err| switch (err) {
                    error.AccessDenied => continue,
                    else => return err,
                };
                defer file.close();
                const stat = try file.stat();
                const time = stat.mtime;

                var fname = blk: {
                    if (prefix) |p| {
                        break :blk try std.mem.join(allocator, "/", &[_][]const u8{ p, entry.name });
                    } else {
                        var fname = try allocator.alloc(u8, entry.name.len);
                        std.mem.copy(u8, fname, entry.name);
                        break :blk fname;
                    }
                };

                const f = File{
                    .time = time,
                    .name = fname,
                    .kind = entry.kind,
                };
                try files.append(f);

                if (args.recursive and entry.kind == .Directory) {
                    try searchDir(allocator, args, file.handle, fname, files);
                }
            },
            else => {},
        }
    }
}

fn usage() void {
    print("Program prints files in directory, sorted by last modification time\n", .{});
    print("{} [-r -R -v] directory\n", .{os.argv[0]});
    print("-r to print in reversed order", .{});
    print("-R for recursive searching\n", .{});
    print("-v for verbose output\n", .{});
}

fn parseArgs(argv: [][*:0]u8) ?Args {
    var args = Args{};
    for (argv) |i| {
        if (eql(i, "-h") or eql(i, "--h") or eql(i, "-?") or eql(i, "--?") or eql(i, "-help") or eql(i, "--help")) {
            usage();
            return null;
        } else if (eql(i, "-r")) {
            args.reverse = true;
        } else if (eql(i, "-R")) {
            args.recursive = true;
        } else if (eql(i, "-v")) {
            args.verbose = true;
        } else {
            args.dir = std.mem.spanZ(i);
        }
    }
    return args;
}
