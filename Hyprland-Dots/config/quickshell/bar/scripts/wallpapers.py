#!/usr/bin/env python3
"""Wallpaper list and thumbnails for the bar's wallpaper carousel (SUPER W).

    wallpapers.py scan  ROOT CACHE   list every wallpaper under ROOT, then make
                                     the thumbnails that are missing in CACHE
    wallpapers.py apply ROOT ID      apply the wallpaper whose id is ID

`scan` prints one JSON line first - {"current", "items": [...]} - so the
carousel can draw at once, then "thumb ID" (or "fail ID") as each missing
thumbnail lands, then "done". All of it is ASCII whatever the file names are.

A wallpaper's id is the md5 of its path *bytes*. The carousel hands the id back
to `apply`, which walks ROOT again to find the file, so the path itself never
has to survive a trip through QML: a name that is not valid UTF-8 turns into
U+FFFD the moment it becomes a QString and could never be opened again. The rofi
menu in WallpaperSelect.sh solved the same problem by returning the index of
the pick instead of its text.

Thumbnails are CACHE/<md5 of path, mtime and size>.jpg, so an edited wallpaper
gets a new one, and any thumbnail no longer named by a wallpaper is deleted.
"""

import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed

# The types WallpaperSelect.sh lists - it is what applies the pick.
IMAGES = {b".jpg", b".jpeg", b".png", b".gif", b".bmp", b".tiff", b".webp"}
VIDEOS = {b".mp4", b".mkv", b".mov", b".webm"}

# Tall enough for the centred card at its largest on a 1440p screen.
THUMB_H = 720

HOME = os.path.expanduser("~")
# WallustSwww.sh points this at the wallpaper on screen (never at an effect
# image), so it is the record of what is current.
CURRENT_LINK = os.fsencode(os.path.join(HOME, ".config/rofi/.current_wallpaper"))
APPLY = os.fsencode(os.path.join(HOME, ".config/hypr/UserScripts/WallpaperSelect.sh"))
THUMB_RE = re.compile(r"^[0-9a-f]{32}\.jpg$")


def walk(root):
    """(path, stat) for every wallpaper under root, as bytes. Follows symlinks
    like the `find -L` in the shell scripts, but never round a loop."""
    seen = set()
    stack = [root]
    while stack:
        d = stack.pop()
        try:
            st = os.stat(d)
        except OSError:
            continue
        if (st.st_dev, st.st_ino) in seen:
            continue
        seen.add((st.st_dev, st.st_ino))
        try:
            with os.scandir(d) as it:
                entries = list(it)
        except OSError:
            continue
        for e in entries:
            try:
                if e.is_dir():
                    stack.append(e.path)
                elif e.is_file() and os.path.splitext(e.name)[1].lower() in IMAGES | VIDEOS:
                    yield e.path, e.stat()
            except OSError:
                continue


def path_id(path):
    return hashlib.md5(path).hexdigest()


def thumb_name(path, st):
    key = b"%s\0%d\0%d" % (path, st.st_mtime_ns, st.st_size)
    return hashlib.md5(key).hexdigest() + ".jpg"


listening = True


def say(line):
    """A line for the carousel. If it has stopped reading - the bar reloaded
    mid-scan - finish the thumbnails anyway and go quiet, rather than die on
    the closed pipe and leave the rest for the next scan."""
    global listening
    if not listening:
        return
    try:
        print(line, flush=True)
    except BrokenPipeError:
        listening = False
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())


def natural(s):
    """Sort key: case-insensitive, and "wall2" before "wall10"."""
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", s.casefold())]


def text(b):
    return b.decode("utf-8", "replace")


def label(b):
    # What is shown, never what is opened: a CR or LF would split the line
    # under the carousel, so it reads "?" as it did in the rofi menu.
    return text(b).replace("\n", "?").replace("\r", "?")


def file_url(path):
    # Percent-encoded, so "#", "?" and "%" in a name stay part of the path.
    return "file://" + urllib.parse.quote(path)


def playing_video():
    """The file mpvpaper is playing, if it is running: a video wallpaper never
    goes through WallustSwww.sh, so the link above still names the last image."""
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/comm", "rb") as f:
                if f.read().strip() != b"mpvpaper":
                    continue
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                args = [a for a in f.read().split(b"\0") if a]
        except OSError:
            continue
        if args:
            return args[-1]
    return None


def current_path():
    video = playing_video()
    if video:
        return os.path.realpath(video)
    try:
        return os.path.realpath(CURRENT_LINK)
    except OSError:
        return None


