const std = @import("std");
const os = std.os;

const utils = @import("utils.zig");
// Shorthand for comparing a [*:0] to a []const u8
const eql = utils.eql;
const print = utils.print;

const Files = std.ArrayList(File);
const File = struct {
    time: i128,
    name: []const u8,
    kind: std.fs.Dir.Entry.Kind,
};

const TimeType = enum {
    /// Access time
    atime,
    /// Creation time
    ctime,
    /// Modification time
    mtime,
};

const Args = struct {
    dir: []const u8 = "./",
    reverse: bool = false,
    recursive: bool = false,
    verbose: bool = false,
    time: TimeType = .mtime,
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

    if (!(try isDir(fd))) {
        std.debug.warn("{} is not a directory\n", .{args.dir});
        os.exit(1);
    }

    try searchDir(arena, args, fd, null, &files);

    if (args.verbose) {
        std.debug.warn("found {} files\n", .{files.items.len});
    }

    utils.insertionSort(File, files.items);
    if (args.reverse) {
        std.mem.reverse(File, files.items);
    }

    const use_colors = os.isatty(std.io.getStdOut().handle);
    const setColor = if (use_colors) utils.setColor else utils.noOpSetColor;
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
                    // Broken symbolic link, possibly more?
                    error.FileNotFound => continue,
                    else => return err,
                };
                defer file.close();
                const stat = try file.stat();
                const time = switch (args.time) {
                    .atime => stat.atime,
                    .ctime => stat.ctime,
                    .mtime => stat.mtime,
                };

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

fn isDir(fd: os.fd_t) !bool {
    const stat = try os.fstat(fd);
    return ((stat.mode & os.S_IFMT) == os.S_IFDIR);
}

fn usage() void {
    print("Program prints files in directory, sorted by last (access|creation|modification) time\n", .{});
    print("{} [options, with a space between each] directory\n", .{os.argv[0]});
    print("-r to print in reversed order", .{});
    print("-R for recursive searching\n", .{});
    print("-v for verbose output\n", .{});
    print("-[a, c, m]time to change which time metric files are sorted by\n", .{});
}

fn parseArgs(argv: [][*:0]u8) ?Args {
    var args = Args{};
    var stop_parsing_options: ?usize = null;
    for (argv) |i, index| {
        if (eql(i, "--")) {
            stop_parsing_options = index;
            break;
        }
        if (eql(i, "-h") or eql(i, "--h") or eql(i, "-?") or eql(i, "--?") or eql(i, "-help") or eql(i, "--help")) {
            usage();
            return null;
        } else if (eql(i, "-r")) {
            args.reverse = true;
        } else if (eql(i, "-R")) {
            args.recursive = true;
        } else if (eql(i, "-v")) {
            args.verbose = true;
        } else if (i[0] == '-' and std.meta.stringToEnum(TimeType, std.mem.spanZ(i)[1..]) != null) {
            args.time = std.meta.stringToEnum(TimeType, std.mem.spanZ(i)[1..]).?;
        } else {
            args.dir = std.mem.spanZ(i);
        }
    }
    if (stop_parsing_options) |index| {
        for (argv[index..argv.len]) |arg| {
            args.dir = std.mem.spanZ(arg);
        }
    }
    return args;
}
