"""
Rebuilds TopSkyMaps.txt from the section files in this folder.

GRplugin reads TopSkyMaps.txt as a single file, so this script just
concatenates the sections below in order. Edit the section files, then
rerun this script (from anywhere) before committing or reloading EuroScope.

The output is written into this folder, alongside the section files, not
into ../TopSkyMaps.txt directly. Copy it over manually before reloading
EuroScope.

Usage: python build.py
"""
import pathlib

SECTIONS = [
    "00_header_colors.txt",
    "01_airspace_config.txt",
    "02_atc_help.txt",
    "03_ekch_tma.txt",
    "04_ekbi.txt",
    "05_ekyt.txt",
    "06_ekah.txt",
    "07_ekka.txt",
    "08_eksp.txt",
    "09_acc.txt",
]

here = pathlib.Path(__file__).parent
out_path = here / "TopSkyMaps.txt"

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
