//! What `grim -s 0.25 -t ppm` and overview-shots.sh's `magick -trim` made of
//! a window's capture, done here: the quarter-size picture (grim's render.c
//! through pixman), the black border cut off, the PPM for the next open.

/// The 16 weights of grim's quarter-size filter. render.c convolves when it
/// shrinks below 0.75: pixman_filter_create_separable_convolution(4, 4,
/// IMPULSE, IMPULSE, LANCZOS2, LANCZOS2, 2, 2), 16 taps in 4 phases. At
/// exactly 1/4 every picture pixel x samples the capture at 4x + 2, which
/// pixman rounds to the middle of phase 0 (1/8) and takes from 4x - 6 on
/// (pixman-fast-path.c, bits_image_fetch_separable_convolution_affine):
/// phase 0's weights, made as pixman-filter.c create_1d_filter makes them.
fn taps() -> [i64; 16] {
    use std::f64::consts::PI;
    let sinc = |x: f64| if x == 0.0 { 1.0 } else { (PI * x).sin() / (PI * x) };
    let lanczos2 = |x: f64| sinc(x) * sinc(x * 0.5);
    let (scale, frac) = (4.0f64, 0.125f64);
    let first = (frac - 16.0 / 2.0 - 0.5).ceil();
    let mut p = [0i64; 16];
    let mut total = 0.0;
    for (i, v) in p.iter_mut().enumerate() {
        let pos = first + i as f64 + 0.5 - frac;
        // The impulse meets the sampling kernel (4 wide, times the scale)
        // at 0 only, when 0 is inside it.
        let c = if pos - scale * 2.0 <= 0.0 && 0.0 <= pos + scale * 2.0 { lanczos2(-pos * (1.0 / scale)) } else { 0.0 };
        *v = (c * 65536.0 + 0.5).floor() as i64;
        total += *v as f64;
    }
    // Normalised with error diffusion; what is left over goes to the first.
    let total = 65536.0 / total;
    let (mut sum, mut e) = (0, 0.0);
    for v in p.iter_mut() {
        let x = *v as f64 * total + e;
        let t = (x + 0.5).floor();
        e = x - t;
        *v = t as i64;
        sum += *v;
    }
    p[0] += 65536 - sum;
    p
}

/// A capture in the compositor's buffer: 4 bytes a pixel, `rgb` the bytes
/// of red, green and blue in one (the 4th is alpha or unused).
pub struct Capture<'a> {
    pub data: &'a [u8],
    pub width: usize,
    pub height: usize,
    pub stride: usize,
    pub rgb: [usize; 3],
}

/// grim's quarter-size picture of a capture, as RGB: width and height / 4
/// rounded down (render.c's int common_width), a capture pixel outside the
/// buffer counts as transparent black (pixman's REPEAT_NONE), and only red,
/// green and blue are kept (write_ppm.c drops alpha, the colours stay
/// premultiplied). pixman sums the 16 x 16 taps with each tap's weight
/// fx * fy rounded to 16 bits; here the two passes are summed apart and the
/// product rounded once, which lands on the same level, or one off where a
/// sum sits on a rounding edge: against pixman 0.46, 0.8 % of the values of
/// a photo, 1.2 % of noise, 0.03 to 0.15 % of a terminal window. The exact
/// sum costs three times as much.
pub fn quarter(c: &Capture) -> Option<(usize, usize, Vec<u8>)> {
    let (w, h, stride) = (c.width, c.height, c.stride);
    let (dw, dh) = (w / 4, h / 4);
    if dw == 0 || dh == 0 || stride < w * 4 || c.data.len() < stride * (h - 1) + w * 4 || c.rgb.iter().any(|&b| b > 3) {
        return None;
    }
    let k = taps();
    let kf = k.map(|v| v as f64);
    // Without SSE4.1 (a generic x86-64 build) a 32-bit multiply is slow: the
    // horizontal pass multiplies by the weights plus LIFT instead, all of
    // them positive and below 2^15, which the compiler does in 16 bits, and
    // takes LIFT times the pixels' sum off again.
    const LIFT: i32 = if cfg!(all(target_arch = "x86_64", not(target_feature = "sse4.1"))) { 2048 } else { 0 };
    let kl = k.map(|v| v as i32 + LIFT);
    // One capture row at a time into a ring of the 16 rows one picture row
    // takes: picture row y reads rows 4y - 6 to 4y + 9, picture pixel x
    // columns 4x - 6 to 4x + 9. A row is copied with 6 black pixels before it
    // and black after it, so every picture pixel takes its 16 in one go.
    let pw = 4 * dw + 16;
    let mut padded = vec![0u8; pw * 4];
    let mut ring = vec![[0i32; 4]; 16 * dw];
    let mut hpass = |row: &[u8], out: &mut [[i32; 4]]| {
        // Pixels past 4 * dw + 9 reach no picture pixel.
        let n = row.len().min((pw - 6) * 4);
        padded[24..24 + n].copy_from_slice(&row[..n]);
        for (x, o) in out.iter_mut().enumerate() {
            let (mut acc, mut sum) = ([0i32; 4], [0i32; 4]);
            for (p, &kt) in padded[16 * x..16 * x + 64].chunks_exact(4).zip(&kl) {
                let kt = if LIFT > 0 { kt & 0x7fff } else { kt };
                for b in 0..4 {
                    acc[b] += kt * p[b] as i32;
                    sum[b] += p[b] as i32;
                }
            }
            for b in 0..4 {
                o[b] = acc[b] - LIFT * sum[b];
            }
        }
    };
    let mut out = vec![0u8; dw * dh * 3];
    let mut acc = vec![[0f64; 4]; dw];
    let mut next = 0usize;
    for (y, line) in out.chunks_exact_mut(dw * 3).enumerate() {
        let first = 4 * y as isize - 6;
        while next < h && next as isize <= first + 15 {
            hpass(&c.data[next * stride..next * stride + w * 4], &mut ring[(next % 16) * dw..][..dw]);
            next += 1;
        }
        // The vertical pass in f64: the sums stay below 2^53, so it is
        // integer arithmetic still.
        acc.iter_mut().for_each(|a| *a = [0.0; 4]);
        for (t, &kt) in kf.iter().enumerate() {
            let sy = first + t as isize;
            if sy < 0 || sy as usize >= h {
                continue;
            }
            for (a, r) in acc.iter_mut().zip(&ring[(sy as usize % 16) * dw..][..dw]) {
                for b in 0..4 {
                    a[b] += kt * r[b] as f64;
                }
            }
        }
        for (o, a) in line.chunks_exact_mut(3).zip(&acc) {
            for (o, &b) in o.iter_mut().zip(&c.rgb) {
                *o = ((a[b] as i64 + (1 << 31)) >> 32).clamp(0, 255) as u8;
            }
        }
    }
    Some((dw, dh, out))
}

