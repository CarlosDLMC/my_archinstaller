//! Animations: QEasingCurve's curves and a value that eases from one target
//! to the next (a QML Behavior / NumberAnimation / ColorAnimation). A surface
//! with a running animation draws on every frame callback; none draws nothing.

use std::time::{Duration, Instant};

use crate::color::Color;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Easing {
    Linear,
    InQuad,
    OutQuad,
    OutCubic,
    InOutQuad,
    InOutCubic,
    /// Easing.BezierSpline with one segment: (x1, y1, x2, y2), ending at (1, 1).
    Bezier(f32, f32, f32, f32),
}

/// QEasingCurve::valueForProgress, same formulas as qeasingcurve.cpp.
pub fn ease(e: Easing, t: f32) -> f32 {
    let t = t.clamp(0.0, 1.0);
    match e {
        Easing::Linear => t,
        Easing::OutCubic => {
            let t = t - 1.0;
            t * t * t + 1.0
        }
        Easing::InQuad => t * t,
        Easing::OutQuad => -t * (t - 2.0),
        Easing::InOutQuad => {
            let t = t * 2.0;
            if t < 1.0 {
                t * t / 2.0
            } else {
                let t = t - 1.0;
                -0.5 * (t * (t - 2.0) - 1.0)
            }
        }
        Easing::InOutCubic => {
            let t = t * 2.0;
            if t < 1.0 {
                0.5 * t * t * t
            } else {
                let t = t - 2.0;
                0.5 * (t * t * t + 2.0)
            }
        }
        Easing::Bezier(x1, y1, x2, y2) => bezier(t, x1, y1, x2, y2),
    }
}

/// y for x on the cubic from (0,0) to (1,1) through the two control points.
fn bezier(x: f32, x1: f32, y1: f32, x2: f32, y2: f32) -> f32 {
    let cx = |s: f32| 3.0 * (1.0 - s) * (1.0 - s) * s * x1 + 3.0 * (1.0 - s) * s * s * x2 + s * s * s;
    let cy = |s: f32| 3.0 * (1.0 - s) * (1.0 - s) * s * y1 + 3.0 * (1.0 - s) * s * s * y2 + s * s * s;
    // bisection on the monotonic x(s)
    let (mut lo, mut hi) = (0.0f32, 1.0f32);
    for _ in 0..32 {
        let mid = (lo + hi) / 2.0;
        if cx(mid) < x {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    cy((lo + hi) / 2.0)
}

pub trait Lerp: Copy + PartialEq {
    fn lerp(a: Self, b: Self, t: f32) -> Self;
}

impl Lerp for f32 {
    fn lerp(a: f32, b: f32, t: f32) -> f32 {
        a + (b - a) * t
    }
}

impl Lerp for Color {
    fn lerp(a: Color, b: Color, t: f32) -> Color {
        Color::mix(a, b, t)
    }
}

/// A property with a Behavior: set() starts an animation from wherever the
/// value is now to the new target.
#[derive(Clone, Copy, Debug)]
pub struct Animated<T: Lerp> {
    from: T,
    to: T,
    start: Option<Instant>,
    dur: Duration,
    easing: Easing,
}

impl<T: Lerp> Animated<T> {
    pub fn new(v: T, ms: u64, easing: Easing) -> Self {
        Animated { from: v, to: v, start: None, dur: Duration::from_millis(ms), easing }
    }

    pub fn get(&self, now: Instant) -> T {
        match self.start {
            None => self.to,
            Some(s) => {
                let t = now.saturating_duration_since(s).as_secs_f32() / self.dur.as_secs_f32().max(1e-6);
                if t >= 1.0 {
                    self.to
                } else {
                    T::lerp(self.from, self.to, ease(self.easing, t))
                }
            }
        }
    }

    pub fn target(&self) -> T {
        self.to
    }

    pub fn set(&mut self, v: T, now: Instant) {
        if v == self.to {
            return;
        }
        self.from = self.get(now);
        self.to = v;
        self.start = Some(now);
    }

    /// Jump without animating (the first value, or a property without Behavior).
    pub fn snap(&mut self, v: T) {
        self.from = v;
        self.to = v;
        self.start = None;
    }

    pub fn running(&self, now: Instant) -> bool {
        self.start.map_or(false, |s| now.saturating_duration_since(s) < self.dur)
    }
}

/// SequentialAnimation { 1 -> lo (half), lo -> 1 (half) } with loops:
/// Infinite and alwaysRunToEnd: true - stopping lets the current cycle finish,
/// so the value always comes to rest at 1.
#[derive(Clone, Copy, Debug, Default)]
pub struct Pulse {
    start: Option<Instant>,
    /// Milliseconds after start at which it ends (the end of the cycle that was
    /// running when it was stopped).
    stop_at: Option<u64>,
}

impl Pulse {
    pub fn set_running(&mut self, on: bool, now: Instant, half_ms: u64) {
        match (on, self.start) {
            (true, None) => {
                self.start = Some(now);
                self.stop_at = None;
            }
            (true, Some(s)) => {
                let el = now.saturating_duration_since(s).as_millis() as u64;
                if self.stop_at.map_or(false, |end| el >= end) {
                    self.start = Some(now);
                }
                self.stop_at = None;
            }
            (false, Some(s)) if self.stop_at.is_none() => {
                let el = now.saturating_duration_since(s).as_millis() as u64;
                let cycle = 2 * half_ms;
                self.stop_at = Some((el / cycle + 1) * cycle);
            }
            _ => {}
        }
    }

    /// (value, still animating)
    pub fn value(&self, now: Instant, lo: f32, half_ms: u64, easing: Easing) -> (f32, bool) {
        let Some(s) = self.start else { return (1.0, false) };
        let el = now.saturating_duration_since(s).as_millis() as u64;
        if self.stop_at.map_or(false, |end| el >= end) {
            return (1.0, false);
        }
        let in_cycle = el % (2 * half_ms);
        let v = if in_cycle < half_ms {
            1.0 + (lo - 1.0) * ease(easing, in_cycle as f32 / half_ms as f32)
        } else {
            lo + (1.0 - lo) * ease(easing, (in_cycle - half_ms) as f32 / half_ms as f32)
        };
        (v, true)
    }
}
