const c = @cImport({
    @cInclude("vapoursynth/VapourSynth4.h");
});

const std = @import("std");
const math = std.math;
const process = @import("process.zig");
const sqrt_2Pi: f64 = math.sqrt(2.0 * math.pi);
const allocator = std.heap.c_allocator;

pub const ZbilateralData = struct {
    node1: ?*c.VSNode,
    node2: ?*c.VSNode,
    joint: bool,
    sigmaS: [3]f64,
    sigmaR: [3]f64,
    process: [3]bool,
    algorithm: [3]i32,
    PBFICnum: [3]u32,
    radius: [3]usize,
    samples: [3]usize,
    step: [3]usize,
    gr_lut: [3][]f32,
    gs_lut: [3][]f32,
    psize: u6,
    peak: f32,
};

export fn zbilateralGetFrame(n: c_int, activationReason: c_int, instanceData: ?*anyopaque, frameData: ?*?*anyopaque, frameCtx: ?*c.VSFrameContext, core: ?*c.VSCore, vsapi: ?*const c.VSAPI) callconv(.C) ?*const c.VSFrame {
    _ = frameData;
    var d: *ZbilateralData = @ptrCast(@alignCast(instanceData));

    if (activationReason == c.arInitial) {
        vsapi.?.requestFrameFilter.?(n, d.node1, frameCtx);
        if (d.joint) {
            vsapi.?.requestFrameFilter.?(n, d.node2, frameCtx);
        }
    } else if (activationReason == c.arAllFramesReady) {
        const src = vsapi.?.getFrameFilter.?(n, d.node1, frameCtx);
        const ref = if (d.joint) vsapi.?.getFrameFilter.?(n, d.node2, frameCtx) else src;

        const fi = vsapi.?.getVideoFrameFormat.?(src);
        const width = vsapi.?.getFrameWidth.?(src, 0);
        const height = vsapi.?.getFrameHeight.?(src, 0);
        var planes = [_]c_int{ 0, 1, 2 };
        var cp_planes = [_]?*const c.VSFrame{ if (d.process[0]) null else src, if (d.process[1]) null else src, if (d.process[2]) null else src };
        var dst = vsapi.?.newVideoFrame2.?(fi, width, height, &cp_planes, &planes, src, core);
        const psize: u6 = d.psize;
        const peak: f32 = d.peak;

        var plane: c_int = 0;
        while (plane < fi.*.numPlanes) : (plane += 1) {
            const uplane: usize = @intCast(plane);
            if (d.process[uplane]) {
                var srcp: [*]const u8 = vsapi.?.getReadPtr.?(src, plane);
                var refp: [*]const u8 = vsapi.?.getReadPtr.?(ref, plane);
                var dstp: [*]u8 = vsapi.?.getWritePtr.?(dst, plane);
                const stride: usize = @intCast(vsapi.?.getStride.?(src, plane));
                const h: usize = @intCast(vsapi.?.getFrameHeight.?(src, plane));
                const w: usize = @intCast(vsapi.?.getFrameWidth.?(src, plane));

                if (psize == 1) {
                    if (!d.joint) {
                        process.Bilateral2D_2(
                            u8,
                            dstp,
                            srcp,
                            d.gs_lut[uplane].ptr,
                            d.gr_lut[uplane].ptr,
                            stride,
                            w,
                            h,
                            d.radius[uplane],
                            d.step[uplane],
                            peak,
                        );
                    } else {
                        process.Bilateral2D_2ref(
                            u8,
                            dstp,
                            srcp,
                            refp,
                            d.gs_lut[uplane].ptr,
                            d.gr_lut[uplane].ptr,
                            stride,
                            w,
                            h,
                            d.radius[uplane],
                            d.step[uplane],
                            peak,
                        );
                    }
                } else {
                    if (!d.joint) {
                        process.Bilateral2D_2(
                            u16,
                            dstp,
                            srcp,
                            d.gs_lut[uplane].ptr,
                            d.gr_lut[uplane].ptr,
                            stride,
                            w,
                            h,
                            d.radius[uplane],
                            d.step[uplane],
                            peak,
                        );
                    } else {
                        process.Bilateral2D_2ref(
                            u16,
                            dstp,
                            srcp,
                            refp,
                            d.gs_lut[uplane].ptr,
                            d.gr_lut[uplane].ptr,
                            stride,
                            w,
                            h,
                            d.radius[uplane],
                            d.step[uplane],
                            peak,
                        );
                    }
                }
            }
        }

        vsapi.?.freeFrame.?(src);
        if (d.joint) {
            vsapi.?.freeFrame.?(ref);
        }

        return dst;
    }
    return null;
}

