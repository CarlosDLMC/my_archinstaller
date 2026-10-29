//! Colours with QColor's arithmetic. Theme.qml derives every role from the
//! wallust palette through hslHue/hslSaturation/hslLightness, Qt.hsla and
//! Qt.darker, so the bar only matches if those conversions round the way
//! QColor does: 16-bit channels, HSV through 8-bit ints for darker().

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Color {
    pub r: f32,
    pub g: f32,
    pub b: f32,
    pub a: f32,
}

const MAX: f32 = 65535.0;

fn q16(v: f32) -> f32 {
    (v * MAX).round() / MAX
}

fn fuzzy_null(v: f32) -> bool {
    v.abs() <= 0.00001
}

fn fuzzy_eq(a: f32, b: f32) -> bool {
    (a - b).abs() * 100000.0 <= a.abs().min(b.abs())
}

impl Color {
    pub const TRANSPARENT: Color = Color { r: 0.0, g: 0.0, b: 0.0, a: 0.0 };

    pub const fn rgba(r: f32, g: f32, b: f32, a: f32) -> Color {
        Color { r, g, b, a }
    }

    /// Qt.rgba(): channels in 0..1. Qt.rgba(255, 255, 255, 0.05) clamps to white.
    pub fn qt_rgba(r: f32, g: f32, b: f32, a: f32) -> Color {
        Color { r: q16(r.clamp(0.0, 1.0)), g: q16(g.clamp(0.0, 1.0)), b: q16(b.clamp(0.0, 1.0)), a: q16(a.clamp(0.0, 1.0)) }
    }

    /// "#RGB", "#RRGGBB" or "#AARRGGBB" (Qt's order), or a few names.
    pub fn parse(s: &str) -> Option<Color> {
        let s = s.trim();
        if s.eq_ignore_ascii_case("transparent") {
            return Some(Color::TRANSPARENT);
        }
        let h = s.strip_prefix('#')?;
        // Hex digits only, as QColor::fromString wants: the slices below
        // count bytes, and a sign is no digit to it either.
        if !h.bytes().all(|b| b.is_ascii_hexdigit()) {
            return None;
        }
        let v = |i: usize, n: usize| u32::from_str_radix(&h[i..i + n], 16).ok();
        let c8 = |x: u32| x as f32 / 255.0;
        match h.len() {
            3 => {
                let (r, g, b) = (v(0, 1)?, v(1, 1)?, v(2, 1)?);
                Some(Color::rgba(c8(r * 17), c8(g * 17), c8(b * 17), 1.0))
            }
            6 => Some(Color::rgba(c8(v(0, 2)?), c8(v(2, 2)?), c8(v(4, 2)?), 1.0)),
            8 => Some(Color::rgba(c8(v(2, 2)?), c8(v(4, 2)?), c8(v(6, 2)?), c8(v(0, 2)?))),
            _ => None,
        }
    }

    /// (hue 0..1 or -1 when achromatic, saturation, lightness) like QColor's hsl*F.
    pub fn hsl(&self) -> (f32, f32, f32) {
        let (r, g, b) = (self.r, self.g, self.b);
        let max = r.max(g).max(b);
        let min = r.min(g).min(b);
        let delta = max - min;
        let delta2 = max + min;
        let l = q16(0.5 * delta2);
        if fuzzy_null(delta) {
            return (-1.0, 0.0, l);
        }
        let s = if 0.5 * delta2 < 0.5 { delta / delta2 } else { delta / (2.0 - delta2) };
        let mut h = if fuzzy_eq(r, max) {
            (g - b) / delta
        } else if fuzzy_eq(g, max) {
            2.0 + (b - r) / delta
        } else {
            4.0 + (r - g) / delta
        };
        h *= 60.0;
        if h < 0.0 {
            h += 360.0;
        }
        let h = (h * 100.0).round();
        (if h == 36000.0 { 0.0 } else { h / 36000.0 }, q16(s), l)
    }

    pub fn lightness(&self) -> f32 {
        self.hsl().2
    }

    /// Qt.hsla(h, s, l, a). A hue of -1 (achromatic) gives a grey.
    pub fn hsla(h: f32, s: f32, l: f32, a: f32) -> Color {
        let s = q16(s.clamp(0.0, 1.0));
        let l = q16(l.clamp(0.0, 1.0));
        let a = q16(a.clamp(0.0, 1.0));
        if h < 0.0 || s == 0.0 {
            return Color::rgba(l, l, l, a);
        }
        let hq = (h * 36000.0).round();
        let h = if hq >= 36000.0 { 0.0 } else { hq / 36000.0 };
        let temp2 = if l < 0.5 { l * (1.0 + s) } else { l + s - l * s };
        let temp1 = 2.0 * l - temp2;
        let mut out = [0f32; 3];
        for (i, t) in [h + 1.0 / 3.0, h, h - 1.0 / 3.0].into_iter().enumerate() {
            let t = if t < 0.0 { t + 1.0 } else if t > 1.0 { t - 1.0 } else { t };
            let v = if t * 6.0 < 1.0 {
                temp1 + (temp2 - temp1) * t * 6.0
            } else if t * 2.0 < 1.0 {
                temp2
            } else if t * 3.0 < 2.0 {
                temp1 + (temp2 - temp1) * (2.0 / 3.0 - t) * 6.0
            } else {
                temp1
            };
            out[i] = q16(v);
        }
        Color::rgba(out[0], out[1], out[2], a)
    }

