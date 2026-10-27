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
        Face { font, data: font.data, index: 0, ft_face: None, upem, hhea, typo, win, strikes, has_bitmaps, fixed_pitch }
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
}

#[derive(Clone, Debug, Default)]
pub struct Line {
    pub glyphs: Vec<PlacedGlyph>,
    pub width: f32,
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
}

pub struct Atlas {
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
    fn new() -> Atlas {
        Atlas { width: 1024, height: 256, pixels: vec![0; 1024 * 256], shelf_x: 0, shelf_y: 0, shelf_h: 0, dirty: vec![], resized: true }
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
            self.pixels.resize((self.width * self.height) as usize, 0);
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
}

/// QFontEngineFT::loadFlags for a gray glyph cache with fontconfig's
/// hintslight. RUST_BAR_FT_FLAGS overrides it (calibration only).
fn native_load_flags() -> i32 {
    if let Some(v) = std::env::var("RUST_BAR_FT_FLAGS").ok().and_then(|v| i32::from_str_radix(v.trim_start_matches("0x"), 16).ok()) {
        return v;
    }
    (ft::FT_LOAD_DEFAULT | ft::FT_LOAD_TARGET_LIGHT) as i32
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
            atlas: Atlas::new(),
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
        let mut x26 = 0i64;
        for ch in text.chars() {
            if ch == '\n' {
                break;
            }
            let fi = self.face_with(key, ch);
            let face = &self.faces[fi as usize];
            let gid = face.font.charmap().map(ch);
            let units = face.font.glyph_metrics(&[]).advance_width(gid) as i64;
            let bold = key.bold && !face.fixed_pitch;
            line.glyphs.push(PlacedGlyph { face: fi, gid, x: x26 as f32 / 64.0, bold });
            x26 += face.advance26(units, size) + spacing26;
        }
        // QTextLine adds the last glyph's negative right bearing, so a Text's
        // width covers a glyph that overhangs its advance (the Nerd icons do).
        if let Some(last) = line.glyphs.last().copied() {
            let rb = self.right_bearing26(last.face, last.gid, size);
            if rb < 0 {
                x26 -= rb;
            }
        }
        line.width = x26 as f32 / 64.0;
        line
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
        out
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
