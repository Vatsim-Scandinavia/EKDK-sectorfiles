"""
Rebuilds ../GRpluginMaps.txt from the section files in this folder.

GRplugin reads GRpluginMaps.txt as a single file, so this script just
concatenates the sections below in order. Edit the section files, then
rerun this script (from anywhere) before committing or reloading EuroScope.

Usage: python build.py
"""
import pathlib

SECTIONS = [
    "00_header_colors.txt",
    "01_approach_views.txt",
    "02_ekbi.txt",
    "03_ekch.txt",
    "04_ekyt.txt",
    "05_ekah.txt",
]

here = pathlib.Path(__file__).parent
out_path = here.parent / "GRpluginMaps.txt"

missing = [name for name in SECTIONS if not (here / name).exists()]
if missing:
    raise SystemExit(f"Missing section file(s): {', '.join(missing)}")

data = b"".join((here / name).read_bytes() for name in SECTIONS)
out_path.write_bytes(data)
print(f"Wrote {out_path} ({len(data)} bytes) from {len(SECTIONS)} sections.")
