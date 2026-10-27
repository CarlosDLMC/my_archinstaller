//! Fonts, distance-field glyphs and single-line layout.
//!
//! Qt Quick draws Text (renderType QtRendering, the default) from distance
//! fields: each glyph is turned into a signed-distance bitmap once, at a base
//! size of 54 px with a 5 px spread, and every pixel size samples that one
//! bitmap through a smoothstep (see gpu.rs for the thresholds). Doing the same
//! here is what makes the glyph edges, weights and the outline style match -
//! and it is also the cheap way: one small atlas serves every size.
//!
//! Metrics follow Qt's QFontEngineFT exactly, because layout positions in the
//! bar are built from them: advances are FreeType's linearHoriAdvance >> 10
//! (so a 500-unit glyph at 24 px is 767/64, not 12); a font with embedded
//! bitmaps (Terminess) takes ascent/descent from the strike of that size, or
//! from the grid-fitted outline metrics; any other font from its OS/2 typo
//! (or win) metrics, truncated to 1/64. A line is ceil(ascent + descent) tall.

use std::collections::HashMap;
use std::process::Command;

use freetype_sys as ft;
use swash::scale::ScaleContext;
use swash::{FontRef, GlyphId};

/// QT_DISTANCEFIELD_DEFAULT_BASEFONTSIZE: the size every field is made at.
pub const DF_BASE: f32 = 54.0;
/// QT_DISTANCEFIELD_DEFAULT_RADIUS / _SCALE: the spread, in base pixels.
pub const DF_RADIUS: f32 = 5.0;
const DF_PAD: i32 = 6;

pub struct Face {
    pub font: FontRef<'static>,
    data: &'static [u8],
    index: u32,
    ft_face: Option<ft::FT_Face>,
    pub upem: i64,
    hhea: (i64, i64),
    typo: Option<(i64, i64)>,
    win: (i64, i64),
    /// Embedded bitmap strikes: (ppem, ascender, descender) from EBLC.
    strikes: Vec<(u8, i64, i64)>,
    has_bitmaps: bool,
    /// post.isFixedPitch - FT_IS_FIXED_WIDTH, which turns Qt's synthetic bold off.
    pub fixed_pitch: bool,
    /// HarfBuzz (rustybuzz) view of the same data, for shaping.
    hb: rustybuzz::Face<'static>,
    /// A colour bitmap font (CBDT/sbix: Noto Color Emoji): drawn from its strike.
    pub color: bool,
}

fn be16(d: &[u8], o: usize) -> i64 {
    i16::from_be_bytes([d[o], d[o + 1]]) as i64
}

fn ube16(d: &[u8], o: usize) -> i64 {
    u16::from_be_bytes([d[o], d[o + 1]]) as i64
}

impl Face {
    fn new(font: FontRef<'static>) -> Face {
        let table = |tag: &[u8; 4]| font.table(swash::tag_from_bytes(tag));
        let upem = table(b"head").map(|d| ube16(d, 18)).unwrap_or(1000);
        let hhea = table(b"hhea").map(|d| (be16(d, 4), be16(d, 6))).unwrap_or((800, -200));
        let (mut typo, mut win) = (None, (0, 0));
        if let Some(d) = table(b"OS/2") {
            if d.len() >= 78 {
                let fs = ube16(d, 62);
                if fs & 128 != 0 {
                    typo = Some((be16(d, 68), be16(d, 70)));
                }
                win = (ube16(d, 74), ube16(d, 76));
            }
        }
        let mut strikes = vec![];
        if let Some(d) = table(b"EBLC") {
            let n = u32::from_be_bytes([d[4], d[5], d[6], d[7]]) as usize;
            for i in 0..n {
                let b = 8 + 48 * i;
                if b + 48 > d.len() {
                    break;
                }
                strikes.push((d[b + 44], d[b + 16] as i8 as i64, d[b + 17] as i8 as i64));
            }
        }
        let has_bitmaps = table(b"EBLC").is_some() || table(b"CBLC").is_some() || table(b"bdat").is_some();
        let fixed_pitch = table(b"post").map_or(false, |d| d.len() >= 16 && u32::from_be_bytes([d[12], d[13], d[14], d[15]]) != 0);
        let color = table(b"CBDT").is_some() || table(b"sbix").is_some();
        let hb = rustybuzz::Face::from_slice(font.data, 0).expect("font for shaping");
        Face { font, data: font.data, index: 0, ft_face: None, upem, hhea, typo, win, strikes, has_bitmaps, fixed_pitch, hb, color }
    }

    fn scale26(&self, size: f32) -> i64 {
        // FT_DivFix(size in 26.6, units per em)
        let s = (size * 64.0).round() as i64;
        (s * 65536 + self.upem / 2) / self.upem
    }

    /// QFontEngineFT advance for `units` font units at `size` px, in 1/64 px.
    pub fn advance26(&self, units: i64, size: f32) -> i64 {
        let lin = (units * self.scale26(size) + 32) / 64;
        lin >> 10
    }

    /// (ascent, descent) in px as Qt reports them.
    pub fn metrics(&self, size: f32) -> (f32, f32) {
        if self.has_bitmaps {
            if size.fract() == 0.0 {
                if let Some(&(_, a, d)) = self.strikes.iter().find(|s| s.0 as f32 == size) {
                    return (a as f32, -d as f32);
                }
            }
            let ys = self.scale26(size);
            let mulfix = |v: i64| {
                let r = (v.abs() * ys + 0x8000) >> 16;
                if v < 0 { -r } else { r }
            };
            let asc = (mulfix(self.hhea.0) + 63) & !63;
            let desc = mulfix(self.hhea.1) & !63;
            return (asc as f32 / 64.0, -desc as f32 / 64.0);
        }
        let fixed = |v: i64| ((v as f64 * size as f64 / self.upem as f64) * 64.0) as i64 as f32 / 64.0;
        if let Some((a, d)) = self.typo {
            return (fixed(a), fixed(-d));
        }
        if self.win != (0, 0) {
            return (fixed(self.win.0), fixed(self.win.1));
        }
        (fixed(self.hhea.0), fixed(-self.hhea.1))
    }
}