export fn zbilateralFree(instanceData: ?*anyopaque, core: ?*c.VSCore, vsapi: ?*const c.VSAPI) callconv(.C) void {
    _ = core;
    var d: *ZbilateralData = @ptrCast(@alignCast(instanceData));

    vsapi.?.freeNode.?(d.node1);
    if (d.joint) {
        vsapi.?.freeNode.?(d.node2);
    }

    var i: usize = 0;
    while (i < 3) : (i += 1) {
        if ((d.process[i]) and (d.algorithm[i] == 2)) {
            allocator.free(d.gs_lut[i]);
        }
    }

    i = 0;
    while (i < 3) : (i += 1) {
        if (d.process[i]) {
            allocator.free(d.gr_lut[i]);
        }
    }

    allocator.destroy(d);
}

export fn zbilateralCreate(in: ?*const c.VSMap, out: ?*c.VSMap, userData: ?*anyopaque, core: ?*c.VSCore, vsapi: ?*const c.VSAPI) callconv(.C) void {
    _ = userData;
    var d: ZbilateralData = undefined;
    var err: c_int = undefined;

    d.node1 = vsapi.?.mapGetNode.?(in, "clip", 0, 0).?;

    const vi: *const c.VSVideoInfo = vsapi.?.getVideoInfo.?(d.node1);
    d.psize = @as(u6, @intCast(vi.format.bytesPerSample));
    const yuv: bool = (vi.format.colorFamily == c.cfYUV);
    const bps = vi.format.bitsPerSample;
    var peak: usize = undefined;
    if (bps == 8) {
        peak = (1 << 8) - 1;
    } else if (bps == 10) {
        peak = (1 << 10) - 1;
    } else if (bps == 12) {
        peak = (1 << 12) - 1;
    } else if (bps == 14) {
        peak = (1 << 14) - 1;
    } else {
        peak = (1 << 16) - 1;
    }

    d.peak = @floatFromInt(peak);

    if ((vi.format.sampleType != c.stInteger) or ((vi.format.bytesPerSample != 1) and (vi.format.bytesPerSample != 2))) {
        vsapi.?.mapSetError.?(out, "Bilateral: Invalid input clip, Only 8-16 bit int formats supported");
        vsapi.?.freeNode.?(d.node1);
        return;
    }

    var i: usize = 0;
    var m: i32 = vsapi.?.mapNumElements.?(in, "sigmaS");
    while (i < 3) : (i += 1) {
        const ssw: i32 = vi.format.subSamplingW;
        const ssh: i32 = vi.format.subSamplingH;
        if (i < m) {
            d.sigmaS[i] = vsapi.?.mapGetFloat.?(in, "sigmaS", @as(c_int, @intCast(i)), 0);
        } else if (i == 0) {
            d.sigmaS[0] = 3.0;
        } else if ((i == 1) and (yuv) and (ssh == 1) and (ssw == 1)) {
            const j: f64 = @floatFromInt((ssh + 1) * (ssw + 1));
            d.sigmaS[1] = d.sigmaS[0] / @sqrt(j);
        } else {
            d.sigmaS[i] = d.sigmaS[i - 1];
        }

        if (d.sigmaS[i] < 0.0) {
            vsapi.?.mapSetError.?(out, "Bilateral: Invalid \"sigmaS\" assigned, must be non-negative float number");
            vsapi.?.freeNode.?(d.node1);
            return;
        }
    }

    i = 0;
    m = vsapi.?.mapNumElements.?(in, "sigmaR");
    while (i < 3) : (i += 1) {
        if (i < m) {
            d.sigmaR[i] = vsapi.?.mapGetFloat.?(in, "sigmaR", @as(c_int, @intCast(i)), 0);
        } else if (i == 0) {
            d.sigmaR[i] = 0.02;
        } else {
            d.sigmaR[i] = d.sigmaR[i - 1];
        }

        if (d.sigmaR[i] < 0) {
            vsapi.?.mapSetError.?(out, "Bilateral: Invalid \"sigmaR\" assigned, must be non-negative float number");
            vsapi.?.freeNode.?(d.node1);
            return;
        }
    }

    i = 0;
    var n: i32 = vi.format.numPlanes;
    m = vsapi.?.mapNumElements.?(in, "planes");
    while (i < 3) : (i += 1) {
        if ((i > 0) and (yuv)) {
            d.process[i] = false;
        } else {
            d.process[i] = m <= 0;
        }
    }

    i = 0;
    while (i < m) : (i += 1) {
        var o: usize = @intCast(vsapi.?.mapGetInt.?(in, "planes", @as(c_int, @intCast(i)), 0));
        if ((o < 0) or (o >= n)) {
            vsapi.?.mapSetError.?(out, "Bilateral: plane index out of range");
            vsapi.?.freeNode.?(d.node1);
            return;
        }
        if (d.process[o]) {
            vsapi.?.mapSetError.?(out, "Bilateral: plane specified twice");
            vsapi.?.freeNode.?(d.node1);
            return;
        }
        d.process[o] = true;
    }

    i = 0;
    while (i < 3) : (i += 1) {
        if ((d.sigmaS[i] == 0.0) or (d.sigmaR[i] == 0.0)) {
            d.process[i] = false;
        }
    }

    i = 0;
    m = vsapi.?.mapNumElements.?(in, "algorithm");
    while (i < 3) : (i += 1) {
        if (i < m) {
            d.algorithm[i] = intSaturateCast(i32, vsapi.?.mapGetInt.?(in, "algorithm", @as(c_int, @intCast(i)), 0));
        } else if (i == 0) {
            d.algorithm[i] = 0;
        } else {
            d.algorithm[i] = d.algorithm[i - 1];
        }

        if ((d.algorithm[i] < 0) or (d.algorithm[i] > 2)) {
            vsapi.?.mapSetError.?(out, "Bilateral: Invalid \"algorithm\" assigned, must be integer ranges in [0,2]");
            vsapi.?.freeNode.?(d.node1);
            return;
        }
    }

    i = 0;
    m = vsapi.?.mapNumElements.?(in, "PBFICnum");
    while (i < 3) : (i += 1) {
        if (i < m) {
            d.PBFICnum[i] = intSaturateCast(u32, vsapi.?.mapGetInt.?(in, "PBFICnum", @as(c_int, @intCast(i)), 0));
        } else if (i == 0) {
            d.PBFICnum[i] = 0;
        } else {
            d.PBFICnum[i] = d.PBFICnum[i - 1];
        }

        if ((d.PBFICnum[i] < 0) or (d.PBFICnum[i] == 1) or (d.PBFICnum[i] > 256)) {
            vsapi.?.mapSetError.?(out, "Bilateral: Invalid \"PBFICnum\" assigned, must be integer ranges in [0,256] except 1");
            vsapi.?.freeNode.?(d.node1);
            return;
        }
    }

    d.node2 = vsapi.?.mapGetNode.?(in, "ref", 0, &err);
    if (err != 0) {
        d.joint = false;
    } else {
        d.joint = true;
        const rvi: *const c.VSVideoInfo = vsapi.?.getVideoInfo.?(d.node2);
        if ((vi.width != rvi.width) or (vi.height != rvi.height)) {
            vsapi.?.mapSetError.?(out, "Bilateral: input clip and clip \"ref\" must be of the same size");
            vsapi.?.freeNode.?(d.node1);
            vsapi.?.freeNode.?(d.node2);
            return;
        }
        if (vi.format.colorFamily != rvi.format.colorFamily) {
            vsapi.?.mapSetError.?(out, "Bilateral: input clip and clip \"ref\" must be of the same color family");
            vsapi.?.freeNode.?(d.node1);
            vsapi.?.freeNode.?(d.node2);
            return;
        }
        if ((vi.format.subSamplingH != rvi.format.subSamplingH) or (vi.format.subSamplingW != rvi.format.subSamplingW)) {
            vsapi.?.mapSetError.?(out, "Bilateral: input clip and clip \"ref\" must be of the same subsampling");
            vsapi.?.freeNode.?(d.node1);
            vsapi.?.freeNode.?(d.node2);
            return;
        }
        if (vi.format.bitsPerSample != rvi.format.bitsPerSample) {
            vsapi.?.mapSetError.?(out, "Bilateral: input clip and clip \"ref\" must be of the same bit depth");
            vsapi.?.freeNode.?(d.node1);
            vsapi.?.freeNode.?(d.node2);
            return;
        }
    }

    i = 0;
    while (i < 3) : (i += 1) {
        if ((d.process[i]) and (d.PBFICnum[i] == 0)) {
            if (d.sigmaR[i] >= 0.08) {
                d.PBFICnum[i] = 4;
            } else if (d.sigmaR[i] >= 0.015) {
                d.PBFICnum[i] = @min(16, @as(u32, @intFromFloat(4.0 * 0.08 / d.sigmaR[i] + 0.5)));
            } else {
                d.PBFICnum[i] = @min(32, @as(u32, @intFromFloat(16.0 * 0.015 / d.sigmaR[i] + 0.5)));
            }

            if ((i > 0) and yuv and (d.PBFICnum[i] % 2 == 0) and (d.PBFICnum[i] < 256)) {
                d.PBFICnum[i] += 1;
            }
        }
    }

    i = 0;
    var orad = [_]i32{ 0, 0, 0 };
    while (i < 3) : (i += 1) {
        if (d.process[i]) {
            orad[i] = @max(@as(i32, @intFromFloat(d.sigmaS[i] * 2.0 + 0.5)), 1);
            if (orad[i] < 4) {
                d.step[i] = 1;
            } else if (orad[i] < 8) {
                d.step[i] = 2;
            } else {
                d.step[i] = 3;
            }

            d.samples[i] = 1;
            d.radius[i] = 1 + (d.samples[i] - 1) * d.step[i];

            while (orad[i] * 2 > d.radius[i] * 3) {
                d.samples[i] += 1;
                d.radius[i] = 1 + (d.samples[i] - 1) * d.step[i];
                if ((d.radius[i] >= orad[i]) and (d.samples[i] > 2)) {
                    d.samples[i] -= 1;
                    d.radius[i] = 1 + (d.samples[i] - 1) * d.step[i];
                    break;
                }
            }
        }
    }

    i = 0;
    while (i < 3) : (i += 1) {
        d.algorithm[i] = 2;
    }

    i = 0;
    while (i < 3) : (i += 1) {
        if ((d.process[i]) and (d.algorithm[i] == 2)) {
            const upper: usize = d.radius[i] + 1;
            d.gs_lut[i] = allocator.alloc(f32, upper * upper) catch unreachable;
            Gaussian_Function_Spatial_LUT_Generation(d.gs_lut[i].ptr, upper, d.sigmaS[i]);
        }
    }

    i = 0;
    while (i < 3) : (i += 1) {
        if (d.process[i]) {
            d.gr_lut[i] = allocator.alloc(f32, peak + 1) catch unreachable;
            Gaussian_Function_Range_LUT_Generation(d.gr_lut[i].ptr, peak, d.sigmaR[i]);
        }
    }

    var data: *ZbilateralData = allocator.create(ZbilateralData) catch unreachable;
    data.* = d;

    var deps = [_]c.VSFilterDependency{
        c.VSFilterDependency{
            .source = d.node1,
            .requestPattern = c.rpStrictSpatial,
        },
        c.VSFilterDependency{
            .source = d.node2,
            .requestPattern = c.rpStrictSpatial,
        },
    };
    vsapi.?.createVideoFilter.?(out, "Bilateral", vi, zbilateralGetFrame, zbilateralFree, c.fmParallel, &deps, if (d.joint) 2 else 1, data, core);
}

