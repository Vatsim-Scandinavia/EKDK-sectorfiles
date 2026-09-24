"""
Rebuilds GRpluginMaps.txt from the section files in this folder.

GRplugin reads GRpluginMaps.txt as a single file, so this script just
concatenates the sections below in order. Edit the section files, then
rerun this script (from anywhere) before committing or reloading EuroScope.

The output is written into this folder, alongside the section files, not
into ../GRpluginMaps.txt directly. Copy it over manually before reloading
EuroScope.

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
    "06_eksb.txt",
    "07_eksp.txt",
    "08_ekeb.txt",
    "09_ekod.txt",
]

here = pathlib.Path(__file__).parent
out_path = here / "GRpluginMaps.txt"

missing = [name for name in SECTIONS if not (here / name).exists()]
if missing:
    raise SystemExit(f"Missing section file(s): {', '.join(missing)}")

# Guard against a section file missing its own trailing newline, which would
# otherwise merge its last line with the next section's first line.
chunks = [(here / name).read_bytes() for name in SECTIONS]
for i in range(len(chunks) - 1):
    if not chunks[i].endswith((b"\r\n", b"\n")):
        chunks[i] += b"\r\n"
data = b"".join(chunks)
out_path.write_bytes(data)
print(f"Wrote {out_path} ({len(data)} bytes) from {len(SECTIONS)} sections.")
