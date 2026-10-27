//! The renderer: one wgpu device (Vulkan only - measured cheaper than GL on
//! this card), shared by every surface; quads drawn in painter's order.

use std::ops::Range;

use crate::color::Color;
use crate::text::{Fonts, Line, DF_BASE, DF_RADIUS};

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct Inst {
    pub rect: [f32; 4],
    pub xf0: [f32; 3],
    pub xf1: [f32; 3],
    pub uv: [f32; 4],
    pub color: [f32; 4],
    pub color2: [f32; 4],
    pub p0: [f32; 4],
    pub p1: [f32; 4],
    pub clip: [f32; 4],
    /// A sheared clip (an item with clip: true under a skew): x0, x1 at
    /// device y = yref, slope dx/dy. NO_SKEW_CLIP when there is none.
    pub sclip: [f32; 4],
}

pub const NO_SKEW_CLIP: [f32; 4] = [-1e30, 1e30, 0.0, 0.0];

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Pipe {
    Rect,
    Text,
    TextSub,
    Image(u32),
    /// Qt's native glyph path with style: Text.Outline (outlinedtext.frag).
    NativeOutline,
    /// A colour glyph from the RGBA atlas (emoji).
    Color,
    /// QtQuick.Effects RectangularShadow.
    Shadow,
    /// Scene::hole.
    Clear,
}

/// A 2D affine transform: x' = a x + c y + tx, y' = b x + d y + ty.
#[derive(Clone, Copy, Debug)]
pub struct Xf {
    pub a: f32,
    pub b: f32,
    pub c: f32,
    pub d: f32,
    pub tx: f32,
    pub ty: f32,
}

impl Xf {
    pub const ID: Xf = Xf { a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0 };

    pub fn then(&self, o: &Xf) -> Xf {
        // self applied first, then o
        Xf {
            a: o.a * self.a + o.c * self.b,
            b: o.b * self.a + o.d * self.b,
            c: o.a * self.c + o.c * self.d,
            d: o.b * self.c + o.d * self.d,
            tx: o.a * self.tx + o.c * self.ty + o.tx,
            ty: o.b * self.tx + o.d * self.ty + o.ty,
        }
    }

    pub fn apply(&self, x: f32, y: f32) -> (f32, f32) {
        (self.a * x + self.c * y + self.tx, self.b * x + self.d * y + self.ty)
    }

