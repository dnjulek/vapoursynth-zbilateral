const std = @import("std");
const math = std.math;

const allocator = std.heap.c_allocator;

inline fn absDiff(x: anytype, y: anytype) @TypeOf(x) {
    return if (x > y) (x - y) else (y - x);
}

inline fn stride_cal(comptime T: type, width: usize) usize {
    const alignment: usize = 32 / @sizeOf(T);
    return if (width % alignment == 0) width else (width / alignment + 1) * alignment;
}

inline fn data2buff(comptime T: type, dst: [*]T, src: [*]const T, radius: usize, bufheight: usize, bufwidth: usize, bufstride: usize, height: usize, width: usize, stride: usize) void {
    var srcp = src;
    var dstp = dst;

    var y: usize = 0;
    while (y < height) : (y += 1) {
        dstp = dst + (radius + y) * bufstride;
        srcp = src + y * stride;

        var x: usize = 0;
        while (x < radius) : (x += 1) {
            dstp[x] = srcp[0];
        }
        var tmpp = dstp + radius;
        @memcpy(tmpp[0..width], srcp);

        x = radius + width;
        while (x < bufwidth) : (x += 1) {
            dstp[x] = srcp[width - 1];
        }
    }

    srcp = dst + radius * bufstride;
    y = 0;
    while (y < radius) : (y += 1) {
        dstp = dst + y * bufstride;
        @memcpy(dstp[0..bufwidth], srcp);
    }

    srcp = dst + (radius + height - 1) * bufstride;
    y = radius + height;

    while (y < bufheight) : (y += 1) {
        dstp = dst + y * bufstride;
        @memcpy(dstp[0..bufwidth], srcp);
    }
}

pub inline fn Bilateral2D_2(comptime T: type, _dstp: [*]u8, _srcp: [*]const u8, gs_lut: [*]f32, gr_lut: [*]f32, _stride: usize, width: usize, height: usize, radius: usize, samplestep: usize, peak: f32) void {
    var srcp: [*]const T = @as([*]const T, @ptrCast(@alignCast(_srcp)));
    var dstp: [*]T = @as([*]T, @ptrCast(@alignCast(_dstp)));
    const stride: usize = _stride >> (@sizeOf(T) >> 1);
    const radius2: usize = radius + 1;
    const bufheight: usize = height + radius * 2;
    const bufwidth: usize = width + radius * 2;
    const bufstride: usize = stride_cal(T, bufwidth);

    const srcbuff_arr = allocator.alignedAlloc(T, 32, bufheight * bufstride) catch unreachable;
    defer allocator.free(srcbuff_arr);
    const srcbuff: [*]T = srcbuff_arr.ptr;

    data2buff(T, srcbuff, srcp, radius, bufheight, bufwidth, bufstride, height, width, stride);

    var swei: f32 = undefined;
    var rwei1: f32 = undefined;
    var rwei2: f32 = undefined;
    var rwei3: f32 = undefined;
    var rwei4: f32 = undefined;
    var weight_sum: f32 = undefined;
    var sum: f32 = undefined;

    var y: usize = 0;
    while (y < height) : (y += 1) {
        const tmp1: usize = (radius + y) * bufstride;
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const tmp2: usize = radius + x + tmp1;
            const cx: T = srcp[x];

            weight_sum = gs_lut[0] * gr_lut[0];
            sum = @as(f32, @floatFromInt(srcp[x])) * weight_sum;

            var yy: usize = 1;
            while (yy < radius2) : (yy += samplestep) {
                const tmp3: usize = yy * bufstride;

                var xx: usize = 1;
                while (xx < radius2) : (xx += samplestep) {
                    const cxx1: T = srcbuff[tmp2 + tmp3 + xx];
                    const cxx2: T = srcbuff[tmp2 + tmp3 - xx];
                    const cxx3: T = srcbuff[tmp2 - tmp3 - xx];
                    const cxx4: T = srcbuff[tmp2 - tmp3 + xx];
                    const cxx1f: f32 = @floatFromInt(cxx1);
                    const cxx2f: f32 = @floatFromInt(cxx2);
                    const cxx3f: f32 = @floatFromInt(cxx3);
                    const cxx4f: f32 = @floatFromInt(cxx4);

                    swei = gs_lut[yy * radius2 + xx];
                    rwei1 = gr_lut[absDiff(cx, cxx1)];
                    rwei2 = gr_lut[absDiff(cx, cxx2)];
                    rwei3 = gr_lut[absDiff(cx, cxx3)];
                    rwei4 = gr_lut[absDiff(cx, cxx4)];
                    weight_sum += swei * (rwei1 + rwei2 + rwei3 + rwei4);
                    sum += swei * (cxx1f * rwei1 + cxx2f * rwei2 + cxx3f * rwei3 + cxx4f * rwei4);
                }
            }
            dstp[x] = @intFromFloat(math.clamp(sum / weight_sum + 0.5, 0.0, peak));
        }
        srcp += stride;
        dstp += stride;
    }
}

