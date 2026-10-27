// One quad per instance; fragment programs: rounded rectangle, distance
// field text (Qt's distancefieldtext / distancefieldoutlinetext) and image.
// The subpixel text program is in subpixel.wgsl (dual-source blending needs a
// module of its own); both are prefixed with common.wgsl.

// p0: radius, border width, antialiasing (0/1), unused
@fragment
fn fs_rect(v: VOut) -> @location(0) vec4<f32> {
    if (clipped(v)) { discard; }
    let half = v.rect.zw * 0.5;
    let center = v.rect.xy + half;
    let r = min(v.p0.x, min(half.x, half.y));
    let q = abs(v.local - center) - (half - vec2<f32>(r));
    let d = length(max(q, vec2<f32>(0.0))) + min(max(q.x, q.y), 0.0) - r;
    let bw = v.p0.y;
    var outer: f32;
    var inner: f32;
    if (v.p0.z > 0.5) {
        let fw = max(fwidth(d), 0.0001);
        outer = clamp(0.5 - d / fw, 0.0, 1.0);
        inner = clamp(0.5 - (d + bw) / fw, 0.0, 1.0);
    } else {
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