    /// QColor::toHsv as floats (hue 0..1 or -1, saturation, value), through
    /// QColor's 16-bit storage.
    fn hsv(&self) -> (f32, f32, f32) {
        let (r, g, b) = (self.r, self.g, self.b);
        let max = r.max(g).max(b);
        let min = r.min(g).min(b);
        let delta = max - min;
        let v = q16(max);
        if fuzzy_null(delta) {
            return (-1.0, 0.0, v);
        }
        let s = q16(delta / max);
        let mut h = if fuzzy_eq(r, max) {
            (g - b) / delta
        } else if fuzzy_eq(g, max) {
            2.0 + (b - r) / delta
        } else {
            4.0 + (r - g) / delta
        };
        h *= 60.0;
        if h < 0.0 {
            h += 360.0;
        }
        let h = (h * 100.0).round();
        (if h == 36000.0 { 0.0 } else { h / 36000.0 }, s, v)
    }

    /// QColor::fromHsvF, back to 16-bit RGB.
    fn from_hsv(h: f32, s: f32, v: f32, a: f32) -> Color {
        let s = q16(s.clamp(0.0, 1.0));
        let v = q16(v.clamp(0.0, 1.0));
        if h < 0.0 || s == 0.0 {
            return Color::rgba(v, v, v, a);
        }
        let hq = (h * 36000.0).round();
        let hh = if hq >= 36000.0 { 0.0 } else { hq / 6000.0 };
        let i = hh as i32;
        let f = hh - i as f32;
        let p = v * (1.0 - s);
        let (r, g, b) = if i & 1 == 1 {
            let q = v * (1.0 - s * f);
            match i {
                1 => (q, v, p),
                3 => (p, q, v),
                _ => (v, p, q),
            }
        } else {
            let t = v * (1.0 - s * (1.0 - f));
            match i {
                0 => (v, t, p),
                2 => (p, v, t),
                _ => (t, p, v),
            }
        };
        Color::rgba(q16(r), q16(g), q16(b), a)
    }

    /// Qt.darker(c, factor): QColor::darker(qRound(factor * 100)) - Qt 6 works
    /// in float HSV (an int HSV path, as in Qt 5, comes out a level darker).
    pub fn darker(&self, factor: f32) -> Color {
        let f = (factor * 100.0).round() as i32;
        if f <= 0 {
            return *self;
        }
        if f < 100 {
            return self.lighter((10000 / f) as f32 / 100.0);
        }
        let (h, s, v) = self.hsv();
        Color::from_hsv(h, s, v * 100.0 / f as f32, self.a)
    }

    /// Qt.lighter(c, factor).
    pub fn lighter(&self, factor: f32) -> Color {
        let f = (factor * 100.0).round() as i32;
        if f <= 0 {
            return *self;
        }
        if f < 100 {
            return self.darker((10000 / f) as f32 / 100.0);
        }
        let (h, mut s, v) = self.hsv();
        let mut v = f as f32 * v / 100.0;
        if v > 1.0 {
            s = (s - (v - 1.0)).max(0.0);
            v = 1.0;
        }
        Color::from_hsv(h, s, v, self.a)
    }

    pub fn with_alpha(self, a: f32) -> Color {
        Color { a, ..self }
    }

    /// Qt's ColorAnimation interpolates the four channels linearly.
    pub fn mix(a: Color, b: Color, t: f32) -> Color {
        Color {
            r: a.r + (b.r - a.r) * t,
            g: a.g + (b.g - a.g) * t,
            b: a.b + (b.b - a.b) * t,
            a: a.a + (b.a - a.a) * t,
        }
    }

    /// Premultiplied, multiplied by an item opacity - what the scene graph uploads.
    pub fn premul(&self, opacity: f32) -> [f32; 4] {
        let a = self.a * opacity;
        [self.r * a, self.g * a, self.b * a, a]
    }

    pub fn relative_luminance(&self) -> f32 {
        let ch = |v: f32| if v <= 0.04045 { v / 12.92 } else { ((v + 0.055) / 1.055).powf(2.4) };
        0.2126 * ch(self.r) + 0.7152 * ch(self.g) + 0.0722 * ch(self.b)
    }
}
