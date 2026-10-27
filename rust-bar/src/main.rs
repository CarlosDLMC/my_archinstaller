mod anim;
mod app;
mod bar;
mod color;
mod gpu;
mod ipc;
mod pw;
mod services;
mod text;
mod theme;

use color::Color;
use gpu::{Gpu, Scene, TextStyle};
use text::{FontKey, Fonts};

/// `rust-bar textref SPEC OUT.png`: draws the rows of SPEC (one per line:
/// family|size|bold 0/1|style n/o|color|styleColor|text) in a Column at
/// x 10, y 6, spacing 4 - the same layout tests/textref/shell.qml shows in
/// quickshell, so the two renders can be diffed pixel for pixel.
fn textref(spec: &str, out: &str) {
    let mut fonts = Fonts::new();
    let mut gpu = Gpu::new(None, Gpu::new_instance());
    let (w, h) = (900u32, 400u32);
    let mut scene = Scene::new(w as f32, h as f32);
    scene.fill(0.0, 0.0, w as f32, h as f32, Color::parse("#202020").unwrap());
    let mut y = 6.0f32;
    for row in std::fs::read_to_string(spec).expect("spec").lines() {
        let f: Vec<&str> = row.splitn(7, '|').collect();
        if f.len() < 7 {
            continue;
        }
        let family: &'static str = Box::leak(f[0].to_string().into_boxed_str());
        let size: f32 = f[1].parse().unwrap();
        let key = FontKey { family, bold: f[2] == "1" };
        let color = Color::parse(f[4]).unwrap();
        let style = if f[3] == "o" { TextStyle::Outline(Color::parse(f[5]).unwrap()) } else { TextStyle::Normal };
        let text = f[6].replace("\\u{f303}", "\u{f303}");
        let line = fonts.layout(&text, key, size, 0.0);
        println!("{text:?}: width {:.3} height {:.3} ascent {:.3}", line.width, line.height(), line.ascent);
        scene.text(&mut fonts, &line, 10.0, y + line.ascent, color, style);
        y += line.height() + 4.0;
    }
    let px = gpu.render_to_rgba(&mut fonts, &mut scene, w, h, [0.0, 0.0, 0.0, 0.0]);
    gpu::write_png(out, w, h, &px);
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("textref") if args.len() == 4 => textref(&args[2], &args[3]),
        Some("msg") => std::process::exit(ipc::client(&args[2..])),
        None => app::App::run(),
        _ => eprintln!("usage: rust-bar [msg <target> <function> [args...] | textref SPEC OUT.png]"),
    }
}