/// `magick -bordercolor black -border 1 -trim +repage`: the rows and
/// columns at the edges that are all black (#000000 exactly) go. A picture
/// that is black all over comes out as magick leaves it: one white pixel.
pub fn trim_black(w: usize, h: usize, rgb: Vec<u8>) -> (usize, usize, Vec<u8>) {
    let lit = |x: usize, y: usize| rgb[(y * w + x) * 3..][..3] != [0, 0, 0];
    let Some(top) = (0..h).find(|&y| (0..w).any(|x| lit(x, y))) else {
        return (1, 1, vec![255; 3]);
    };
    let bottom = (top..h).rev().find(|&y| (0..w).any(|x| lit(x, y))).unwrap_or(top);
    let left = (0..w).find(|&x| (top..=bottom).any(|y| lit(x, y))).unwrap_or(0);
    let right = (left..w).rev().find(|&x| (top..=bottom).any(|y| lit(x, y))).unwrap_or(left);
    if (top, bottom, left, right) == (0, h - 1, 0, w - 1) {
        return (w, h, rgb);
    }
    let (tw, th) = (right - left + 1, bottom - top + 1);
    let mut out = Vec::with_capacity(tw * th * 3);
    for y in top..=bottom {
        out.extend_from_slice(&rgb[(y * w + left) * 3..(y * w + right + 1) * 3]);
    }
    (tw, th, out)
}

/// The picture as grim and magick wrote it: binary PPM, maxval 255.
pub fn ppm(w: usize, h: usize, rgb: &[u8]) -> Vec<u8> {
    let mut out = format!("P6\n{w} {h}\n255\n").into_bytes();
    out.extend_from_slice(rgb);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A w x h RGB picture, black but for the lit pixels.
    fn picture(w: usize, h: usize, lit: &[(usize, usize, [u8; 3])]) -> Vec<u8> {
        let mut rgb = vec![0; w * h * 3];
        for &(x, y, c) in lit {
            rgb[(y * w + x) * 3..][..3].copy_from_slice(&c);
        }
        rgb
    }

    #[test]
    fn trim_cuts_black_edges() {
        let rgb = picture(6, 5, &[(2, 1, [9, 0, 0]), (4, 3, [0, 0, 1])]);
        let (w, h, out) = trim_black(6, 5, rgb);
        assert_eq!((w, h), (3, 3));
        assert_eq!(&out[..3], &[9, 0, 0]);
        assert_eq!(&out[out.len() - 3..], &[0, 0, 1]);
    }

    #[test]
    fn trim_keeps_inner_black() {
        // Black rows and columns inside the picture stay.
        let rgb = picture(5, 5, &[(0, 0, [1, 1, 1]), (4, 4, [1, 1, 1])]);
        let (w, h, out) = trim_black(5, 5, rgb.clone());
        assert_eq!((w, h, out), (5, 5, rgb));
    }

    #[test]
    fn trim_all_black_is_one_white_pixel() {
        assert_eq!(trim_black(4, 3, vec![0; 36]), (1, 1, vec![255; 3]));
    }

    #[test]
    fn quarter_of_a_flat_capture_is_flat_inside() {
        // Opaque grey, stored BGRX: inside, far from the edges, the weights
        // sum to 1 and the grey comes back; the edges darken (the buffer
        // ends in transparent black).
        let (w, h) = (64, 40);
        let data: Vec<u8> = (0..w * h).flat_map(|_| [100, 100, 100, 255]).collect();
        let (dw, dh, rgb) = quarter(&Capture { data: &data, width: w, height: h, stride: w * 4, rgb: [2, 1, 0] }).unwrap();
        assert_eq!((dw, dh), (16, 10));
        assert_eq!(&rgb[(5 * dw + 8) * 3..][..3], &[100, 100, 100]);
        assert!(rgb[0] < 100);
    }

    #[test]
    fn taps_sum_to_one() {
        assert_eq!(taps().iter().sum::<i64>(), 65536);
    }
}
