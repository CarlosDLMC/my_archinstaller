// Qt's hiqsubpixeldistancefieldtext: five samples across the pixel, one
// coverage per channel, blended per channel (dual-source).
struct DualOut {
    @location(0) @blend_src(0) color: vec4<f32>,
    @location(0) @blend_src(1) mask: vec4<f32>,
};

// p1.x: atlas u per device pixel (the sub-sample step); color.a carries the text alpha
@fragment
fn fs_text_subpixel(v: VOut) -> DualOut {
    if (clipped(v)) { discard; }
    let du = v.p1.x;
    var n: vec4<f32>;
    n.x = textureSample(atlas_tex, samp, v.uv - vec2<f32>(du * 0.667, 0.0)).r;
    n.y = textureSample(atlas_tex, samp, v.uv - vec2<f32>(du * 0.333, 0.0)).r;
    var c = textureSample(atlas_tex, samp, v.uv).r;
    n.z = textureSample(atlas_tex, samp, v.uv + vec2<f32>(du * 0.333, 0.0)).r;
    n.w = textureSample(atlas_tex, samp, v.uv + vec2<f32>(du * 0.667, 0.0)).r;
    let dd = min(abs(n.yw - n.xz) * 2.0, vec2<f32>(0.67));
    let lo = mix(vec2<f32>(v.p0.x), vec2<f32>(0.5), dd);
    let hi = mix(vec2<f32>(v.p0.y), vec2<f32>(0.5), dd);
    n = smoothstep(lo.xxyy, hi.xxyy, n);
    c = smoothstep(lo.x + lo.y, hi.x + hi.y, 2.0 * c);
    // Qt: fragColor = coverage * color.w, blended with constant = premultiplied colour.
    let f = vec4<f32>((n.xyz + n.yzw + vec3<f32>(c)) * 0.333, c) * v.color.a;
    let k = skew_cov(v);
    var o: DualOut;
    o.color = vec4<f32>(v.color.rgb * f.rgb, f.a) * k;
    o.mask = f * k;
    return o;
}