pub inline fn Bilateral2D_2ref(comptime T: type, _dstp: [*]u8, _srcp: [*]const u8, _refp: [*]const u8, gs_lut: [*]f32, gr_lut: [*]f32, _stride: usize, width: usize, height: usize, radius: usize, samplestep: usize, peak: f32) void {
    var srcp: [*]const T = @as([*]const T, @ptrCast(@alignCast(_srcp)));
    var refp: [*]const T = @as([*]const T, @ptrCast(@alignCast(_refp)));
    var dstp: [*]T = @as([*]T, @ptrCast(@alignCast(_dstp)));
    const stride: usize = _stride >> (@sizeOf(T) >> 1);
    const radius2: usize = radius + 1;
    const bufheight: usize = height + radius * 2;
    const bufwidth: usize = width + radius * 2;
    const bufstride: usize = stride_cal(T, bufwidth);

    const srcbuff_arr = allocator.alignedAlloc(T, 32, bufheight * bufstride) catch unreachable;
    const refbuff_arr = allocator.alignedAlloc(T, 32, bufheight * bufstride) catch unreachable;
    defer allocator.free(srcbuff_arr);
    defer allocator.free(refbuff_arr);
    const srcbuff: [*]T = srcbuff_arr.ptr;
    const refbuff: [*]T = refbuff_arr.ptr;

    data2buff(T, srcbuff, srcp, radius, bufheight, bufwidth, bufstride, height, width, stride);
    data2buff(T, refbuff, refp, radius, bufheight, bufwidth, bufstride, height, width, stride);

    var swei: f32 = undefined;
    var rwei1: f32 = undefined;
    var rwei2: f32 = undefined;
    var rwei3: f32 = undefined;
    var rwei4: f32 = undefined;
    var weight_sum: f32 = undefined;
    var sum: f32 = undefined;

    var y: usize = 0;
    while (y < height) : (y += 1) {
        const tmp1: usize = (radius + y) * bufstride;
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const tmp2: usize = radius + x + tmp1;
            const cx: T = refp[x];

            weight_sum = gs_lut[0] * gr_lut[0];
            sum = @as(f32, @floatFromInt(srcp[x])) * weight_sum;

            var yy: usize = 1;
            while (yy < radius2) : (yy += samplestep) {
                const tmp3: usize = yy * bufstride;

                var xx: usize = 1;
                while (xx < radius2) : (xx += samplestep) {
                    const cxx1: T = refbuff[tmp2 + tmp3 + xx];
                    const cxx2: T = refbuff[tmp2 + tmp3 - xx];
                    const cxx3: T = refbuff[tmp2 - tmp3 - xx];
                    const cxx4: T = refbuff[tmp2 - tmp3 + xx];
                    const cxx1f: f32 = @floatFromInt(srcbuff[tmp2 + tmp3 + xx]);
                    const cxx2f: f32 = @floatFromInt(srcbuff[tmp2 + tmp3 - xx]);
                    const cxx3f: f32 = @floatFromInt(srcbuff[tmp2 - tmp3 - xx]);
                    const cxx4f: f32 = @floatFromInt(srcbuff[tmp2 - tmp3 + xx]);

                    swei = gs_lut[yy * radius2 + xx];
                    rwei1 = gr_lut[absDiff(cx, cxx1)];
                    rwei2 = gr_lut[absDiff(cx, cxx2)];
                    rwei3 = gr_lut[absDiff(cx, cxx3)];
                    rwei4 = gr_lut[absDiff(cx, cxx4)];
                    weight_sum += swei * (rwei1 + rwei2 + rwei3 + rwei4);
                    sum += swei * (cxx1f * rwei1 + cxx2f * rwei2 + cxx3f * rwei3 + cxx4f * rwei4);
                }
            }
            dstp[x] = @intFromFloat(math.clamp(sum / weight_sum + 0.5, 0.0, peak));
        }
        srcp += stride;
        refp += stride;
        dstp += stride;
    }
}