#[derive(Clone, Copy, Debug)]
pub struct DfGlyph {
    /// Texel rect in the atlas.
    pub ax: u32,
    pub ay: u32,
    pub w: u32,
    pub h: u32,
    /// Top-left of the bitmap relative to the pen on the baseline, base px, y down.
    pub x0: f32,
    pub y0: f32,
}

/// A FreeType-rasterised glyph (Qt's native text path), 8-bit coverage.
#[derive(Clone, Copy, Debug)]
pub struct NativeGlyph {
    /// Texel rect of the coverage in the atlas; two zero texels surround it.
    pub ax: u32,
    pub ay: u32,
    pub w: u32,
    pub h: u32,
    /// FreeType bitmap_left / bitmap_top.
    pub left: i32,
    pub top: i32,
}

/// A laid-out glyph: which face/glyph, pen x in item px.
#[derive(Clone, Copy, Debug)]
pub struct PlacedGlyph {
    pub face: u16,
    pub gid: GlyphId,
    pub x: f32,
    /// Synthetic bold: FreeType's embolden, which Qt applies to a bold
    /// request on a regular face unless the face is fixed-pitch.
    pub bold: bool,
    /// From a colour bitmap font (emoji).
    pub color: bool,
}

/// A colour glyph scaled from its strike, in the RGBA atlas.
#[derive(Clone, Copy, Debug)]
pub struct ColorGlyph {
    pub ax: u32,
    pub ay: u32,
    pub w: u32,
    pub h: u32,
    pub left: f32,
    pub top: f32,
}

/// Which plain Texts Qt still draws with subpixel anti-aliasing. Qt 6.12
/// rebuilds a Text's node whenever its text, colour or layout changes, and
/// the glyph nodes it recycles for that come back with gray anti-aliasing
/// (QSGDistanceFieldGlyphNode::recycle). So a Text is subpixel from its first
/// frame until it first changes, then gray for as long as the item lives. A
/// text here is a call site plus its occurrence number in the frame.
#[derive(Default)]
pub struct TextMemo {
    seen: HashMap<(u64, u32), (u64, bool)>,
    sites: HashMap<u64, u32>,
}

impl TextMemo {
    pub fn begin_frame(&mut self) {
        self.sites.clear();
    }

    /// The style to draw `line` with: Normal turns Gray once this text changed.
    pub fn style(&mut self, site: u64, line: &Line, color: crate::color::Color, style: crate::gpu::TextStyle) -> crate::gpu::TextStyle {
        if !matches!(style, crate::gpu::TextStyle::Normal) {
            return style;
        }
        let n = self.sites.entry(site).or_insert(0);
        let key = (site, *n);
        *n += 1;
        self.style_keyed(key, line, color, style)
    }

    /// The same for a text named by its control (a key's caption, a row's
    /// label), so texts hidden in some frames do not shift the others.
    pub fn style_keyed(&mut self, key: (u64, u32), line: &Line, color: crate::color::Color, style: crate::gpu::TextStyle) -> crate::gpu::TextStyle {
        self.style_lines(key, std::slice::from_ref(line), color, style)
    }

    /// One Text laid out over several lines: one node, one verdict.
    pub fn style_lines(&mut self, key: (u64, u32), lines: &[Line], color: crate::color::Color, style: crate::gpu::TextStyle) -> crate::gpu::TextStyle {
        use std::hash::{Hash, Hasher};
        if !matches!(style, crate::gpu::TextStyle::Normal) {
            return style;
        }
        // An empty Text has no node; the next text gets a new one.
        if lines.iter().all(|l| l.glyphs.is_empty()) {
            self.seen.remove(&key);
            return style;
        }
        let mut h = std::collections::hash_map::DefaultHasher::new();
        for line in lines {
            for g in &line.glyphs {
                (g.face, g.gid, g.x.to_bits(), g.bold).hash(&mut h);
            }
            (line.size.to_bits(), line.glyphs.len()).hash(&mut h);
        }
        (color.r.to_bits(), color.g.to_bits(), color.b.to_bits(), color.a.to_bits()).hash(&mut h);
        let sig = h.finish();
        let e = self.seen.entry(key).or_insert((sig, false));
        if e.0 != sig {
            *e = (sig, true);
        }
        if e.1 { crate::gpu::TextStyle::Gray } else { style }
    }

    /// Forgets the controls' texts of these parts (a ListView's delegates,
    /// made anew when its model is replaced).
    pub fn forget_parts(&mut self, parts: &[u64]) {
        self.seen.retain(|k, _| !parts.contains(&k.0));
    }

    /// A call site's id, for #[track_caller] callers.
    pub fn site(loc: &std::panic::Location) -> u64 {
        use std::hash::{Hash, Hasher};
        let mut h = std::collections::hash_map::DefaultHasher::new();
        (loc.file(), loc.line(), loc.column()).hash(&mut h);
        h.finish()
    }
}

#[derive(Clone, Debug, Default)]
pub struct Line {
    pub glyphs: Vec<PlacedGlyph>,
    /// implicitWidth: the advances plus the last glyph's overhang.
    pub width: f32,
    /// The advances alone - what horizontalAlignment centres.
    pub adv: f32,
    pub ascent: f32,
    pub descent: f32,
    pub size: f32,
}