def make_thumb(src, kind, out):
    tmp = os.path.join(os.path.dirname(out), b".%d.%s" % (os.getpid(), os.path.basename(out)))
    quiet = {"stdin": subprocess.DEVNULL, "stdout": subprocess.DEVNULL,
             "stderr": subprocess.DEVNULL, "timeout": 60}
    try:
        if kind == "video":
            # A second in, past the fade-in most clips open with; a clip shorter
            # than that yields no frame, so then the very first one.
            for seek in ([b"-ss", b"1"], []):
                subprocess.run([b"ffmpeg", b"-nostdin", b"-v", b"error", b"-y", *seek,
                                b"-i", src, b"-frames:v", b"1",
                                b"-vf", b"scale=-2:%d" % THUMB_H, b"-update", b"1", tmp],
                               **quiet)
                if os.path.isfile(tmp) and os.path.getsize(tmp) > 0:
                    break
        else:
            # % doubled: magick reads %d in a file name as a frame number (the
            # same fix as the GIF previews in WallpaperSelect.sh). [0] is the
            # first frame of a GIF and a no-op for anything else. jpeg:size lets
            # libjpeg decode a 6K photo at a fraction of its size.
            subprocess.run([b"magick", b"-define", b"jpeg:size=2560x1440",
                            src.replace(b"%", b"%%") + b"[0]", b"-auto-orient",
                            b"-thumbnail", b"x%d>" % THUMB_H, b"-quality", b"85", tmp],
                           **quiet)
        if os.path.isfile(tmp) and os.path.getsize(tmp) > 0:
            os.replace(tmp, out)
            return True
    except (OSError, subprocess.SubprocessError):
        pass
    try:
        os.unlink(tmp)
    except OSError:
        pass
    return False


def scan(root, cache):
    found = []
    for path, st in walk(root):
        rel = os.path.relpath(os.path.dirname(path), root)
        ext = os.path.splitext(path)[1].lower()
        found.append((path, st, b"" if rel == b"." else rel,
                      "video" if ext in VIDEOS else "gif" if ext == b".gif" else "image"))
    # Top level first, then the folders; natural order inside each.
    found.sort(key=lambda f: (natural(text(f[2])), natural(text(os.path.basename(f[0])))))

    current = current_path()
    items, missing, names = [], [], set()
    current_id = ""
    for path, st, rel, kind in found:
        pid = path_id(path)
        name = os.fsencode(thumb_name(path, st))
        names.add(name)
        thumb = os.path.join(cache, name)
        if current is not None and os.path.realpath(path) == current:
            current_id = pid
        items.append({
            "id": pid,
            "name": label(os.path.basename(path)),
            "dir": label(rel),
            "kind": kind,
            "src": file_url(path),
            "thumb": file_url(thumb),
            "ready": os.path.isfile(thumb),
        })
        if not items[-1]["ready"]:
            missing.append((pid, path, kind, thumb))

    say(json.dumps({"current": current_id, "items": items}, ensure_ascii=True))

    # The list is out; the rest is background work, so stay out of the way.
    os.nice(10)
    os.makedirs(cache, exist_ok=True)
    # One generator at a time: a bar reloaded mid-run starts a second scan,
    # which waits here and then finds the thumbnails already made.
    with open(os.path.join(cache, b".lock"), "wb") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # Thumbnails of wallpapers that are gone (or were edited since), and
        # the half-written files of a run that was killed.
        for name in os.listdir(cache):
            part = name.startswith(b".") and name.endswith(b".jpg")
            if part or (THUMB_RE.match(text(name)) and name not in names):
                try:
                    os.unlink(os.path.join(cache, name))
                except OSError:
                    pass
        todo = []
        for pid, path, kind, thumb in missing:
            if os.path.isfile(thumb):
                say("thumb " + pid)  # made while we waited for the lock
            else:
                todo.append((pid, path, kind, thumb))
        with ThreadPoolExecutor(max_workers=min(4, os.cpu_count() or 1)) as pool:
            jobs = {pool.submit(make_thumb, path, kind, thumb): pid
                    for pid, path, kind, thumb in todo}
            for job in as_completed(jobs):
                say(("thumb " if job.result() else "fail ") + jobs[job])
    say("done")


def notify(body):
    subprocess.run(["notify-send", "-u", "low", "Wallpaper", body],
                   stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def apply(root, wanted):
    for path, _ in walk(root):
        if path_id(path) == wanted:
            try:
                os.execv(APPLY, [APPLY, path])
            except OSError as e:
                notify(f"Cannot run WallpaperSelect.sh: {e.strerror}")
                return 1
    notify("That wallpaper is gone - it was moved or deleted.")
    return 1


def main(argv):
    if len(argv) == 4 and argv[1] == "scan":
        scan(os.fsencode(argv[2]), os.fsencode(argv[3]))
        return 0
    if len(argv) == 4 and argv[1] == "apply":
        return apply(os.fsencode(argv[2]), argv[3])
    print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
