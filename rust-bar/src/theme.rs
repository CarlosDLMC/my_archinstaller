//! Theme.qml: the wallust palette and every role derived from it. The bar is
//! monochrome on purpose - see the comments in Theme.qml for why each role is
//! what it is; the arithmetic here is the same, through QColor's rounding.

use crate::color::Color;
pub use crate::text::FontKey;

pub const FONT: &str = "Terminess Nerd Font";
pub const FONT_CONTENT: &str = "JetBrainsMono Nerd Font";
pub const FONT_SIZE: f32 = 24.0;

pub fn bar_font(bold: bool) -> FontKey {
    FontKey { family: FONT, bold }
}

pub fn content_font(bold: bool) -> FontKey {
    FontKey { family: FONT_CONTENT, bold }
}

#[derive(Clone, Debug)]
pub struct Theme {
    pub pal_bg: Color,
    pub pal_fg: Color,
    pub pal_bright: Color,
    pub pal_dim: Color,
    pub pal_muted: Color,
    pub pal_faint: Color,
    pub pal_accent: Color,
    pub pal_alert: Color,
    pub pal_warn: Color,
    pub pal_border: Color,

    pub col_white: Color,
    pub col_grey: Color,
    pub col_bg: Color,
    pub col_plate: Color,
    pub col_accent: Color,
    pub col_bg_wash: Color,
    pub col_value: Color,
    pub col_dim: Color,
    pub col_muted: Color,
    pub col_faint: Color,
    pub col_separator: Color,
    pub col_alert: Color,
    pub col_warn: Color,
    pub col_on_alert: Color,
    pub col_text_shadow: Color,
    pub col_window: Color,
    pub col_logo: Color,
}

fn hex(s: &str) -> Color {
    Color::parse(s).unwrap()
}

fn at_least(c: Color, min_l: f32) -> Color {
    let (h, s, l) = c.hsl();
    if l >= min_l {
        c
    } else {
        Color::hsla(h, s, min_l, c.a)
    }
}

fn desat(c: Color, keep: f32, l: f32) -> Color {
    let (h, s, _) = c.hsl();
    Color::hsla(h, s * keep, l, c.a)
}

fn contrast(a: Color, b: Color) -> f32 {
    let (la, lb) = (a.relative_luminance(), b.relative_luminance());
    (la.max(lb) + 0.05) / (la.min(lb) + 0.05)
}

fn lift_to_contrast(c: Color, against: Color, target: f32) -> Color {
    if contrast(c, against) >= target {
        return c;
    }
    let (h, s, l0) = c.hsl();
    let mut l = l0;
    while l <= 0.95 {
        let lifted = Color::hsla(h, s, l, c.a);
        if contrast(lifted, against) >= target {
            return lifted;
        }
        l += 0.02;
    }
    Color::hsla(h, s, 0.95, c.a)
}

/// alertFrom(): the most colourful of wallust's hue slots, softened.
fn alert_from(hues: &[Color]) -> Color {
    let mut best: Option<Color> = None;
    let mut best_chroma = -1.0f32;
    for c in hues {
        let chroma = c.r.max(c.g).max(c.b) - c.r.min(c.g).min(c.b);
        if chroma > best_chroma {
            best = Some(*c);
            best_chroma = chroma;
        }
    }
    match best {
        Some(b) if best_chroma >= 0.06 => {
            let (h, s, _) = b.hsl();
            Color::hsla(h, s.clamp(0.35, 0.55), 0.66, 1.0)
        }
        _ => Color::hsla(6.0 / 360.0, 0.45, 0.66, 1.0),
    }
}

impl Theme {
    pub fn fallback() -> Theme {
        let mut t = Theme {
            pal_bg: hex("#262625"),
            pal_fg: hex("#E8C4C0"),
            pal_bright: hex("#D6A29C"),
            pal_dim: hex("#96716D"),
            pal_muted: hex("#524B47"),
            pal_faint: hex("#4C4C4B"),
            pal_accent: hex("#D6A29C"),
            pal_alert: hex("#D1887F"),
            pal_warn: hex("#8E4137"),
            pal_border: hex("#59302D"),
            col_white: Color::TRANSPARENT,
            col_grey: Color::TRANSPARENT,
            col_bg: Color::TRANSPARENT,
            col_plate: Color::TRANSPARENT,
            col_accent: Color::TRANSPARENT,
            col_bg_wash: Color::TRANSPARENT,
            col_value: Color::TRANSPARENT,
            col_dim: Color::TRANSPARENT,
            col_muted: Color::TRANSPARENT,
            col_faint: Color::TRANSPARENT,
            col_separator: Color::TRANSPARENT,
            col_alert: Color::TRANSPARENT,
            col_warn: Color::TRANSPARENT,
            col_on_alert: Color::TRANSPARENT,
            col_text_shadow: Color::TRANSPARENT,
            col_window: Color::TRANSPARENT,
            col_logo: Color::TRANSPARENT,
        };
        t.derive();
        t
    }

    fn derive(&mut self) {
        self.col_white = desat(self.pal_fg, 0.12, 0.95);
        self.col_grey = desat(self.pal_fg, 0.08, 0.62);
        self.col_bg = self.pal_bg;
        self.col_plate = self.pal_bg.darker(1.55);
        self.col_accent = at_least(self.pal_accent, 0.62);
        self.col_bg_wash = Color::qt_rgba(0.0, 0.0, 0.0, 0.55);
        self.col_value = self.col_white;
        self.col_dim = at_least(self.pal_dim, 0.59);
        self.col_muted = at_least(self.pal_muted, 0.57);
        self.col_faint = at_least(self.pal_faint, 0.56);
        self.col_separator = self.col_grey;
        self.col_alert = self.pal_alert;
        self.col_warn = self.pal_warn;
        self.col_on_alert = self.pal_bg;
        self.col_text_shadow = Color::qt_rgba(0.0, 0.0, 0.0, 0.55);
        self.col_window = desat(self.pal_fg, 0.60, 0.84);
        self.col_logo = lift_to_contrast(self.pal_border, self.pal_bg, 3.0);
    }

    /// applyPalette(): wallust-colors.json; anything missing keeps its fallback.
    pub fn apply_json(&mut self, text: &str) -> bool {
        let Ok(j) = serde_json::from_str::<serde_json::Value>(text) else { return false };
        let get = |k: &str| j.get(k).and_then(|v| v.as_str()).and_then(Color::parse);
        if let Some(c) = get("bg") { self.pal_bg = c; }
        if let Some(c) = get("fg") { self.pal_fg = c; }
        if let Some(c) = get("bright") { self.pal_bright = c; }
        if let Some(c) = get("dim") { self.pal_dim = c; }
        if let Some(c) = get("muted") { self.pal_muted = c; }
        if let Some(c) = get("faint") { self.pal_faint = c; }
        if let Some(c) = get("accent") { self.pal_accent = c; }
        if let Some(h) = j.get("hues").and_then(|v| v.as_array()) {
            let hues: Vec<Color> = h.iter().filter_map(|v| v.as_str().and_then(Color::parse)).collect();
            self.pal_alert = alert_from(&hues);
        }
        if let Some(c) = get("warn") { self.pal_warn = c; }
        if let Some(c) = get("border") { self.pal_border = c; }
        self.derive();
        true
    }
}