    /// The scale Qt's text materials call the matrix scale.
    pub fn scale(&self) -> f32 {
        ((self.a * self.d - self.b * self.c).abs()).sqrt()
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum TextStyle {
    /// Plain Text: Qt draws it with subpixel anti-aliasing.
    Normal,
    /// style: Text.Outline, styleColor.
    Outline(Color),
    /// Plain text forced to grey anti-aliasing (for translucent text).
    Gray,
    /// renderType: Text.NativeRendering - FreeType's gray coverage at the
    /// device size; the hinting preference (1 full, 2 none, 0 default).
    Native(u8),
}

pub struct Scene {
    pub insts: Vec<Inst>,
    pub batches: Vec<(Pipe, Range<u32>)>,
    pub xf: Xf,
    pub clip: [f32; 4],
    pub sclip: [f32; 4],
    pub opacity: f32,
    stack: Vec<(Xf, [f32; 4], [f32; 4], f32)>,
    atlas_size: (f32, f32),
}

/// thresholdFunc of Qt's distance-field text material (QT_DF_BASE 0.5,
/// QT_DF_BASEDEVIATION 0.065, QT_DF_SCALEFORMAXDEV 0.15, QT_DF_SCALEFORNODEV 0.3).
fn df_threshold(scale: f32) -> f32 {
    const BASE: f32 = 0.5;
    const BASE_DEV: f32 = 0.065;
    const MIN: f32 = 0.15;
    const MAX: f32 = 0.3;
    BASE - ((scale.clamp(MIN, MAX) - MIN) / (MAX - MIN) * -BASE_DEV + BASE_DEV)
}

/// alphaMin / alphaMax: threshold -/+ spreadFunc (QT_DF_RANGE 0.06 / scale).
fn df_alpha_range(scale: f32) -> (f32, f32) {
    let t = df_threshold(scale);
    let range = 0.06 / scale;
    ((t - range).max(0.0), (t + range).min(1.0))
}

/// Qt's outline material: where the outline fades out (read back from Qt's
/// own uniforms: 24 px gives 0.14 / 0.365).
fn df_outline_range(font_scale: f32, combined: f32) -> (f32, f32) {
    let (alpha_min, _) = df_alpha_range(combined);
    let base = df_threshold(combined);
    let range = 0.06 / combined;
    let limit = (base - 0.5 / DF_RADIUS / font_scale).max(0.2);
    ((limit - range).max(0.0), (limit + range).min(alpha_min))
}

impl Scene {
    pub fn new(width: f32, height: f32) -> Scene {
        Scene {
            insts: Vec::new(),
            batches: Vec::new(),
            xf: Xf::ID,
            clip: [0.0, 0.0, width, height],
            sclip: NO_SKEW_CLIP,
            opacity: 1.0,
            stack: Vec::new(),
            atlas_size: (1.0, 1.0),
        }
    }

    pub fn clear(&mut self, width: f32, height: f32) {
        self.insts.clear();
        self.batches.clear();
        self.xf = Xf::ID;
        self.clip = [0.0, 0.0, width, height];
        self.sclip = NO_SKEW_CLIP;
        self.opacity = 1.0;
        self.stack.clear();
    }

    pub fn save(&mut self) {
        self.stack.push((self.xf, self.clip, self.sclip, self.opacity));
    }

    pub fn restore(&mut self) {
        if let Some((x, c, sc, o)) = self.stack.pop() {
            self.xf = x;
            self.clip = c;
            self.sclip = sc;
            self.opacity = o;
        }
    }

    pub fn translate(&mut self, x: f32, y: f32) {
        self.xf = Xf { a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: x, ty: y }.then(&self.xf);
    }

    pub fn scale(&mut self, sx: f32, sy: f32) {
        self.xf = Xf { a: sx, b: 0.0, c: 0.0, d: sy, tx: 0.0, ty: 0.0 }.then(&self.xf);
    }

    pub fn transform(&mut self, m: Xf) {
        self.xf = m.then(&self.xf);
    }

    pub fn multiply_opacity(&mut self, o: f32) {
        self.opacity *= o;
    }

    /// clip: true on an item - an axis-aligned cut in device pixels.
    pub fn clip_rect(&mut self, x: f32, y: f32, w: f32, h: f32) {
        let (x0, y0) = self.xf.apply(x, y);
        let (x1, y1) = self.xf.apply(x + w, y + h);
        let (x0, x1) = (x0.min(x1), x0.max(x1));
        let (y0, y1) = (y0.min(y1), y0.max(y1));
        if self.xf.c.abs() > 1e-6 && self.xf.b.abs() < 1e-6 {
            // Under a skew the cut is a parallelogram: its y range here, its
            // sloping sides in sclip (Qt clips it in a multisampled layer).
            let k = self.xf.c / self.xf.d;
            let yref = self.xf.ty;
            let (l, r) = (self.xf.a * x + self.xf.tx, self.xf.a * (x + w) + self.xf.tx);
            self.sclip = [l.min(r), l.max(r), yref, k];
            let (ya, yb) = (self.xf.d * y + self.xf.ty, self.xf.d * (y + h) + self.xf.ty);
            self.clip = [self.clip[0], self.clip[1].max(ya.min(yb)), self.clip[2], self.clip[3].min(ya.max(yb))];
            return;
        }
        self.clip = [self.clip[0].max(x0), self.clip[1].max(y0), self.clip[2].min(x1), self.clip[3].min(y1)];
    }

    fn push(&mut self, pipe: Pipe, inst: Inst) {
        let i = self.insts.len() as u32;
        self.insts.push(inst);
        if let Some((p, r)) = self.batches.last_mut() {
            if *p == pipe && r.end == i {
                r.end = i + 1;
                return;
            }
        }
        self.batches.push((pipe, i..i + 1));
    }

    fn base(&self, x: f32, y: f32, w: f32, h: f32) -> Inst {
        Inst {
            rect: [x, y, w, h],
            xf0: [self.xf.a, self.xf.c, self.xf.tx],
            xf1: [self.xf.b, self.xf.d, self.xf.ty],
            clip: self.clip,
            sclip: self.sclip,
            ..Default::default()
        }
    }

    /// A QML Rectangle: fill, radius, border inside the edge. `aa` is
    /// Rectangle.antialiasing (QML turns it on whenever radius > 0).
    pub fn rect(&mut self, x: f32, y: f32, w: f32, h: f32, fill: Color, radius: f32, border: f32, border_color: Color, aa: bool) {
        if w <= 0.0 || h <= 0.0 || self.opacity <= 0.0 {
            return;
        }
        if fill.a <= 0.0 && (border <= 0.0 || border_color.a <= 0.0) {
            return;
        }
        let mut i = self.base(x, y, w, h);
        i.color = fill.premul(self.opacity);
        i.color2 = border_color.premul(self.opacity);
        i.p0 = [radius, border, if aa { 1.0 } else { 0.0 }, 0.0];
        self.push(Pipe::Rect, i);
    }

    /// A transparent hole in what is drawn so far, whole pixels by the fill
    /// rule: a subsurface placed below shows through it (the audio meter).
    pub fn hole(&mut self, x: f32, y: f32, w: f32, h: f32) {
        if w <= 0.0 || h <= 0.0 {
            return;
        }
        let i = self.base(x, y, w, h);
        self.push(Pipe::Clear, i);
    }

    pub fn fill(&mut self, x: f32, y: f32, w: f32, h: f32, c: Color) {
        self.rect(x, y, w, h, c, 0.0, 0.0, Color::TRANSPARENT, false);
    }

    /// A laid-out line with its baseline at (x, y).
    pub fn text(&mut self, fonts: &mut Fonts, line: &Line, x: f32, baseline: f32, color: Color, style: TextStyle) {
        if let TextStyle::Native(hint) = style {
            self.text_native(fonts, line, x, baseline, color, hint);
            return;
        }
        if self.opacity <= 0.0 || line.glyphs.is_empty() {
            return;
        }
        let font_scale = line.size / DF_BASE;
        let combined = font_scale * self.xf.scale();
        let (amin, amax) = df_alpha_range(combined);
        let (o0, o1) = df_outline_range(font_scale, combined);
        // Text.Outline is two nodes in Qt: the outline material for every
        // glyph, then the plain gray text drawn again on top of it.
        let passes: &[u8] = match style {
            TextStyle::Outline(_) => &[1, 0],
            _ => &[0],
        };
        // Qt picks the subpixel material whatever the alpha; the shader scales
        // the coverage by alpha * opacity (hiqsubpixeldistancefieldtext.frag)
        // and the colour is blended in once - measured: white at alpha .3
        // over 16 gives 84 = 242 * .3 + 16 * .7.
        let subpixel = style == TextStyle::Normal;
        for &outline_pass in passes {
            for g in &line.glyphs {
                if g.color {
                    continue;
                }
                let Some(df) = fonts.df_glyph(g.face, g.gid, g.bold) else { continue };
                self.atlas_size = (fonts.atlas.width as f32, fonts.atlas.height as f32);
                let mut i = self.base(
                    x + g.x + df.x0 * font_scale,
                    baseline + df.y0 * font_scale,
                    df.w as f32 * font_scale,
                    df.h as f32 * font_scale,
                );
                i.uv = [df.ax as f32, df.ay as f32, (df.ax + df.w) as f32, (df.ay + df.h) as f32];
                i.p0 = [amin, amax, o0, o1];
                i.color = color.premul(self.opacity);
                if outline_pass == 1 {
                    if let TextStyle::Outline(sc) = style {
                        i.color2 = sc.premul(self.opacity);
                    }
                    i.p1 = [0.0, 1.0, 0.0, 0.0];
                    self.push(Pipe::Text, i);
                } else if subpixel {
                    i.color = [color.r, color.g, color.b, color.a * self.opacity];
                    // atlas texels per device pixel, normalised later by the atlas width
                    i.p1 = [1.0 / combined, 0.0, 0.0, 0.0];
                    self.push(Pipe::TextSub, i);
                } else {
                    self.push(Pipe::Text, i);
                }
            }
        }
        if line.glyphs.iter().any(|g| g.color) {
            self.color_glyphs(fonts, line, x, baseline);
        }
    }

    /// Colour glyphs (emoji): the scaled strike bitmap, on whole device pixels
    /// like Qt's native (ARGB) glyph cache.
    pub fn color_glyphs(&mut self, fonts: &mut Fonts, line: &Line, x: f32, baseline: f32) {
        let size = line.size * self.xf.scale();
        for g in line.glyphs.iter().filter(|g| g.color) {
            let (dx, dy) = self.xf.apply(x + g.x, baseline);
            let Some(cg) = fonts.color_glyph(g.face, g.gid, size) else { continue };
            let px = (dx + cg.left).round();
            let py = (dy - cg.top).round();
            let mut i = Inst {
                rect: [px, py, cg.w as f32, cg.h as f32],
                xf0: [1.0, 0.0, 0.0],
                xf1: [0.0, 1.0, 0.0],
                clip: self.clip,
                sclip: self.sclip,
                ..Default::default()
            };
            i.uv = [cg.ax as f32, cg.ay as f32, (cg.ax + cg.w) as f32, (cg.ay + cg.h) as f32];
            i.p0 = [self.opacity, 0.0, 0.0, 0.0];
            self.push(Pipe::Color, i);
        }
    }

    /// Outlined text goes down Qt's native path: FreeType coverage at the
    /// device size, pen x floored with the fraction rendered in quarters, the
    /// baseline rounded, and the outline made from the four neighbours.
    fn text_native_outline(&mut self, fonts: &mut Fonts, line: &Line, x: f32, baseline: f32, color: Color, style_color: Color) {
        let scale = self.xf.scale();
        let size = line.size * scale;
        for g in &line.glyphs {
            let (dx, dy) = self.xf.apply(x + g.x, baseline);
            let quarter = Fonts::subpixel_quarter(dx);
            let Some(ng) = fonts.native_glyph(g.face, g.gid, size, quarter) else { continue };
            if ng.w == 0 {
                continue;
            }
            let px = dx.floor() + ng.left as f32 - 1.0;
            let py = dy.round() - ng.top as f32 - 1.0;
            let mut i = Inst {
                rect: [px, py, (ng.w + 2) as f32, (ng.h + 2) as f32],
                xf0: [1.0, 0.0, 0.0],
                xf1: [0.0, 1.0, 0.0],
                clip: self.clip,
                sclip: self.sclip,
                ..Default::default()
            };
            i.uv = [(ng.ax - 1) as f32, (ng.ay - 1) as f32, (ng.ax + ng.w + 1) as f32, (ng.ay + ng.h + 1) as f32];
            i.color = color.premul(self.opacity);
            i.color2 = style_color.premul(self.opacity);
            self.push(Pipe::NativeOutline, i);
        }
    }

    /// Native glyphs: full hinting snaps the pen to whole pixels, otherwise
    /// it is placed in quarters (QFontEngineFT's subpixel positions).
    fn text_native(&mut self, fonts: &mut Fonts, line: &Line, x: f32, baseline: f32, color: Color, hint: u8) {
        let scale = self.xf.scale();
        let size = line.size * scale;
        for g in &line.glyphs {
            let (dx, dy) = self.xf.apply(x + g.x, baseline);
            let (dx, quarter) = if hint == 1 { (dx.round(), 0) } else { (dx, Fonts::subpixel_quarter(dx)) };
            let Some(ng) = fonts.native_glyph_hinted(g.face, g.gid, size, quarter, hint) else { continue };
            if ng.w == 0 {
                continue;
            }
            let px = dx.floor() + ng.left as f32 - 1.0;
            let py = dy.round() - ng.top as f32 - 1.0;
            let mut i = Inst {
                rect: [px, py, (ng.w + 2) as f32, (ng.h + 2) as f32],
                xf0: [1.0, 0.0, 0.0],
                xf1: [0.0, 1.0, 0.0],
                clip: self.clip,
                sclip: self.sclip,
                ..Default::default()
            };
            i.uv = [(ng.ax - 1) as f32, (ng.ay - 1) as f32, (ng.ax + ng.w + 1) as f32, (ng.ay + ng.h + 1) as f32];
            i.color = color.premul(self.opacity);
            i.color2 = [0.0; 4];
            self.push(Pipe::NativeOutline, i);
        }
    }

    /// RectangularShadow on an item at (x, y, w, h): the quad grows by
    /// 2 blur + 2 spread, the box inside shrinks by 1.8 blur, and the alpha is
    /// colour * a^2 with a = 1 - smoothstep(0, 2.1 blur, distance)
    /// (qquickrectangularshadow.cpp, rectangularshadow.frag; radius 0).
    pub fn shadow(&mut self, x: f32, y: f32, w: f32, h: f32, color: Color, blur: f32, spread: f32, offset: (f32, f32)) {
        if self.opacity <= 0.0 {
            return;
        }
        let pad = 2.0 * blur + 2.0 * spread;
        let (ew, eh) = (w + pad, h + pad);
        let (ex, ey) = (x + (w - ew) / 2.0 + offset.0, y + (h - eh) / 2.0 + offset.1);
        let mut i = self.base(ex, ey, ew, eh);
        i.color = color.premul(self.opacity);
        i.p0 = [ew / 2.0 - blur * 1.8, eh / 2.0 - blur * 1.8, blur * 2.1, 0.0];
        self.push(Pipe::Shadow, i);
    }

    pub fn image(&mut self, id: u32, x: f32, y: f32, w: f32, h: f32, uv: [f32; 4]) {
        if self.opacity <= 0.0 {
            return;
        }
        let mut i = self.base(x, y, w, h);
        i.uv = uv;
        i.p0 = [self.opacity, 0.0, 0.0, 0.0];
        self.push(Pipe::Image(id), i);
    }

    /// Atlas texel coordinates become normalised uv once the atlas size is final.
    fn finish_color(&mut self, w: f32, h: f32) {
        for (p, r) in &self.batches {
            if *p == Pipe::Color {
                for i in &mut self.insts[r.start as usize..r.end as usize] {
                    if i.uv[2] > 1.0 || i.uv[3] > 1.0 || i.uv[0] > 1.0 {
                        i.uv = [i.uv[0] / w, i.uv[1] / h, i.uv[2] / w, i.uv[3] / h];
                    }
                }
            }
        }
    }

    fn finish(&mut self, atlas_w: f32, atlas_h: f32) {
        for (p, r) in &self.batches {
            if matches!(p, Pipe::Text | Pipe::TextSub | Pipe::NativeOutline) {
                for i in &mut self.insts[r.start as usize..r.end as usize] {
                    if i.uv[2] > 1.0 || i.uv[3] > 1.0 || i.uv[0] > 1.0 {
                        i.uv = [i.uv[0] / atlas_w, i.uv[1] / atlas_h, i.uv[2] / atlas_w, i.uv[3] / atlas_h];
                        if *p == Pipe::TextSub {
                            i.p1[0] /= atlas_w;
                        }
                    }
                }
            }
        }
        let _ = self.atlas_size;
    }
}

pub struct Image {
    pub bind: wgpu::BindGroup,
    pub width: u32,
    pub height: u32,
}

pub struct Gpu {
    pub instance: wgpu::Instance,
    pub adapter: wgpu::Adapter,
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    layout0: wgpu::BindGroupLayout,
    layout1: wgpu::BindGroupLayout,
    shader: wgpu::ShaderModule,
    shader_sub: wgpu::ShaderModule,
    pipe_layout: wgpu::PipelineLayout,
    pipelines: Vec<(wgpu::TextureFormat, [wgpu::RenderPipeline; 7])>,
    globals: wgpu::Buffer,
    atlas: Option<(wgpu::Texture, wgpu::BindGroup, u32, u32)>,
    color_atlas: Option<(wgpu::Texture, wgpu::BindGroup, u32, u32)>,
    sampler: wgpu::Sampler,
    inst_buf: Option<wgpu::Buffer>,
    pub images: Vec<Option<Image>>,
}

const INST_ATTRS: [wgpu::VertexAttribute; 10] = wgpu::vertex_attr_array![
    0 => Float32x4, 1 => Float32x3, 2 => Float32x3, 3 => Float32x4, 4 => Float32x4,
    5 => Float32x4, 6 => Float32x4, 7 => Float32x4, 8 => Float32x4, 9 => Float32x4
];

fn bytes<T>(v: &[T]) -> &[u8] {
    unsafe { std::slice::from_raw_parts(v.as_ptr() as *const u8, std::mem::size_of_val(v)) }
}

impl Gpu {
    pub fn new(compatible: Option<&wgpu::Surface<'_>>, instance: wgpu::Instance) -> Gpu {
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::LowPower,
            compatible_surface: compatible,
            force_fallback_adapter: false,
        }))
        .expect("no Vulkan adapter");
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: None,
            required_features: wgpu::Features::DUAL_SOURCE_BLENDING,
            required_limits: wgpu::Limits::downlevel_defaults().using_resolution(adapter.limits()),
            // Small allocation blocks: the bar's buffers are tiny.
            memory_hints: wgpu::MemoryHints::MemoryUsage,
            trace: wgpu::Trace::Off,
        }))
        .expect("no device");
        let common = include_str!("common.wgsl");
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("bar"),
            source: wgpu::ShaderSource::Wgsl(format!("{common}{}", include_str!("shader.wgsl")).into()),
        });
        let shader_sub = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("subpixel"),
            source: wgpu::ShaderSource::Wgsl(format!("enable dual_source_blending;\n{common}{}", include_str!("subpixel.wgsl")).into()),
        });
        let layout0 = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: None,
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::VERTEX_FRAGMENT,
                    ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
            ],
        });
        let layout1 = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: None,
            entries: &[wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::FRAGMENT,
                ty: wgpu::BindingType::Texture {
                    sample_type: wgpu::TextureSampleType::Float { filterable: true },
                    view_dimension: wgpu::TextureViewDimension::D2,
                    multisampled: false,
                },
                count: None,
            }],
        });
        let pipe_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: None,
            bind_group_layouts: &[&layout0, &layout1],
            push_constant_ranges: &[],
        });
        let globals = device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: 16,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Linear,
            ..Default::default()
        });
        let mut gpu = Gpu {
            instance,
            adapter,
            device,
            queue,
            layout0,
            layout1,
            shader,
            shader_sub,
            pipe_layout,
            pipelines: Vec::new(),
            globals,
            atlas: None,
            color_atlas: None,
            sampler,
            inst_buf: None,
            images: Vec::new(),
        };
        // Image 0: one transparent texel, bound whenever no image is.
        gpu.add_image(1, 1, &[0, 0, 0, 0], false);
        gpu
    }

    pub fn new_instance() -> wgpu::Instance {
        wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends: wgpu::Backends::VULKAN,
            flags: wgpu::InstanceFlags::empty(),
            ..Default::default()
        })
    }

    fn pipelines_for(&mut self, format: wgpu::TextureFormat) -> usize {
        if let Some(i) = self.pipelines.iter().position(|(f, _)| *f == format) {
            return i;
        }
        let premul = wgpu::BlendState::PREMULTIPLIED_ALPHA_BLENDING;
        let dual = wgpu::BlendState {
            color: wgpu::BlendComponent {
                src_factor: wgpu::BlendFactor::One,
                dst_factor: wgpu::BlendFactor::OneMinusSrc1,
                operation: wgpu::BlendOperation::Add,
            },
            alpha: wgpu::BlendComponent {
                src_factor: wgpu::BlendFactor::One,
                dst_factor: wgpu::BlendFactor::OneMinusSrc1Alpha,
                operation: wgpu::BlendOperation::Add,
            },
        };
        let make = |vs: &str, fs: &str, blend: wgpu::BlendState| {
            let module = if fs == "fs_text_subpixel" { &self.shader_sub } else { &self.shader };
            self.device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some(fs),
                layout: Some(&self.pipe_layout),
                vertex: wgpu::VertexState {
                    module,
                    entry_point: Some(vs),
                    compilation_options: Default::default(),
                    buffers: &[wgpu::VertexBufferLayout {
                        array_stride: std::mem::size_of::<Inst>() as u64,
                        step_mode: wgpu::VertexStepMode::Instance,
                        attributes: &INST_ATTRS,
                    }],
                },
                fragment: Some(wgpu::FragmentState {
                    module,
                    entry_point: Some(fs),
                    compilation_options: Default::default(),
                    targets: &[Some(wgpu::ColorTargetState { format, blend: Some(blend), write_mask: wgpu::ColorWrites::ALL })],
                }),
                primitive: wgpu::PrimitiveState { topology: wgpu::PrimitiveTopology::TriangleStrip, ..Default::default() },
                depth_stencil: None,
                multisample: wgpu::MultisampleState::default(),
                multiview: None,
                cache: None,
            })
        };
        let p = [
            make("vs_rect", "fs_rect", premul),
            make("vs_quad", "fs_text", premul),
            make("vs_quad", "fs_text_subpixel", dual),
            make("vs_quad", "fs_image", premul),
            make("vs_quad", "fs_native_outline", premul),
            make("vs_quad", "fs_shadow", premul),
            make("vs_rect", "fs_clear", wgpu::BlendState::REPLACE),
        ];
        self.pipelines.push((format, p));
        self.pipelines.len() - 1
    }

    fn sync_atlas(&mut self, fonts: &mut Fonts) {
        let a = &mut fonts.atlas;
        if a.resized || self.atlas.is_none() {
            let tex = self.device.create_texture(&wgpu::TextureDescriptor {
                label: Some("glyphs"),
                size: wgpu::Extent3d { width: a.width, height: a.height, depth_or_array_layers: 1 },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: wgpu::TextureFormat::R8Unorm,
                usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
                view_formats: &[],
            });
            let view = tex.create_view(&Default::default());
            let bind = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: None,
                layout: &self.layout0,
                entries: &[
                    wgpu::BindGroupEntry { binding: 0, resource: self.globals.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(&view) },
                    wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::Sampler(&self.sampler) },
                ],
            });
            self.atlas = Some((tex, bind, a.width, a.height));
            a.dirty.clear();
            a.dirty.push((0, 0, a.width, a.height));
            a.resized = false;
        }
        let (tex, _, w, _) = self.atlas.as_ref().unwrap();
        for (x, y, rw, rh) in a.dirty.drain(..) {
            let start = (y * *w + x) as usize;
            self.queue.write_texture(
                wgpu::TexelCopyTextureInfo { texture: tex, mip_level: 0, origin: wgpu::Origin3d { x, y, z: 0 }, aspect: wgpu::TextureAspect::All },
                &a.pixels[start..],
                wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(*w), rows_per_image: Some(rh) },
                wgpu::Extent3d { width: rw, height: rh, depth_or_array_layers: 1 },
            );
        }
    }

    fn sync_color_atlas(&mut self, fonts: &mut Fonts) {
        let a = &mut fonts.color_atlas;
        if a.resized || self.color_atlas.is_none() {
            let tex = self.device.create_texture(&wgpu::TextureDescriptor {
                label: Some("colour glyphs"),
                size: wgpu::Extent3d { width: a.width, height: a.height, depth_or_array_layers: 1 },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: wgpu::TextureFormat::Rgba8Unorm,
                usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
                view_formats: &[],
            });
            let view = tex.create_view(&Default::default());
            let bind = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: None,
                layout: &self.layout1,
                entries: &[wgpu::BindGroupEntry { binding: 0, resource: wgpu::BindingResource::TextureView(&view) }],
            });
            self.color_atlas = Some((tex, bind, a.width, a.height));
            a.dirty.clear();
            a.dirty.push((0, 0, a.width, a.height));
            a.resized = false;
        }
        let (tex, _, w, _) = self.color_atlas.as_ref().unwrap();
        for (x, y, rw, rh) in a.dirty.drain(..) {
            let start = ((y * *w + x) * 4) as usize;
            self.queue.write_texture(
                wgpu::TexelCopyTextureInfo { texture: tex, mip_level: 0, origin: wgpu::Origin3d { x, y, z: 0 }, aspect: wgpu::TextureAspect::All },
                &a.pixels[start..],
                wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(*w * 4), rows_per_image: Some(rh) },
                wgpu::Extent3d { width: rw, height: rh, depth_or_array_layers: 1 },
            );
        }
    }

    /// Premultiplied RGBA8 pixels -> an image id for Scene::image.
    pub fn add_image(&mut self, width: u32, height: u32, rgba: &[u8], mipmaps: bool) -> u32 {
        let mips = if mipmaps { 32 - width.max(height).leading_zeros() } else { 1 };
        let tex = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("image"),
            size: wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
            mip_level_count: mips,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8Unorm,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        let mut level = rgba.to_vec();
        let (mut w, mut h) = (width, height);
        for m in 0..mips {
            self.queue.write_texture(
                wgpu::TexelCopyTextureInfo { texture: &tex, mip_level: m, origin: wgpu::Origin3d::ZERO, aspect: wgpu::TextureAspect::All },
                &level,
                wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(4 * w), rows_per_image: Some(h) },
                wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 },
            );
            if m + 1 < mips {
                let (nw, nh) = ((w / 2).max(1), (h / 2).max(1));
                let mut next = vec![0u8; (nw * nh * 4) as usize];
                for y in 0..nh {
                    for x in 0..nw {
                        for c in 0..4 {
                            let px = |xx: u32, yy: u32| level[((yy.min(h - 1) * w + xx.min(w - 1)) * 4 + c) as usize] as u32;
                            let s = px(2 * x, 2 * y) + px(2 * x + 1, 2 * y) + px(2 * x, 2 * y + 1) + px(2 * x + 1, 2 * y + 1);
                            next[((y * nw + x) * 4 + c) as usize] = ((s + 2) / 4) as u8;
                        }
                    }
                }
                level = next;
                (w, h) = (nw, nh);
            }
        }
        let view = tex.create_view(&Default::default());
        let bind = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &self.layout1,
            entries: &[wgpu::BindGroupEntry { binding: 0, resource: wgpu::BindingResource::TextureView(&view) }],
        });
        let img = Image { bind, width, height };
        if let Some(i) = self.images.iter().skip(1).position(|s| s.is_none()).map(|i| i + 1) {
            self.images[i] = Some(img);
            i as u32
        } else {
            self.images.push(Some(img));
            (self.images.len() - 1) as u32
        }
    }

    pub fn drop_image(&mut self, id: u32) {
        if let Some(s) = self.images.get_mut(id as usize) {
            *s = None;
        }
    }

    /// Draws `scene` into `target`, cleared to `clear` (premultiplied).
    pub fn render(&mut self, fonts: &mut Fonts, scene: &mut Scene, target: &wgpu::TextureView, format: wgpu::TextureFormat, size: (u32, u32), clear: [f64; 4]) {
        self.sync_atlas(fonts);
        let (_, _, aw, ah) = self.atlas.as_ref().map(|a| (0, 0, a.2, a.3)).unwrap();
        scene.finish(aw as f32, ah as f32);
        if scene.batches.iter().any(|b| b.0 == Pipe::Color) {
            self.sync_color_atlas(fonts);
            let (_, _, cw, ch) = self.color_atlas.as_ref().unwrap();
            scene.finish_color(*cw as f32, *ch as f32);
        }
        let pi = self.pipelines_for(format);
        let g = [size.0 as f32, size.1 as f32, aw as f32, ah as f32];
        self.queue.write_buffer(&self.globals, 0, bytes(&g));
        let need = (scene.insts.len().max(1) * std::mem::size_of::<Inst>()) as u64;
        if self.inst_buf.as_ref().map_or(true, |b| b.size() < need) {
            self.inst_buf = Some(self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("instances"),
                size: need.next_power_of_two().max(16 * 1024),
                usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            }));
        }
        let buf = self.inst_buf.as_ref().unwrap();
        if !scene.insts.is_empty() {
            self.queue.write_buffer(buf, 0, bytes(&scene.insts));
        }
        let mut enc = self.device.create_command_encoder(&Default::default());
        {
            let mut rp = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: None,
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: target,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color { r: clear[0], g: clear[1], b: clear[2], a: clear[3] }),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
            let atlas_bind = &self.atlas.as_ref().unwrap().1;
            rp.set_bind_group(0, atlas_bind, &[]);
            rp.set_vertex_buffer(0, buf.slice(..));
            let pipes = &self.pipelines[pi].1;
            rp.set_bind_group(1, &self.images[0].as_ref().unwrap().bind, &[]);
            let mut bound_image: Option<u32> = Some(0);
            for (p, r) in &scene.batches {
                match p {
                    Pipe::Rect => rp.set_pipeline(&pipes[0]),
                    Pipe::Text => rp.set_pipeline(&pipes[1]),
                    Pipe::TextSub => rp.set_pipeline(&pipes[2]),
                    Pipe::NativeOutline => rp.set_pipeline(&pipes[4]),
                    Pipe::Shadow => rp.set_pipeline(&pipes[5]),
                    Pipe::Clear => rp.set_pipeline(&pipes[6]),
                    Pipe::Color => {
                        let Some((_, bind, ..)) = self.color_atlas.as_ref() else { continue };
                        rp.set_pipeline(&pipes[3]);
                        rp.set_bind_group(1, bind, &[]);
                        bound_image = Some(u32::MAX);
                    }
                    Pipe::Image(id) => {
                        let Some(Some(img)) = self.images.get(*id as usize) else { continue };
                        rp.set_pipeline(&pipes[3]);
                        if bound_image != Some(*id) {
                            rp.set_bind_group(1, &img.bind, &[]);
                            bound_image = Some(*id);
                        }
                    }
                }
                rp.draw(0..4, r.clone());
            }
        }
        self.queue.submit([enc.finish()]);
    }

    /// Renders offscreen and returns straight-alpha RGBA8 rows (tests and references).
    pub fn render_to_rgba(&mut self, fonts: &mut Fonts, scene: &mut Scene, w: u32, h: u32, clear: [f64; 4]) -> Vec<u8> {
        let format = wgpu::TextureFormat::Rgba8Unorm;
        let tex = self.device.create_texture(&wgpu::TextureDescriptor {
            label: None,
            size: wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        let view = tex.create_view(&Default::default());
        self.render(fonts, scene, &view, format, (w, h), clear);
        let row = (w * 4).div_ceil(256) * 256;
        let out = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: (row * h) as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let mut enc = self.device.create_command_encoder(&Default::default());
        enc.copy_texture_to_buffer(
            wgpu::TexelCopyTextureInfo { texture: &tex, mip_level: 0, origin: wgpu::Origin3d::ZERO, aspect: wgpu::TextureAspect::All },
            wgpu::TexelCopyBufferInfo { buffer: &out, layout: wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(row), rows_per_image: Some(h) } },
            wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 },
        );
        self.queue.submit([enc.finish()]);
        out.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        let _ = self.device.poll(wgpu::PollType::Wait);
        let data = out.slice(..).get_mapped_range();
        let mut px = Vec::with_capacity((w * h * 4) as usize);
        for y in 0..h {
            for x in 0..w {
                let o = (y * row + x * 4) as usize;
                let a = data[o + 3] as f32 / 255.0;
                for c in 0..3 {
                    let v = if a > 0.0 { (data[o + c] as f32 / a).min(255.0) } else { 0.0 };
                    px.push(v.round() as u8);
                }
                px.push(data[o + 3]);
            }
        }
        px
    }
}

