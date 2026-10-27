// One quad per instance; fragment programs: rounded rectangle, distance
// field text (Qt's distancefieldtext / distancefieldoutlinetext) and image.
// The subpixel text program is in subpixel.wgsl (dual-source blending needs a
// module of its own); both are prefixed with common.wgsl.

// Qt's smooth rectangle (qsgbasicinternalrectanglenode.cpp): each corner is
// an inscribed polygon of clamp(ceil(r * pi / 6), 3, 18) chords, and the
// vertex shader moves every edge vertex half a pixel in x and in y
// separately - inwards for the opaque ring, outwards for the clear one. So a
// point's alpha is 0.5 - s, where s is how far (in pixels, along the
// diagonal) the convex outline must move to pass through it: the largest
// (n.q - c) / (n.x + n.y) over the edges' and chords' half-planes.
// q is folded into one quadrant, relative to the corner's centre.
fn qt_alpha(q: vec2<f32>, r: f32, segments: f32, px: f32) -> f32 {
    var s = max(q.x, q.y) - r;
    if (r > 0.0 && q.x > 0.0 && q.y > 0.0) {
        let step = 1.5707964 / segments;
        let c = r * cos(step * 0.5);
        for (var k = 0.0; k < segments; k += 1.0) {
            let a = (k + 0.5) * step;
            let n = vec2<f32>(cos(a), sin(a));
            s = max(s, (dot(n, q) - c) / (n.x + n.y));
        }
    }
    return clamp(0.5 - s / px, 0.0, 1.0);
}

// p0: radius, border width, antialiasing (0/1), unused
@fragment
fn fs_rect(v: VOut) -> @location(0) vec4<f32> {
    if (clipped(v)) { discard; }
    let half = v.rect.zw * 0.5;
    let center = v.rect.xy + half;
    let bw = v.p0.y;
    var outer: f32;
    var inner: f32;
    if (v.p0.z > 0.5) {
        // Qt: radius <= min(w, h) * 0.4999, and none at all at half a pixel or less.
        var r = min(v.p0.x, min(half.x, half.y) * 0.9998);
        if (r <= 0.5) { r = 0.0; }
        let segments = clamp(ceil(r * 0.5235988), 3.0, 18.0);
        let px = max(length(dpdx(v.local)), 0.0001);
        let a = abs(v.local - center);
        outer = qt_alpha(a - (half - vec2<f32>(r)), r, segments, px);
        let ri = select(0.0, max(r - bw, 0.01), r > 0.0);
        inner = qt_alpha(a - (half - vec2<f32>(bw) - vec2<f32>(ri)), ri, segments, px);
    } else {
        let r = min(v.p0.x, min(half.x, half.y));
        let q = abs(v.local - center) - (half - vec2<f32>(r));
        let d = length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - r;
        outer = select(0.0, 1.0, d <= 0.0);
        inner = select(0.0, 1.0, d + bw <= 0.0);
    }
    if (bw <= 0.0) { inner = outer; }
    return v.color * inner + v.color2 * (outer - inner);
}

// p0: alphaMin, alphaMax, outlineAlphaMax0, outlineAlphaMax1; p1.y: 1 = outline style
@fragment
fn fs_text(v: VOut) -> @location(0) vec4<f32> {
    if (clipped(v)) { discard; }
    let d = textureSample(atlas_tex, samp, v.uv).r;
    let a = smoothstep(v.p0.x, v.p0.y, d);
    if (v.p1.y > 0.5) {
        return mix(v.color2, v.color, vec4<f32>(a)) * smoothstep(v.p0.z, v.p0.w, d);
    }
    return v.color * a;
}

// p0.x: opacity
@fragment
fn fs_image(v: VOut) -> @location(0) vec4<f32> {
    if (clipped(v)) { discard; }
    return textureSample(image_tex, samp, v.uv) * v.p0.x;
}

// Qt's outlinedtext.frag: coverage plus the four one-texel neighbours.
@fragment
fn fs_native_outline(v: VOut) -> @location(0) vec4<f32> {
    if (clipped(v)) { discard; }
    let t = 1.0 / g.atlas;
    let glyph = textureSample(atlas_tex, samp, v.uv).r;
    let n = textureSample(atlas_tex, samp, v.uv + vec2<f32>(0.0, t.y)).r
          + textureSample(atlas_tex, samp, v.uv - vec2<f32>(0.0, t.y)).r
          + textureSample(atlas_tex, samp, v.uv + vec2<f32>(t.x, 0.0)).r
          + textureSample(atlas_tex, samp, v.uv - vec2<f32>(t.x, 0.0)).r;
    let outline = clamp(clamp(n, 0.0, 1.0) - glyph, 0.0, 1.0);
    return v.color2 * outline + v.color * glyph;
}
