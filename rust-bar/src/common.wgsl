// Shared by shader.wgsl and subpixel.wgsl: bindings, the instance and the vertex stage.
struct Globals {
    viewport: vec2<f32>,
    atlas: vec2<f32>,
};
@group(0) @binding(0) var<uniform> g: Globals;
@group(0) @binding(1) var atlas_tex: texture_2d<f32>;
@group(0) @binding(2) var samp: sampler;
@group(1) @binding(0) var image_tex: texture_2d<f32>;

struct Inst {
    @location(0) rect: vec4<f32>,   // x, y, w, h in item px
    @location(1) xf0: vec3<f32>,    // x' = a x + c y + tx
    @location(2) xf1: vec3<f32>,    // y' = b x + d y + ty
    @location(3) uv: vec4<f32>,     // u0 v0 u1 v1
    @location(4) color: vec4<f32>,  // premultiplied
    @location(5) color2: vec4<f32>, // premultiplied border / outline colour
    @location(6) p0: vec4<f32>,
    @location(7) p1: vec4<f32>,
    @location(8) clip: vec4<f32>,   // device px x0 y0 x1 y1
    @location(9) sclip: vec4<f32>,  // sheared clip: x0, x1 at y ref, slope
};

struct VOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) local: vec2<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) @interpolate(flat) color: vec4<f32>,
    @location(3) @interpolate(flat) color2: vec4<f32>,
    @location(4) @interpolate(flat) p0: vec4<f32>,
    @location(5) @interpolate(flat) p1: vec4<f32>,
    @location(6) @interpolate(flat) rect: vec4<f32>,
    @location(7) @interpolate(flat) clip: vec4<f32>,
    @location(8) @interpolate(flat) sclip: vec4<f32>,
};

fn corner(vi: u32) -> vec2<f32> {
    let x = f32(vi & 1u);
    let y = f32((vi >> 1u) & 1u);
    return vec2<f32>(x, y);
}

fn place(i: Inst, local: vec2<f32>) -> vec4<f32> {
    let dx = i.xf0.x * local.x + i.xf0.y * local.y + i.xf0.z;
    let dy = i.xf1.x * local.x + i.xf1.y * local.y + i.xf1.z;
    return vec4<f32>(dx / g.viewport.x * 2.0 - 1.0, 1.0 - dy / g.viewport.y * 2.0, 0.0, 1.0);
}

// Rectangles grow by one device pixel on each side so the anti-aliased edge has room.
@vertex
fn vs_rect(@builtin(vertex_index) vi: u32, i: Inst) -> VOut {
    var o: VOut;
    let c = corner(vi);
    let sx = max(length(vec2<f32>(i.xf0.x, i.xf1.x)), 0.0001);
    let sy = max(length(vec2<f32>(i.xf0.y, i.xf1.y)), 0.0001);
    let m = vec2<f32>(1.0 / sx, 1.0 / sy);
    let local = i.rect.xy - m + c * (i.rect.zw + 2.0 * m);
    o.pos = place(i, local);
    o.local = local;
    o.uv = vec2<f32>(0.0);
    o.color = i.color;
    o.color2 = i.color2;
    o.p0 = i.p0;
    o.p1 = i.p1;
    o.rect = i.rect;
    o.clip = i.clip;
    o.sclip = i.sclip;
    return o;
}

@vertex
fn vs_quad(@builtin(vertex_index) vi: u32, i: Inst) -> VOut {
    var o: VOut;
    let c = corner(vi);
    let local = i.rect.xy + c * i.rect.zw;
    o.pos = place(i, local);
    o.local = local;
    o.uv = mix(i.uv.xy, i.uv.zw, c);
    o.color = i.color;
    o.color2 = i.color2;
    o.p0 = i.p0;
    o.p1 = i.p1;
    o.rect = i.rect;
    o.clip = i.clip;
    o.sclip = i.sclip;
    return o;
}

/// Coverage of the sheared clip's sloping sides (1 without one).
fn skew_cov(v: VOut) -> f32 {
    let off = v.sclip.w * (v.pos.y - v.sclip.z);
    let l = v.sclip.x + off;
    let r = v.sclip.y + off;
    return clamp(v.pos.x - l + 0.5, 0.0, 1.0) * clamp(r - v.pos.x + 0.5, 0.0, 1.0);
}

fn clipped(v: VOut) -> bool {
    return v.pos.x < v.clip.x || v.pos.y < v.clip.y || v.pos.x >= v.clip.z || v.pos.y >= v.clip.w;
}