pub fn write_png(path: &str, w: u32, h: u32, rgba: &[u8]) {
    let f = std::fs::File::create(path).expect("png");
    let mut e = png::Encoder::new(std::io::BufWriter::new(f), w, h);
    e.set_color(png::ColorType::Rgba);
    e.set_depth(png::BitDepth::Eight);
    e.write_header().unwrap().write_image_data(rgba).unwrap();
}

/// Image's smooth scaling: the tent filter (image's Triangle, what the bar
/// used before), with SIMD - 1 ms instead of 11 for a carousel thumbnail, the
/// same pixels within one level. Straight alpha, as before.
pub fn scale(img: image::RgbaImage, w: u32, h: u32) -> image::RgbaImage {
    use fast_image_resize::{images::Image, FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer};
    let (iw, ih) = img.dimensions();
    if (iw, ih) == (w, h) {
        return img;
    }
    let Ok(src) = Image::from_vec_u8(iw, ih, img.into_raw(), PixelType::U8x4) else { return image::RgbaImage::new(w, h) };
    let mut dst = Image::new(w, h, PixelType::U8x4);
    let opts = ResizeOptions::new().resize_alg(ResizeAlg::Convolution(FilterType::Bilinear)).use_alpha(false);
    let _ = Resizer::new().resize(&src, &mut dst, &opts);
    image::RgbaImage::from_raw(w, h, dst.into_vec()).unwrap_or_else(|| image::RgbaImage::new(w, h))
}

/// Premultiplied alpha, what add_image takes. An opaque picture (every JPEG)
/// is already premultiplied.
pub fn premultiply(mut rgba: Vec<u8>) -> Vec<u8> {
    if rgba.chunks_exact(4).all(|p| p[3] == 255) {
        return rgba;
    }
    for p in rgba.chunks_exact_mut(4) {
        let a = p[3] as u32;
        for v in &mut p[..3] {
            *v = ((*v as u32 * a + 127) / 255) as u8;
        }
    }
    rgba
}
