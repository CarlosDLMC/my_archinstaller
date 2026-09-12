# GTK themes, icons and cursors

Vendored copies of the GTK themes, icon sets and cursor theme that
`install-scripts/gtk_themes.sh` unpacks into `~/.themes` and `~/.icons`.

They are committed here on purpose rather than cloned at install time: a clone
makes the install depend on a third-party repository still existing and still
containing the same files, and the previous version of `gtk_themes.sh` deleted
this directory before re-cloning it, which meant a network failure left the
machine with no themes at all.

`gtk_themes.sh` runs `auto-extract.sh` from this directory. To unpack them by
hand:

```bash
cd GTK-themes-icons
chmod +x auto-extract.sh
./auto-extract.sh
```

Apply them with `nwg-look`, or:

```bash
gsettings set org.gnome.desktop.interface gtk-theme Flat-Remix-GTK-Blue-Dark
gsettings set org.gnome.desktop.interface icon-theme Flat-Remix-Blue-Dark
```

## Credit and source

- Flat Remix GTK theme — [daniruiz/flat-remix-gtk](https://github.com/daniruiz/flat-remix-gtk)
- Flat Remix icon theme — [daniruiz/flat-remix](https://github.com/daniruiz/flat-remix)
- Bibata cursors — [ful1e5/Bibata_Cursor](https://github.com/ful1e5/Bibata_Cursor)