export fn VapourSynthPluginInit2(plugin: *c.VSPlugin, vspapi: *const c.VSPLUGINAPI) void {
    _ = vspapi.configPlugin.?("com.julek.zbilateral", "zbilateral", "Bilateral filter", c.VS_MAKE_VERSION(1, 0), c.VAPOURSYNTH_API_VERSION, 0, plugin);
    _ = vspapi.registerFunction.?("Bilateral", "clip:vnode;ref:vnode:opt;sigmaS:float[]:opt;sigmaR:float[]:opt;planes:int[]:opt;algorithm:int[]:opt;PBFICnum:int[]:opt", "clip:vnode;", zbilateralCreate, null, plugin);
}

inline fn Gaussian_Function_Spatial_LUT_Generation(gs_lut: [*]f32, upper: usize, sigmaS: f64) void {
    var y: usize = 0;
    while (y < upper) : (y += 1) {
        var x: usize = 0;
        while (x < upper) : (x += 1) {
            gs_lut[y * upper + x] = floatSaturateCast(f32, @exp(@as(f64, @floatFromInt(x * x + y * y)) / (sigmaS * sigmaS * -2.0)));
        }
    }
}

inline fn Gaussian_Function_Range_LUT_Generation(gr_lut: [*]f32, range: usize, sigmaR: f64) void {
    const levels: usize = range + 1;
    const range_f: f64 = @floatFromInt(range);
    const upper: usize = @intFromFloat(@min(range_f, (sigmaR * 8.0 * range_f + 0.5)));

    var i: usize = 0;
    while (i <= upper) : (i += 1) {
        const j: f64 = @as(f64, @floatFromInt(i)) / range_f;
        gr_lut[i] = floatSaturateCast(f32, Normalized_Gaussian_Function(j, sigmaR));
    }

    if (i < levels) {
        const upperLUTvalue: f32 = gr_lut[upper];
        while (i < levels) : (i += 1) {
            gr_lut[i] = upperLUTvalue;
        }
    }
}

inline fn Normalized_Gaussian_Function(y: f64, sigma: f64) f64 {
    const x = y / sigma;
    return @exp(x * x / -2) / (sqrt_2Pi * sigma);
}

inline fn intSaturateCast(comptime T: type, n: anytype) T {
    const max = math.maxInt(T);
    if (n > max) {
        return max;
    }

    const min = math.minInt(T);
    if (n < min) {
        return min;
    }

    return @as(T, @intCast(n));
}

inline fn floatSaturateCast(comptime T: type, n: anytype) T {
    const max = math.floatMax(T);
    if (n > max) {
        return max;
    }

    const min = math.floatMin(T);
    if (n < min) {
        return min;
    }

    return @as(T, @floatCast(n));
}