impl Line {
    /// QTextLine::height(): ceil(ascent + descent).
    pub fn height(&self) -> f32 {
        (self.ascent + self.descent).ceil()
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct FontKey {
    pub family: &'static str,
    pub bold: bool,
    /// font.kerning: false + font.features { liga: 0, calt: 0 }.
    pub plain: bool,
}

pub struct Atlas {
    /// Bytes per texel: 1 (distance fields, coverage) or 4 (colour glyphs).
    pub bpp: u32,
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
    shelf_x: u32,
    shelf_y: u32,
    shelf_h: u32,
    /// Regions written since the last upload (x, y, w, h).
    pub dirty: Vec<(u32, u32, u32, u32)>,
    /// The texture must be recreated (it grew).
    pub resized: bool,
}

impl Atlas {
    fn new(bpp: u32, width: u32, height: u32) -> Atlas {
        Atlas { bpp, width, height, pixels: vec![0; (width * height * bpp) as usize], shelf_x: 0, shelf_y: 0, shelf_h: 0, dirty: vec![], resized: true }
    }

    fn alloc(&mut self, w: u32, h: u32) -> (u32, u32) {
        if self.shelf_x + w > self.width {
            self.shelf_y += self.shelf_h + 1;
            self.shelf_x = 0;
            self.shelf_h = 0;
        }
        while self.shelf_y + h > self.height {
            let old = self.height;
            self.height *= 2;
            self.pixels.resize((self.width * self.height * self.bpp) as usize, 0);
            self.resized = true;
            let _ = old;
        }
        let at = (self.shelf_x, self.shelf_y);
        self.shelf_x += w + 1;
        self.shelf_h = self.shelf_h.max(h);
        at
    }
}

pub struct Fonts {
    pub faces: Vec<Face>,
    by_key: HashMap<FontKey, u16>,
    by_file: HashMap<(String, u32), u16>,
    fallback: HashMap<(FontKey, char), u16>,
    glyphs: HashMap<(u16, GlyphId, bool), Option<DfGlyph>>,
    native: HashMap<(u16, GlyphId, i64, u8), Option<NativeGlyph>>,
    library: ft::FT_Library,
    scale: ScaleContext,
    pub atlas: Atlas,
    pub color_atlas: Atlas,
    colors: HashMap<(u16, GlyphId, i64), Option<ColorGlyph>>,
    emoji: Option<Option<u16>>,
}

/// QFontEngineFT::loadFlags for a gray glyph cache with fontconfig's
/// hintslight. RUST_BAR_FT_FLAGS overrides it (calibration only).
fn native_load_flags() -> i32 {
    if let Some(v) = std::env::var("RUST_BAR_FT_FLAGS").ok().and_then(|v| i32::from_str_radix(v.trim_start_matches("0x"), 16).ok()) {
        return v;
    }
    (ft::FT_LOAD_DEFAULT | ft::FT_LOAD_TARGET_LIGHT) as i32
}

/// Unicode Emoji_Presentation=Yes (emoji-data.txt): drawn as colour emoji
/// even without a variation selector.
fn is_emoji_presentation(c: char) -> bool {
    let u = c as u32;
    const R: &[(u32, u32)] = &[
        (0x231A, 0x231B), (0x23E9, 0x23EC), (0x23F0, 0x23F0), (0x23F3, 0x23F3), (0x25FD, 0x25FE), (0x2614, 0x2615),
        (0x2648, 0x2653), (0x267F, 0x267F), (0x2693, 0x2693), (0x26A1, 0x26A1), (0x26AA, 0x26AB), (0x26BD, 0x26BE),
        (0x26C4, 0x26C5), (0x26CE, 0x26CE), (0x26D4, 0x26D4), (0x26EA, 0x26EA), (0x26F2, 0x26F3), (0x26F5, 0x26F5),
        (0x26FA, 0x26FA), (0x26FD, 0x26FD), (0x2705, 0x2705), (0x270A, 0x270B), (0x2728, 0x2728), (0x274C, 0x274C),
        (0x274E, 0x274E), (0x2753, 0x2755), (0x2757, 0x2757), (0x2795, 0x2797), (0x27B0, 0x27B0), (0x27BF, 0x27BF),
        (0x2B1B, 0x2B1C), (0x2B50, 0x2B50), (0x2B55, 0x2B55), (0x1F004, 0x1F004), (0x1F0CF, 0x1F0CF), (0x1F18E, 0x1F18E),
        (0x1F191, 0x1F19A), (0x1F1E6, 0x1F1FF), (0x1F201, 0x1F201), (0x1F21A, 0x1F21A), (0x1F22F, 0x1F22F), (0x1F232, 0x1F236),
        (0x1F238, 0x1F23A), (0x1F250, 0x1F251), (0x1F300, 0x1F320), (0x1F32D, 0x1F335), (0x1F337, 0x1F37C), (0x1F37E, 0x1F393),
        (0x1F3A0, 0x1F3CA), (0x1F3CF, 0x1F3D3), (0x1F3E0, 0x1F3F0), (0x1F3F4, 0x1F3F4), (0x1F3F8, 0x1F43E), (0x1F440, 0x1F440),
        (0x1F442, 0x1F4FC), (0x1F4FF, 0x1F53D), (0x1F54B, 0x1F54E), (0x1F550, 0x1F567), (0x1F57A, 0x1F57A), (0x1F595, 0x1F596),
        (0x1F5A4, 0x1F5A4), (0x1F5FB, 0x1F64F), (0x1F680, 0x1F6C5), (0x1F6CC, 0x1F6CC), (0x1F6D0, 0x1F6D2), (0x1F6D5, 0x1F6D7),
        (0x1F6DC, 0x1F6DF), (0x1F6EB, 0x1F6EC), (0x1F6F4, 0x1F6FC), (0x1F7E0, 0x1F7EB), (0x1F7F0, 0x1F7F0), (0x1F90C, 0x1F93A),
        (0x1F93C, 0x1F945), (0x1F947, 0x1F9FF), (0x1FA70, 0x1FAFF),
    ];
    R.iter().any(|&(a, b)| u >= a && u <= b)
}

/// FT_Outline_Decompose into line segments; curves flattened finely enough
/// that the distance field cannot tell.
struct Walk {
    segs: Vec<[f32; 4]>,
    cur: (f32, f32),
    start: (f32, f32),
}

impl Walk {
    fn pt(v: *const ft::FT_Vector) -> (f32, f32) {
        unsafe { ((*v).x as f32 / 64.0, -((*v).y as f32) / 64.0) }
    }

    fn close(&mut self) {
        if self.cur != self.start {
            self.segs.push([self.cur.0, self.cur.1, self.start.0, self.start.1]);
        }
        self.cur = self.start;
    }

    fn line(&mut self, p: (f32, f32)) {
        self.segs.push([self.cur.0, self.cur.1, p.0, p.1]);
        self.cur = p;
    }
}

extern "C" fn move_to(to: *const ft::FT_Vector, user: *mut std::ffi::c_void) -> std::ffi::c_int {
    let w = unsafe { &mut *(user as *mut Walk) };
    w.close();
    w.cur = Walk::pt(to);
    w.start = w.cur;
    0
}

extern "C" fn line_to(to: *const ft::FT_Vector, user: *mut std::ffi::c_void) -> std::ffi::c_int {
    let w = unsafe { &mut *(user as *mut Walk) };
    w.line(Walk::pt(to));
    0
}

extern "C" fn conic_to(c: *const ft::FT_Vector, to: *const ft::FT_Vector, user: *mut std::ffi::c_void) -> std::ffi::c_int {
    let w = unsafe { &mut *(user as *mut Walk) };
    let (p0, c1, p1) = (w.cur, Walk::pt(c), Walk::pt(to));
    let n = (((c1.0 - p0.0).hypot(c1.1 - p0.1) + (p1.0 - c1.0).hypot(p1.1 - c1.1)) / 0.75).ceil().clamp(2.0, 96.0) as usize;
    for i in 1..=n {
        let t = i as f32 / n as f32;
        let u = 1.0 - t;
        w.line((u * u * p0.0 + 2.0 * u * t * c1.0 + t * t * p1.0, u * u * p0.1 + 2.0 * u * t * c1.1 + t * t * p1.1));
    }
    0
}

extern "C" fn cubic_to(c1: *const ft::FT_Vector, c2: *const ft::FT_Vector, to: *const ft::FT_Vector, user: *mut std::ffi::c_void) -> std::ffi::c_int {
    let w = unsafe { &mut *(user as *mut Walk) };
    let (p0, a, b, p1) = (w.cur, Walk::pt(c1), Walk::pt(c2), Walk::pt(to));
    let len = (a.0 - p0.0).hypot(a.1 - p0.1) + (b.0 - a.0).hypot(b.1 - a.1) + (p1.0 - b.0).hypot(p1.1 - b.1);
    let n = (len / 0.75).ceil().clamp(2.0, 128.0) as usize;
    for i in 1..=n {
        let t = i as f32 / n as f32;
        let u = 1.0 - t;
        let x = u * u * u * p0.0 + 3.0 * u * u * t * a.0 + 3.0 * u * t * t * b.0 + t * t * t * p1.0;
        let y = u * u * u * p0.1 + 3.0 * u * u * t * a.1 + 3.0 * u * t * t * b.1 + t * t * t * p1.1;
        w.line((x, y));
    }
    0
}

fn fc_match(pattern: &str) -> Option<(String, u32)> {
    let out = Command::new("fc-match").arg("-f").arg("%{file}\n%{index}").arg(pattern).output().ok()?;
    let s = String::from_utf8(out.stdout).ok()?;
    let mut it = s.lines();
    let file = it.next()?.to_string();
    let index = it.next().and_then(|i| i.parse().ok()).unwrap_or(0);
    if file.is_empty() {
        None
    } else {
        Some((file, index))
    }
}

impl Fonts {
    pub fn new() -> Fonts {
        Fonts {
            faces: vec![],
            by_key: HashMap::new(),
            by_file: HashMap::new(),
            fallback: HashMap::new(),
            glyphs: HashMap::new(),
            native: HashMap::new(),
            library: {
                let mut lib: ft::FT_Library = std::ptr::null_mut();
                unsafe { ft::FT_Init_FreeType(&mut lib) };
                lib
            },
            scale: ScaleContext::new(),
            atlas: Atlas::new(1, 1024, 256),
            color_atlas: Atlas::new(4, 256, 64),
            colors: HashMap::new(),
            emoji: None,
        }
    }

    fn load_file(&mut self, file: &str, index: u32) -> Option<u16> {
        if let Some(&i) = self.by_file.get(&(file.to_string(), index)) {
            return Some(i);
        }
        let f = std::fs::File::open(file).ok()?;
        // Mapped, not read: the pages are the page cache's, shared and evictable.
        let map = unsafe { memmap2::Mmap::map(&f).ok()? };
        let data: &'static [u8] = Box::leak(Box::new(map));
        let font = FontRef::from_index(data, index as usize)?;
        let mut face = Face::new(font);
        face.data = data;
        face.index = index;
        face.hb = rustybuzz::Face::from_slice(data, index)?;
        self.faces.push(face);
        let i = (self.faces.len() - 1) as u16;
        self.by_file.insert((file.to_string(), index), i);
        Some(i)
    }

    pub fn face_for(&mut self, key: FontKey) -> u16 {
        if let Some(&i) = self.by_key.get(&key) {
            return i;
        }
        // The bar's Qt resolves bold to the family's regular file (the live bar
        // maps only TerminessNerdFont-Regular.ttf) and emboldens it - see layout().
        let (file, index) = fc_match(key.family).unwrap_or_else(|| ("/usr/share/fonts/TTF/DejaVuSans.ttf".into(), 0));
        let i = self.load_file(&file, index).expect("no usable font");
        self.by_key.insert(key, i);
        i
    }

    /// The face that draws `ch`: the requested one, else fontconfig's pick
    /// for that character - Qt's fallback goes through fontconfig too.
    fn face_with(&mut self, key: FontKey, ch: char) -> u16 {
        let primary = self.face_for(key);
        if self.faces[primary as usize].font.charmap().map(ch) != 0 || ch.is_control() {
            return primary;
        }
        if let Some(&i) = self.fallback.get(&(key, ch)) {
            return i;
        }
        let pat = format!("{}:charset={:x}", key.family, ch as u32);
        let i = fc_match(&pat).and_then(|(f, idx)| self.load_file(&f, idx)).unwrap_or(primary);
        self.fallback.insert((key, ch), i);
        i
    }

    /// One line of text at `size` px with Qt's letterSpacing (added after every glyph).
    pub fn layout(&mut self, text: &str, key: FontKey, size: f32, letter_spacing: f32) -> Line {
        let primary = self.face_for(key);
        let (ascent, descent) = self.faces[primary as usize].metrics(size);
        let mut line = Line { ascent, descent, size, ..Default::default() };
        let spacing26 = (letter_spacing * 64.0).round() as i64;
        // Itemise by face, as QTextEngine does with its fallback fonts; emoji
        // joiners, variation selectors and skin tones stay with their emoji.
        let mut runs: Vec<(u16, String)> = Vec::new();
        let chars: Vec<char> = text.chars().take_while(|c| *c != '\n').collect();
        for (i, &ch) in chars.iter().enumerate() {
            let joiner = matches!(ch, '\u{200d}' | '\u{fe0e}' | '\u{fe0f}' | '\u{1f3fb}'..='\u{1f3ff}' | '\u{e0020}'..='\u{e007f}');
            let next = chars.get(i + 1).copied();
            // Qt's emoji segmentation: emoji presentation (or VS16) goes to the emoji font.
            let emoji = (is_emoji_presentation(ch) && next != Some('\u{fe0e}')) || next == Some('\u{fe0f}');
            let fi = match runs.last() {
                Some((f, _)) if joiner => *f,
                _ if emoji => self.emoji_face().unwrap_or_else(|| self.face_with(key, ch)),
                _ => self.face_with(key, ch),
            };
            match runs.last_mut() {
                Some((f, s)) if *f == fi => s.push(ch),
                _ => runs.push((fi, ch.to_string())),
            }
        }
        let mut x26 = 0i64;
        for (fi, s) in runs {
            let shaped: Vec<(rustybuzz::GlyphInfo, rustybuzz::GlyphPosition)> = {
                let face = &self.faces[fi as usize];
                let mut buf = rustybuzz::UnicodeBuffer::new();
                buf.push_str(&s);
                let off = |t: &[u8; 4]| rustybuzz::Feature::new(rustybuzz::ttf_parser::Tag::from_bytes(t), 0, ..);
                let plain = [off(b"liga"), off(b"calt"), off(b"kern")];
                let out = rustybuzz::shape(&face.hb, if key.plain { &plain[..] } else { &[] }, buf);
                out.glyph_infos().iter().copied().zip(out.glyph_positions().iter().copied()).collect()
            };
            for (info, pos) in shaped {
                let face = &self.faces[fi as usize];
                let scale = size as f64 / face.upem as f64;
                let gid = info.glyph_id as GlyphId;
                let hmtx = face.font.glyph_metrics(&[]).advance_width(gid) as i64;
                let adv26 = if face.color {
                    0
                } else {
                    // Qt's advance for the glyph, plus whatever GPOS added to it.
                    face.advance26(hmtx, size) + ((pos.x_advance as i64 - hmtx) as f64 * scale * 64.0).round() as i64
                };
                let xoff = pos.x_offset as f64 * scale;
                let bold = key.bold && !face.fixed_pitch;
                let is_color = face.color;
                line.glyphs.push(PlacedGlyph { face: fi, gid, x: (x26 as f64 / 64.0 + xoff) as f32, bold, color: is_color });
                let adv26 = if is_color { self.color_advance26(fi, gid, size) } else { adv26 };
                x26 += adv26 + spacing26;
            }
        }
        // QTextLine's ascent/descent: the largest of every font the line uses.
        let mut used: Vec<u16> = line.glyphs.iter().map(|g| g.face).collect();
        used.sort_unstable();
        used.dedup();
        for f in used {
            if f == primary {
                continue;
            }
            let (a, d) = self.face_metrics(f, size);
            line.ascent = line.ascent.max(a);
            line.descent = line.descent.max(d);
        }
        line.adv = x26 as f32 / 64.0;
        // QTextLine adds the last glyph's negative right bearing, so a Text's
        // width covers a glyph that overhangs its advance (the Nerd icons do).
        if let Some(last) = line.glyphs.last().copied() {
            if !last.color {
                let rb = self.right_bearing26(last.face, last.gid, size);
                if rb < 0 {
                    x26 -= rb;
                }
            }
        }
        line.width = x26 as f32 / 64.0;
        line
    }

    /// Ascent/descent of a face at `size` as Qt reports them; a colour bitmap
    /// font gives its strike's metrics times the strike scale.
    fn face_metrics(&mut self, face: u16, size: f32) -> (f32, f32) {
        if !self.faces[face as usize].color {
            return self.faces[face as usize].metrics(size);
        }
        let f = self.strike_scale(face, size);
        let Some(fc) = self.ft_face(face) else { return (0.0, 0.0) };
        unsafe {
            if (*fc).num_fixed_sizes > 0 {
                ft::FT_Select_Size(fc, 0);
            }
            let m = &(*(*fc).size).metrics;
            (m.ascender as f32 / 64.0 * f, -(m.descender as f32) / 64.0 * f)
        }
    }

    /// The colour emoji face (fontconfig's "emoji"), if there is one.
    fn emoji_face(&mut self) -> Option<u16> {
        if let Some(f) = self.emoji {
            return f;
        }
        let f = fc_match("emoji:color=true").and_then(|(file, idx)| self.load_file(&file, idx)).filter(|&i| self.faces[i as usize].color);
        self.emoji = Some(f);
        f
    }

    /// QFontEngineFT's scale for a scalable bitmap font: pixel size over the
    /// strike's height (128 for Noto Color Emoji, not its 109 ppem).
    fn strike_scale(&mut self, face: u16, size: f32) -> f32 {
        let Some(fc) = self.ft_face(face) else { return 1.0 };
        unsafe {
            if (*fc).num_fixed_sizes > 0 {
                let h = (*(*fc).available_sizes).height as f32;
                return size / h.max(1.0);
            }
        }
        1.0
    }

    /// The strike advance of a colour glyph, scaled, in 1/64 px.
    fn color_advance26(&mut self, face: u16, gid: GlyphId, size: f32) -> i64 {
        let f = self.strike_scale(face, size);
        let Some(fc) = self.ft_face(face) else { return 0 };
        unsafe {
            if (*fc).num_fixed_sizes > 0 {
                ft::FT_Select_Size(fc, 0);
            }
            if ft::FT_Load_Glyph(fc, gid as u32, ft::FT_LOAD_COLOR as i32) != 0 {
                return 0;
            }
            ((*(*fc).glyph).metrics.horiAdvance as f32 * f).round() as i64
        }
    }

    /// A colour glyph (emoji) the way QFontEngineFT draws a scalable bitmap
    /// font: the strike's BGRA bitmap, smooth-scaled to the pixel size.
    pub fn color_glyph(&mut self, face: u16, gid: GlyphId, size: f32) -> Option<ColorGlyph> {
        let key = (face, gid, (size * 64.0).round() as i64);
        if let Some(g) = self.colors.get(&key) {
            return *g;
        }
        let g = unsafe { self.rasterise_color(face, gid, size) };
        self.colors.insert(key, g);
        g
    }

    unsafe fn rasterise_color(&mut self, face: u16, gid: GlyphId, size: f32) -> Option<ColorGlyph> {
        let fc = self.ft_face(face)?;
        if (*fc).num_fixed_sizes > 0 {
            ft::FT_Select_Size(fc, 0);
        }
        let f = if (*fc).num_fixed_sizes > 0 { size / ((*(*fc).available_sizes).height as f32).max(1.0) } else { 1.0 };
        if ft::FT_Load_Glyph(fc, gid as u32, ft::FT_LOAD_COLOR as i32) != 0 {
            return None;
        }
        let slot = (*fc).glyph;
        if (*slot).format != ft::FT_GLYPH_FORMAT_BITMAP && ft::FT_Render_Glyph(slot, ft::FT_RENDER_MODE_NORMAL) != 0 {
            return None;
        }
        let bm = &(*slot).bitmap;
        if bm.pixel_mode as u32 != ft::FT_PIXEL_MODE_BGRA as u32 || bm.width == 0 || bm.rows == 0 {
            return None;
        }
        let (sw, sh) = (bm.width as usize, bm.rows as usize);
        let (dw, dh) = (((sw as f32 * f).round() as usize).max(1), ((sh as f32 * f).round() as usize).max(1));
        // Area-average down (QImage::scaled, SmoothTransformation), BGRA -> RGBA.
        let mut out = vec![0u8; dw * dh * 4];
        for y in 0..dh {
            let (y0, y1) = (y as f32 * sh as f32 / dh as f32, (y + 1) as f32 * sh as f32 / dh as f32);
            for x in 0..dw {
                let (x0, x1) = (x as f32 * sw as f32 / dw as f32, (x + 1) as f32 * sw as f32 / dw as f32);
                let mut acc = [0f32; 4];
                let mut wsum = 0f32;
                let mut sy = y0.floor() as usize;
                while (sy as f32) < y1 && sy < sh {
                    let wy = (y1.min(sy as f32 + 1.0) - y0.max(sy as f32)).max(0.0);
                    let mut sx = x0.floor() as usize;
                    while (sx as f32) < x1 && sx < sw {
                        let wx = (x1.min(sx as f32 + 1.0) - x0.max(sx as f32)).max(0.0);
                        let p = bm.buffer.offset(sy as isize * bm.pitch as isize + sx as isize * 4);
                        let w = wx * wy;
                        acc[0] += *p.add(2) as f32 * w;
                        acc[1] += *p.add(1) as f32 * w;
                        acc[2] += *p as f32 * w;
                        acc[3] += *p.add(3) as f32 * w;
                        wsum += w;
                        sx += 1;
                    }
                    sy += 1;
                }
                let o = (y * dw + x) * 4;
                for c in 0..4 {
                    out[o + c] = (acc[c] / wsum.max(1e-6)).round().clamp(0.0, 255.0) as u8;
                }
            }
        }
        let (ax, ay) = self.color_atlas.alloc(dw as u32, dh as u32);
        let aw = self.color_atlas.width as usize;
        for y in 0..dh {
            let dst = ((ay as usize + y) * aw + ax as usize) * 4;
            self.color_atlas.pixels[dst..dst + dw * 4].copy_from_slice(&out[y * dw * 4..(y + 1) * dw * 4]);
        }
        self.color_atlas.dirty.push((ax, ay, dw as u32, dh as u32));
        Some(ColorGlyph { ax, ay, w: dw as u32, h: dh as u32, left: (*slot).bitmap_left as f32 * f, top: (*slot).bitmap_top as f32 * f })
    }

    /// Text.WordWrap: QTextLayout's line breaking - at the Unicode line-break
    /// opportunities (after spaces, but also after hyphens and slashes),
    /// trailing spaces hanging past the edge; a piece wider than the line
    /// stays whole.
    pub fn wrap(&mut self, text: &str, key: FontKey, size: f32, letter_spacing: f32, max: f32) -> Vec<Line> {
        self.wrap_strings(text, key, size, letter_spacing, max, false).iter().map(|l| self.layout(l, key, size, letter_spacing)).collect()
    }

    /// Text.Wrap: the same, but a piece wider than the line breaks anywhere.
    pub fn wrap_anywhere(&mut self, text: &str, key: FontKey, size: f32, letter_spacing: f32, max: f32) -> Vec<Line> {
        self.wrap_strings(text, key, size, letter_spacing, max, true).iter().map(|l| self.layout(l, key, size, letter_spacing)).collect()
    }

    pub fn wrap_strings(&mut self, text: &str, key: FontKey, size: f32, letter_spacing: f32, max: f32, anywhere: bool) -> Vec<String> {
        use unicode_linebreak::{linebreaks, BreakOpportunity};
        let mut out: Vec<String> = Vec::new();
        let mut cur = String::new();
        let mut start = 0;
        for (pos, opp) in linebreaks(text) {
            let seg = &text[start..pos];
            start = pos;
            let cand = format!("{cur}{seg}");
            let fits = self.measure(cand.trim_end(), key, size, letter_spacing) <= max;
            if fits || cur.is_empty() && !anywhere {
                cur = cand;
            } else {
                if !cur.is_empty() {
                    out.push(cur.trim_end_matches(['\n', '\r']).to_string());
                    cur.clear();
                }
                if self.measure(seg.trim_end(), key, size, letter_spacing) <= max || !anywhere {
                    cur = seg.to_string();
                } else {
                    // Wider than a whole line: break it wherever it must.
                    for ch in seg.chars() {
                        let c = format!("{cur}{ch}");
                        if !cur.is_empty() && self.measure(c.trim_end(), key, size, letter_spacing) > max {
                            out.push(std::mem::take(&mut cur));
                            cur.push(ch);
                        } else {
                            cur = c;
                        }
                    }
                }
            }
            if opp == BreakOpportunity::Mandatory && pos < text.len() {
                out.push(cur.trim_end_matches(['\n', '\r']).to_string());
                cur.clear();
            }
        }
        let last = cur.trim_end_matches(['\n', '\r']).to_string();
        if !last.is_empty() || out.is_empty() {
            out.push(last);
        }
        out
    }

    /// Text.ElideRight: cut and end with "…" so the line fits `max`.
    pub fn elide_right(&mut self, line: &Line, text: &str, key: FontKey, max: f32, letter_spacing: f32) -> Line {
        if line.width <= max {
            return line.clone();
        }
        let dots = self.layout("…", key, line.size, letter_spacing);
        let mut out = line.clone();
        let chars: Vec<char> = text.chars().collect();
        let mut n = out.glyphs.len().min(chars.len());
        while n > 0 {
            let end = if n < out.glyphs.len() { out.glyphs[n].x } else { line.width };
            if end + dots.width <= max {
                break;
            }
            n -= 1;
        }
        out.glyphs.truncate(n);
        let start = if n < line.glyphs.len() { line.glyphs[n].x } else { line.width };
        for g in &dots.glyphs {
            out.glyphs.push(PlacedGlyph { x: start + g.x, ..*g });
        }
        out.width = start + dots.width;
        out.adv = start + dots.adv;
        out
    }

    /// Qt's ElideMiddle (QTextEngine::elidedText): as many characters from
    /// each end as fit beside the ellipsis.
    pub fn elide_middle(&mut self, text: &str, key: FontKey, size: f32, letter_spacing: f32, max: f32) -> Line {
        let full = self.layout(text, key, size, letter_spacing);
        if full.width <= max {
            return full;
        }
        let avail = max - self.layout("…", key, size, letter_spacing).width;
        let chars: Vec<char> = text.chars().collect();
        let mut keep = 0;
        for k in 1..=chars.len() / 2 {
            let left: String = chars[..k].iter().collect();
            let right: String = chars[chars.len() - k..].iter().collect();
            if self.layout(&left, key, size, letter_spacing).adv + self.layout(&right, key, size, letter_spacing).adv >= avail {
                break;
            }
            keep = k;
        }
        let s: String = chars[..keep].iter().chain(std::iter::once(&'…')).chain(chars[chars.len() - keep..].iter()).collect();
        self.layout(&s, key, size, letter_spacing)
    }

    /// QFontMetricsF::boundingRect(text).width for one glyph: the hinted ink box.
    pub fn ink_width(&mut self, text: &str, key: FontKey, size: f32) -> f32 {
        let line = self.layout(text, key, size, 0.0);
        let Some(g) = line.glyphs.first().copied() else { return 0.0 };
        let Some(fc) = self.ft_face(g.face) else { return 0.0 };
        unsafe {
            let s = (size * 64.0).round() as ft::FT_F26Dot6;
            ft::FT_Set_Char_Size(fc, s, s, 72, 72);
            if ft::FT_Load_Glyph(fc, g.gid as u32, ft::FT_LOAD_DEFAULT | ft::FT_LOAD_TARGET_LIGHT) != 0 {
                return 0.0;
            }
            (*(*fc).glyph).metrics.width as f32 / 64.0
        }
    }

    pub fn measure(&mut self, text: &str, key: FontKey, size: f32, letter_spacing: f32) -> f32 {
        self.layout(text, key, size, letter_spacing).width
    }

    /// QFontEngineFT::getGlyphBearings: hinted advance - right edge of the
    /// hinted glyph box (light hinting, as the bar's fontconfig asks), 26.6.
    fn right_bearing26(&mut self, face: u16, gid: GlyphId, size: f32) -> i64 {
        let Some(fc) = self.ft_face(face) else { return 0 };
        unsafe {
            let s = (size * 64.0).round() as ft::FT_F26Dot6;
            ft::FT_Set_Char_Size(fc, s, s, 72, 72);
            if ft::FT_Load_Glyph(fc, gid as u32, ft::FT_LOAD_DEFAULT | ft::FT_LOAD_TARGET_LIGHT) != 0 {
                return 0;
            }
            let m = &(*(*fc).glyph).metrics;
            (m.horiAdvance - m.horiBearingX - m.width) as i64
        }
    }

    /// QFontEngine::subPixelPositionFor: the fraction of x in quarters; note the
    /// +1/64, which makes a pen at n + 63/64 render as n + 1.
    pub fn subpixel_quarter(x: f32) -> u8 {
        let v = (x * 64.0).round() as i64;
        if v == 0 {
            return 0;
        }
        let frac = v - (v.div_euclid(64) * 64) + 1; // in 1/64
        ((frac * 4) / 64) as u8
    }

    /// A glyph rasterised by FreeType the way QFontEngineFT does it for an
    /// 8-bit (gray) glyph cache: light hinting target, outline translated by
    /// the subpixel position, rendered in normal mode.
    pub fn native_glyph(&mut self, face: u16, gid: GlyphId, size: f32, quarter: u8) -> Option<NativeGlyph> {
        let size26 = (size * 64.0).round() as i64;
        let key = (face, gid, size26, quarter);
        if let Some(g) = self.native.get(&key) {
            return *g;
        }
        let g = unsafe { self.rasterise(face, gid, size26, quarter) };
        self.native.insert(key, g);
        g
    }

    unsafe fn rasterise(&mut self, face: u16, gid: GlyphId, size26: i64, quarter: u8) -> Option<NativeGlyph> {
        let f = &mut self.faces[face as usize];
        if f.ft_face.is_none() {
            let mut fc: ft::FT_Face = std::ptr::null_mut();
            if ft::FT_New_Memory_Face(self.library, f.data.as_ptr(), f.data.len() as ft::FT_Long, f.index as ft::FT_Long, &mut fc) != 0 {
                return None;
            }
            f.ft_face = Some(fc);
        }
        let fc = f.ft_face.unwrap();
        ft::FT_Set_Char_Size(fc, size26 as ft::FT_F26Dot6, size26 as ft::FT_F26Dot6, 72, 72);
        let flags = native_load_flags();
        if ft::FT_Load_Glyph(fc, gid as u32, flags) != 0 {
            return None;
        }
        let slot = (*fc).glyph;
        if (*slot).format == ft::FT_GLYPH_FORMAT_OUTLINE && quarter != 0 {
            ft::FT_Outline_Translate(&(*slot).outline, quarter as ft::FT_Pos * 16, 0);
        }
        if (*slot).format != ft::FT_GLYPH_FORMAT_BITMAP && ft::FT_Render_Glyph(slot, ft::FT_RENDER_MODE_NORMAL) != 0 {
            return None;
        }
        let bm = &(*slot).bitmap;
        let (w, h) = (bm.width as u32, bm.rows as u32);
        let (left, top) = ((*slot).bitmap_left, (*slot).bitmap_top);
        if w == 0 || h == 0 {
            return Some(NativeGlyph { ax: 0, ay: 0, w: 0, h: 0, left, top });
        }
        let (ax, ay) = self.atlas.alloc(w + 4, h + 4);
        let aw = self.atlas.width;
        for j in 0..h + 4 {
            let row = ((ay + j) * aw + ax) as usize;
            self.atlas.pixels[row..row + (w + 4) as usize].fill(0);
        }
        let mono = bm.pixel_mode as u32 == ft::FT_PIXEL_MODE_MONO as u32;
        for j in 0..h {
            let src = bm.buffer.offset((j as isize) * bm.pitch as isize);
            let dst = ((ay + 2 + j) * aw + ax + 2) as usize;
            for i in 0..w {
                let v = if mono {
                    let byte = *src.add((i / 8) as usize);
                    if byte & (0x80 >> (i % 8)) != 0 { 255 } else { 0 }
                } else {
                    *src.add(i as usize)
                };
                self.atlas.pixels[dst + i as usize] = v;
            }
        }
        self.atlas.dirty.push((ax, ay, w + 4, h + 4));
        Some(NativeGlyph { ax: ax + 2, ay: ay + 2, w, h, left, top })
    }

    /// The distance field of a glyph, made on first use.
    pub fn df_glyph(&mut self, face: u16, gid: GlyphId, bold: bool) -> Option<DfGlyph> {
        if let Some(g) = self.glyphs.get(&(face, gid, bold)) {
            return *g;
        }
        let g = self.make_df(face, gid, bold);
        self.glyphs.insert((face, gid, bold), g);
        g
    }

    fn ft_face(&mut self, face: u16) -> Option<ft::FT_Face> {
        let f = &mut self.faces[face as usize];
        if f.ft_face.is_none() {
            let mut fc: ft::FT_Face = std::ptr::null_mut();
            let err = unsafe { ft::FT_New_Memory_Face(self.library, f.data.as_ptr(), f.data.len() as ft::FT_Long, f.index as ft::FT_Long, &mut fc) };
            if err != 0 {
                return None;
            }
            f.ft_face = Some(fc);
        }
        f.ft_face
    }

    /// The glyph's outline at the field's base size, as Qt gets it for a
    /// distance field: FreeType, unhinted, in 26.6, emboldened by
    /// FT_GlyphSlot_Embolden's strength for synthetic bold. Line segments in
    /// base px, y down.
    fn outline_segments(&mut self, face: u16, gid: GlyphId, bold: bool) -> Option<Vec<[f32; 4]>> {
        let fc = self.ft_face(face)?;
        unsafe {
            let size = (DF_BASE * 64.0) as ft::FT_F26Dot6;
            ft::FT_Set_Char_Size(fc, size, size, 72, 72);
            if ft::FT_Load_Glyph(fc, gid as u32, ft::FT_LOAD_NO_BITMAP | ft::FT_LOAD_NO_HINTING) != 0 {
                return None;
            }
            let slot = (*fc).glyph;
            if (*slot).format != ft::FT_GLYPH_FORMAT_OUTLINE {
                return None;
            }
            if bold {
                let strength = ft::FT_MulFix((*fc).units_per_EM as ft::FT_Long, (*(*fc).size).metrics.y_scale) / 24;
                ft::FT_Outline_EmboldenXY(&mut (*slot).outline, strength, strength);
            }
            let mut walk = Walk { segs: Vec::new(), cur: (0.0, 0.0), start: (0.0, 0.0) };
            let funcs = ft::FT_Outline_Funcs { move_to, line_to, conic_to, cubic_to, shift: 0, delta: 0 };
            ft::FT_Outline_Decompose(&mut (*slot).outline, &funcs, &mut walk as *mut Walk as *mut std::ffi::c_void);
            walk.close();
            Some(walk.segs)
        }
    }

    fn make_df(&mut self, face: u16, gid: GlyphId, bold: bool) -> Option<DfGlyph> {
        let segs = self.outline_segments(face, gid, bold)?;
        if segs.is_empty() {
            return None;
        }
        let (mut xmin, mut ymin, mut xmax, mut ymax) = (f32::MAX, f32::MAX, f32::MIN, f32::MIN);
        for s in &segs {
            xmin = xmin.min(s[0]).min(s[2]);
            xmax = xmax.max(s[0]).max(s[2]);
            ymin = ymin.min(s[1]).min(s[3]);
            ymax = ymax.max(s[1]).max(s[3]);
        }
        let x0 = xmin.floor() as i32 - DF_PAD;
        let y0 = ymin.floor() as i32 - DF_PAD;
        let w = (xmax.ceil() as i32 + DF_PAD - x0) as u32;
        let h = (ymax.ceil() as i32 + DF_PAD - y0) as u32;
        let mut bits = vec![0u8; (w * h) as usize];
        for j in 0..h {
            let py = y0 as f32 + j as f32 + 0.5;
            for i in 0..w {
                let px = x0 as f32 + i as f32 + 0.5;
                let mut d2 = DF_RADIUS * DF_RADIUS;
                let mut winding = 0i32;
                for s in &segs {
                    let (ax, ay, bx, by) = (s[0], s[1], s[2], s[3]);
                    if (ay <= py) != (by <= py) {
                        let xi = ax + (py - ay) * (bx - ax) / (by - ay);
                        if xi > px {
                            winding += if by > ay { 1 } else { -1 };
                        }
                    }
                    let (dx, dy) = (bx - ax, by - ay);
                    let l2 = dx * dx + dy * dy;
                    let t = if l2 > 0.0 { (((px - ax) * dx + (py - ay) * dy) / l2).clamp(0.0, 1.0) } else { 0.0 };
                    let (ex, ey) = (ax + t * dx - px, ay + t * dy - py);
                    d2 = d2.min(ex * ex + ey * ey);
                }
                let d = d2.sqrt();
                let sd = if winding != 0 { d } else { -d };
                let v = (0.5 + sd / (2.0 * DF_RADIUS)).clamp(0.0, 1.0);
                bits[(j * w + i) as usize] = (v * 255.0).round() as u8;
            }
        }
        let (ax, ay) = self.atlas.alloc(w, h);
        let aw = self.atlas.width;
        for j in 0..h {
            let dst = ((ay + j) * aw + ax) as usize;
            self.atlas.pixels[dst..dst + w as usize].copy_from_slice(&bits[(j * w) as usize..((j + 1) * w) as usize]);
        }
        self.atlas.dirty.push((ax, ay, w, h));
        Some(DfGlyph { ax, ay, w, h, x0: x0 as f32, y0: y0 as f32 })
    }
}
