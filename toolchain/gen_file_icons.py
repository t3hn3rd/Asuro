#!/usr/bin/env python3
"""
gen_file_icons.py — Generate LVGL-compatible icon font C files from Font Awesome.

Renders FA glyphs at multiple sizes (32, 64, 128) with per-file-type label
overlays. Outputs asuro_icons_{size}.c files that compile into liblvgl.a.

Uses PIL (python3-pil) to rasterize Font Awesome TTF glyphs and composite
type-specific text labels. Output is in LVGL lv_font_fmt_txt format with
4bpp anti-aliased bitmaps in the Unicode Private Use Area (U+E000–E0FF).

Usage:
    python3 gen_file_icons.py <output_dir> [--font-dir <font_cache_dir>]

Dependencies: python3-pil (already in Dockerfile)
"""

import os
import sys
import struct
import math
import urllib.request
from PIL import Image, ImageDraw, ImageFont

# =============================================================================
# Configuration
# =============================================================================

FA_VERSION = "6.7.2"
FA_TTF_URL = (
    f"https://github.com/FortAwesome/Font-Awesome/releases/download/"
    f"{FA_VERSION}/fontawesome-free-{FA_VERSION}-desktop.zip"
)
# We'll download the individual TTF directly from the release assets
FA_SOLID_URL = (
    f"https://raw.githubusercontent.com/FortAwesome/Font-Awesome/"
    f"{FA_VERSION}/webfonts/fa-solid-900.ttf"
)

SIZES = [32, 64, 128]
BPP = 4  # 4 bits per pixel (16 levels of anti-aliasing)

# Font Awesome codepoints for base shapes
FA_FILE = 0xF15B       # file (blank)
FA_FILE_CODE = 0xF1C9  # file-code (angle brackets)
FA_FILE_LINES = 0xF15C # file-lines (text lines on file)
FA_FILE_IMAGE = 0xF1C5 # file-image
FA_FILE_AUDIO = 0xF1C7 # file-audio (music note on file)
FA_FILE_VIDEO = 0xF1C8 # file-video (play on file)
FA_FILE_ZIP = 0xF1C6   # file-zipper
FA_FILE_PDF = 0xF1C1   # file-pdf
FA_FOLDER = 0xF07B     # folder
FA_FOLDER_OPEN = 0xF07C # folder-open
FA_HDD = 0xF0A0        # hard-drive
FA_LINK = 0xF0C1       # link
FA_GEAR = 0xF013       # gear
FA_DATABASE = 0xF1C0   # database (stacked disks)
FA_KEY = 0xF084        # key
FA_TERMINAL = 0xF120   # terminal
FA_FONT = 0xF031       # font (big A)
FA_CODE = 0xF121       # code (angle brackets)
FA_CUBE = 0xF1B2       # cube

# Category colors (R, G, B) — used for label background bands
CLR_GENERIC  = (120, 130, 150)  # Slate grey
CLR_CODE     = (60, 120, 210)   # Blue
CLR_DOC      = (140, 150, 165)  # Grey
CLR_DATA     = (40, 170, 160)   # Teal
CLR_IMAGE    = (50, 180, 80)    # Green
CLR_AUDIO    = (140, 80, 200)   # Purple
CLR_VIDEO    = (190, 60, 150)   # Magenta
CLR_ARCHIVE  = (220, 140, 30)   # Orange
CLR_SYSTEM   = (200, 60, 60)    # Red
CLR_FONT     = (200, 160, 40)   # Amber
CLR_MISC     = (100, 110, 130)  # Slate

# Icon definitions: (pua_codepoint, fa_base_glyph, label_text, category_color)
# label_text=None means no overlay (just the base glyph)
ICONS = [
    # === Generic (E000–E005) ===
    (0xE000, FA_FILE,        None,   CLR_GENERIC),   # Generic file
    (0xE001, FA_FOLDER,      None,   CLR_GENERIC),   # Folder closed
    (0xE002, FA_FOLDER_OPEN, None,   CLR_GENERIC),   # Folder open
    (0xE003, FA_HDD,         None,   CLR_GENERIC),   # Drive
    (0xE004, FA_CUBE,        None,   CLR_GENERIC),   # Mount point
    (0xE005, FA_LINK,        None,   CLR_GENERIC),   # Symlink

    # === Code (E010–E023) ===
    (0xE010, FA_FILE_CODE,   None,   CLR_CODE),      # Generic code
    (0xE011, FA_FILE_CODE,   "PAS",  CLR_CODE),      # Pascal
    (0xE012, FA_FILE_CODE,   "PY",   CLR_CODE),      # Python
    (0xE013, FA_FILE_CODE,   "JS",   CLR_CODE),      # JavaScript
    (0xE014, FA_FILE_CODE,   "TS",   CLR_CODE),      # TypeScript
    (0xE015, FA_FILE_CODE,   "C",    CLR_CODE),      # C source
    (0xE016, FA_FILE_CODE,   "H",    CLR_CODE),      # C header
    (0xE017, FA_FILE_CODE,   "C++",  CLR_CODE),      # C++
    (0xE018, FA_FILE_CODE,   "RS",   CLR_CODE),      # Rust
    (0xE019, FA_FILE_CODE,   "GO",   CLR_CODE),      # Go
    (0xE01A, FA_FILE_CODE,   "RB",   CLR_CODE),      # Ruby
    (0xE01B, FA_TERMINAL,    "SH",   CLR_CODE),      # Shell script
    (0xE01C, FA_FILE_CODE,   "ASM",  CLR_CODE),      # Assembly
    (0xE01D, FA_FILE_CODE,   "LUA",  CLR_CODE),      # Lua
    (0xE01E, FA_FILE_CODE,   "SQL",  CLR_CODE),      # SQL
    (0xE01F, FA_FILE_CODE,   "CSS",  CLR_CODE),      # CSS
    (0xE020, FA_FILE_CODE,   "HTM",  CLR_CODE),      # HTML
    (0xE021, FA_FILE_CODE,   "PHP",  CLR_CODE),      # PHP
    (0xE022, FA_FILE_CODE,   "JAV",  CLR_CODE),      # Java
    (0xE023, FA_FILE_CODE,   "C#",   CLR_CODE),      # C#

    # === Documents (E028–E02F) ===
    (0xE028, FA_FILE_LINES,  "TXT",  CLR_DOC),       # Plain text
    (0xE029, FA_FILE_LINES,  "MD",   CLR_DOC),       # Markdown
    (0xE02A, FA_FILE_PDF,    None,   CLR_DOC),        # PDF (has its own icon)
    (0xE02B, FA_FILE_LINES,  "DOC",  CLR_DOC),       # Word
    (0xE02C, FA_FILE_LINES,  "RTF",  CLR_DOC),       # Rich text
    (0xE02D, FA_FILE_LINES,  "LOG",  CLR_DOC),       # Log
    (0xE02E, FA_FILE_LINES,  "CSV",  CLR_DOC),       # CSV
    (0xE02F, FA_FILE_LINES,  "TEX",  CLR_DOC),       # LaTeX

    # === Data/Config (E030–E036) ===
    (0xE030, FA_FILE_CODE,   "JSN",  CLR_DATA),      # JSON
    (0xE031, FA_FILE_CODE,   "XML",  CLR_DATA),      # XML
    (0xE032, FA_FILE_CODE,   "YML",  CLR_DATA),      # YAML
    (0xE033, FA_FILE,        "INI",  CLR_DATA),       # INI
    (0xE034, FA_FILE,        "CFG",  CLR_DATA),       # Config
    (0xE035, FA_FILE,        "ENV",  CLR_DATA),       # Env
    (0xE036, FA_FILE_CODE,   "TML",  CLR_DATA),      # TOML

    # === Images (E038–E041) ===
    (0xE038, FA_FILE_IMAGE,  None,   CLR_IMAGE),      # Generic image
    (0xE039, FA_FILE_IMAGE,  "PNG",  CLR_IMAGE),      # PNG
    (0xE03A, FA_FILE_IMAGE,  "JPG",  CLR_IMAGE),      # JPEG
    (0xE03B, FA_FILE_IMAGE,  "BMP",  CLR_IMAGE),      # Bitmap
    (0xE03C, FA_FILE_IMAGE,  "TGA",  CLR_IMAGE),      # Targa
    (0xE03D, FA_FILE_IMAGE,  "GIF",  CLR_IMAGE),      # GIF
    (0xE03E, FA_FILE_IMAGE,  "SVG",  CLR_IMAGE),      # SVG
    (0xE03F, FA_FILE_IMAGE,  "ICO",  CLR_IMAGE),      # Icon
    (0xE040, FA_FILE_IMAGE,  "PSD",  CLR_IMAGE),      # Photoshop
    (0xE041, FA_FILE_IMAGE,  "WBP",  CLR_IMAGE),      # WebP

    # === Audio (E044–E049) ===
    (0xE044, FA_FILE_AUDIO,  None,   CLR_AUDIO),      # Generic audio
    (0xE045, FA_FILE_AUDIO,  "MP3",  CLR_AUDIO),      # MP3
    (0xE046, FA_FILE_AUDIO,  "WAV",  CLR_AUDIO),      # WAV
    (0xE047, FA_FILE_AUDIO,  "OGG",  CLR_AUDIO),      # OGG
    (0xE048, FA_FILE_AUDIO,  "FLC",  CLR_AUDIO),      # FLAC
    (0xE049, FA_FILE_AUDIO,  "MID",  CLR_AUDIO),      # MIDI

    # === Video (E04C–E051) ===
    (0xE04C, FA_FILE_VIDEO,  None,   CLR_VIDEO),      # Generic video
    (0xE04D, FA_FILE_VIDEO,  "MP4",  CLR_VIDEO),      # MP4
    (0xE04E, FA_FILE_VIDEO,  "AVI",  CLR_VIDEO),      # AVI
    (0xE04F, FA_FILE_VIDEO,  "MKV",  CLR_VIDEO),      # MKV
    (0xE050, FA_FILE_VIDEO,  "WBM",  CLR_VIDEO),      # WebM
    (0xE051, FA_FILE_VIDEO,  "MOV",  CLR_VIDEO),      # MOV

    # === Archives (E054–E05C) ===
    (0xE054, FA_FILE_ZIP,    None,   CLR_ARCHIVE),    # Generic archive
    (0xE055, FA_FILE_ZIP,    "ZIP",  CLR_ARCHIVE),    # ZIP
    (0xE056, FA_FILE_ZIP,    "TAR",  CLR_ARCHIVE),    # TAR
    (0xE057, FA_FILE_ZIP,    "GZ",   CLR_ARCHIVE),    # Gzip
    (0xE058, FA_FILE_ZIP,    "7Z",   CLR_ARCHIVE),    # 7-Zip
    (0xE059, FA_FILE_ZIP,    "RAR",  CLR_ARCHIVE),    # RAR
    (0xE05A, FA_FILE_ZIP,    "XZ",   CLR_ARCHIVE),    # XZ
    (0xE05B, FA_FILE_ZIP,    "BZ2",  CLR_ARCHIVE),    # BZip2
    (0xE05C, FA_FILE_ZIP,    "ISO",  CLR_ARCHIVE),    # ISO image

    # === System/Binary (E060–E069) ===
    (0xE060, FA_GEAR,        None,   CLR_SYSTEM),     # Generic system
    (0xE061, FA_FILE,        "BIN",  CLR_SYSTEM),     # Binary
    (0xE062, FA_FILE,        "EXE",  CLR_SYSTEM),     # Executable
    (0xE063, FA_FILE,        "DLL",  CLR_SYSTEM),     # Library
    (0xE064, FA_FILE,        "SO",   CLR_SYSTEM),     # Shared object
    (0xE065, FA_FILE,        "PPU",  CLR_SYSTEM),     # FPC unit
    (0xE066, FA_FILE,        "OBJ",  CLR_SYSTEM),     # Object file
    (0xE067, FA_FILE,        "WSM",  CLR_SYSTEM),     # WebAssembly
    (0xE068, FA_FILE,        "ELF",  CLR_SYSTEM),     # ELF binary
    (0xE069, FA_GEAR,        "KRN",  CLR_SYSTEM),     # Kernel/driver

    # === Font/Media (E06C–E06F) ===
    (0xE06C, FA_FONT,        None,   CLR_FONT),       # Generic font
    (0xE06D, FA_FONT,        "TTF",  CLR_FONT),       # TrueType
    (0xE06E, FA_FONT,        "OTF",  CLR_FONT),       # OpenType
    (0xE06F, FA_FONT,        "WOF",  CLR_FONT),       # WOFF

    # === Misc (E070–E078) ===
    (0xE070, FA_LINK,        "LNK",  CLR_MISC),       # Shortcut
    (0xE071, FA_FILE,        "BAK",  CLR_MISC),       # Backup
    (0xE072, FA_FILE,        "TMP",  CLR_MISC),       # Temporary
    (0xE073, FA_FILE,        "LCK",  CLR_MISC),       # Lock file
    (0xE074, FA_KEY,         None,   CLR_MISC),        # Key/cert
    (0xE075, FA_DATABASE,    None,   CLR_MISC),        # Database
    (0xE076, FA_CODE,        "GIT",  CLR_MISC),        # Git file
    (0xE077, FA_FILE,        "MK",   CLR_MISC),        # Makefile
    (0xE078, FA_FILE,        "DKR",  CLR_MISC),        # Dockerfile
]

# Build a contiguous range covering all icons (with empty slots for gaps)
PUA_START = 0xE000
PUA_END = max(cp for cp, _, _, _ in ICONS)


# =============================================================================
# Font Awesome TTF download/cache
# =============================================================================

def ensure_fa_ttf(font_dir):
    """Download Font Awesome Solid 900 TTF if not cached."""
    os.makedirs(font_dir, exist_ok=True)
    ttf_path = os.path.join(font_dir, "fa-solid-900.ttf")
    if os.path.exists(ttf_path):
        return ttf_path
    print(f"  Downloading Font Awesome {FA_VERSION} TTF...")
    urllib.request.urlretrieve(FA_SOLID_URL, ttf_path)
    print(f"  Saved to {ttf_path}")
    return ttf_path


# =============================================================================
# Glyph rendering
# =============================================================================

def render_glyph(fa_font, label_font, size, fa_codepoint, label_text, color):
    """
    Render one icon glyph as a greyscale PIL Image.

    1. Render the FA base glyph at full size, centered in the cell
    2. If label_text is set, overlay it directly on the lower portion of
       the glyph: punch a dark strip into the existing pixels, then draw
       bright white text on top for maximum contrast
    3. Return the image as greyscale (L mode)
    """
    img = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(img)

    # Render FA glyph — full size, centered
    fa_char = chr(fa_codepoint)
    fa_size = int(size * 0.82)
    try:
        fa_pil = ImageFont.truetype(fa_font, fa_size)
    except Exception:
        fa_pil = ImageFont.truetype(fa_font, int(size * 0.7))

    bbox = fa_pil.getbbox(fa_char)
    if bbox is None:
        margin = size // 8
        draw.rectangle([margin, margin, size - margin, size - margin],
                       fill=180, outline=255)
        return img

    gw = bbox[2] - bbox[0]
    gh = bbox[3] - bbox[1]
    gx = (size - gw) // 2 - bbox[0]
    gy = (size - gh) // 2 - bbox[1]
    draw.text((gx, gy), fa_char, fill=255, font=fa_pil)

    # Overlay label text on the lower portion of the glyph
    if label_text:
        # Size the label font: ~30% of icon height, minimum 8px
        lbl_size = max(8, int(size * 0.30))
        try:
            lbl_font = ImageFont.truetype(label_font, lbl_size)
            # Shrink if text is wider than the icon
            lbbox = lbl_font.getbbox(label_text)
            if lbbox:
                lw = lbbox[2] - lbbox[0]
                while lw > size - 2 and lbl_size > 7:
                    lbl_size -= 1
                    lbl_font = ImageFont.truetype(label_font, lbl_size)
                    lbbox = lbl_font.getbbox(label_text)
                    if lbbox:
                        lw = lbbox[2] - lbbox[0]
        except Exception:
            lbl_font = ImageFont.load_default()

        lbbox = lbl_font.getbbox(label_text)
        if lbbox:
            lw = lbbox[2] - lbbox[0]
            lh = lbbox[3] - lbbox[1]
            # Position: centered horizontally, bottom-aligned with small margin
            pad = max(1, size // 16)
            lx = (size - lw) // 2 - lbbox[0]
            ly = size - lh - pad - lbbox[1]

            # Punch a dark rectangle behind the text for contrast
            # 2px padding around the text
            tp = max(1, size // 16)
            rx0 = max(0, lx + lbbox[0] - tp)
            ry0 = max(0, ly + lbbox[1] - tp)
            rx1 = min(size - 1, lx + lbbox[0] + lw + tp)
            ry1 = min(size - 1, ly + lbbox[1] + lh + tp)

            # Darken: set the region to a low value so the glyph fades there
            draw.rectangle([rx0, ry0, rx1, ry1], fill=40)

            # Draw the text in full white — maximum 4bpp contrast vs fill=40
            # fill=40 -> quantises to 2, fill=255 -> quantises to 15 = 13 steps
            draw.text((lx, ly), label_text, fill=255, font=lbl_font)

    return img


# =============================================================================
# LVGL C font file generation
# =============================================================================

def quantize_4bpp(img):
    """Convert greyscale image to 4bpp packed bytes (high nibble first)."""
    w, h = img.size
    pixels = list(img.getdata())
    result = []
    row_bytes = (w + 1) // 2  # ceil(w/2)

    for row in range(h):
        for col_pair in range(row_bytes):
            c0 = col_pair * 2
            c1 = c0 + 1
            idx0 = row * w + c0
            idx1 = row * w + c1

            # Quantize 0-255 to 0-15
            p0 = min(15, pixels[idx0] >> 4) if c0 < w else 0
            p1 = min(15, pixels[idx1] >> 4) if c1 < w else 0
            result.append((p0 << 4) | p1)

    return bytes(result)


def generate_font_c(icons_data, size, font_name):
    """
    Generate LVGL-compatible C source for a font.

    icons_data: list of (codepoint, bitmap_bytes, box_w, box_h)
                sorted by codepoint, contiguous from PUA_START.
    """
    lines = []

    # Header
    lines.append("/*******************************************************************************")
    lines.append(f" * Asuro file-type icons — {size}px")
    lines.append(f" * Bpp: {BPP}")
    lines.append(f" * Auto-generated by gen_file_icons.py — DO NOT EDIT")
    lines.append(" ******************************************************************************/")
    lines.append("")
    lines.append("#ifdef LV_LVGL_H_INCLUDE_SIMPLE")
    lines.append('    #include "lvgl.h"')
    lines.append("#else")
    lines.append('    #include "lvgl/lvgl.h"')
    lines.append("#endif")
    lines.append("")
    lines.append(f"#ifndef {font_name.upper()}")
    lines.append(f"#define {font_name.upper()} 1")
    lines.append("#endif")
    lines.append("")
    lines.append(f"#if {font_name.upper()}")
    lines.append("")

    # Build contiguous glyph table from PUA_START to PUA_END
    # Map codepoints to their data
    cp_map = {cp: (bm, bw, bh) for cp, bm, bw, bh in icons_data}

    # Contiguous range PUA_START..PUA_END
    glyph_list = []
    for cp in range(PUA_START, PUA_END + 1):
        if cp in cp_map:
            glyph_list.append((cp, cp_map[cp][0], cp_map[cp][1], cp_map[cp][2]))
        else:
            # Empty placeholder glyph (zero-size)
            glyph_list.append((cp, b"", 0, 0))

    # === glyph_bitmap[] ===
    lines.append("/*-----------------------")
    lines.append(" *  Glyph bitmap data")
    lines.append(" *-----------------------*/")
    lines.append("")
    lines.append("static LV_ATTRIBUTE_LARGE_CONST const uint8_t glyph_bitmap[] = {")

    bitmap_offset = 0
    glyph_offsets = []  # (bitmap_index, box_w, box_h)

    for cp, bm, bw, bh in glyph_list:
        glyph_offsets.append((bitmap_offset, bw, bh))
        if len(bm) > 0:
            lines.append(f"    /* U+{cp:04X} */")
            # Format bitmap bytes, 16 per line
            for i in range(0, len(bm), 16):
                chunk = bm[i:i+16]
                hex_str = ", ".join(f"0x{b:02x}" for b in chunk)
                comma = "," if i + 16 < len(bm) else ","
                lines.append(f"    {hex_str}{comma}")
            bitmap_offset += len(bm)
        lines.append("")

    lines.append("};")
    lines.append("")

    # === glyph_dsc[] ===
    # adv_w is box_w * 16 (8.4 fixed point) + small padding
    lines.append("/*-----------------------")
    lines.append(" *  Glyph descriptors")
    lines.append(" *-----------------------*/")
    lines.append("")
    lines.append("static const lv_font_fmt_txt_glyph_dsc_t glyph_dsc[] = {")
    lines.append("    {.bitmap_index = 0, .adv_w = 0, .box_w = 0, "
                 ".box_h = 0, .ofs_x = 0, .ofs_y = 0},    /* sentinel */")

    for i, (bm_idx, bw, bh) in enumerate(glyph_offsets):
        cp = PUA_START + i
        if bw == 0 and bh == 0:
            # Empty slot
            adv_w = size * 16  # still advance by full cell
            lines.append(f"    {{.bitmap_index = 0, .adv_w = {adv_w}, "
                         f".box_w = 0, .box_h = 0, "
                         f".ofs_x = 0, .ofs_y = 0}},    /* U+{cp:04X} empty */")
        else:
            adv_w = (bw + 1) * 16  # advance = box width + 1px padding
            ofs_y = 0  # glyph top aligns with line top (base_line=0)
            lines.append(f"    {{.bitmap_index = {bm_idx}, .adv_w = {adv_w}, "
                         f".box_w = {bw}, .box_h = {bh}, "
                         f".ofs_x = 0, .ofs_y = {ofs_y}}},    /* U+{cp:04X} */")

    lines.append("};")
    lines.append("")

    # === cmap — FORMAT0_TINY (contiguous range) ===
    num_glyphs = PUA_END - PUA_START + 1
    lines.append("/*-----------------------")
    lines.append(" *  Character map")
    lines.append(" *-----------------------*/")
    lines.append("")
    lines.append("static const lv_font_fmt_txt_cmap_t cmaps[] = {")
    lines.append("    {")
    lines.append(f"        .range_start = {PUA_START}, .range_length = {num_glyphs}, "
                 f".glyph_id_start = 1,")
    lines.append("        .unicode_list = NULL, .glyph_id_ofs_list = NULL, "
                 ".list_length = 0,")
    lines.append("        .type = LV_FONT_FMT_TXT_CMAP_FORMAT0_TINY")
    lines.append("    }")
    lines.append("};")
    lines.append("")

    # === font_dsc ===
    lines.append("/*-----------------------")
    lines.append(" *  Font descriptor")
    lines.append(" *-----------------------*/")
    lines.append("")
    lines.append("static const lv_font_fmt_txt_dsc_t font_dsc = {")
    lines.append("    .glyph_bitmap = glyph_bitmap,")
    lines.append("    .glyph_dsc = glyph_dsc,")
    lines.append("    .cmaps = cmaps,")
    lines.append("    .kern_dsc = NULL,")
    lines.append("    .kern_scale = 0,")
    lines.append("    .cmap_num = 1,")
    lines.append(f"    .bpp = {BPP},")
    lines.append("    .kern_classes = 0,")
    lines.append("    .bitmap_format = 0")
    lines.append("};")
    lines.append("")

    # === lv_font_t ===
    line_height = size
    base_line = 0

    lines.append("/*-----------------------")
    lines.append(" *  Public font")
    lines.append(" *-----------------------*/")
    lines.append("")
    lines.append(f"const lv_font_t {font_name} = {{")
    lines.append("    .get_glyph_dsc = lv_font_get_glyph_dsc_fmt_txt,")
    lines.append("    .get_glyph_bitmap = lv_font_get_bitmap_fmt_txt,")
    lines.append(f"    .line_height = {line_height},")
    lines.append(f"    .base_line = {base_line},")
    lines.append("    .subpx = LV_FONT_SUBPX_NONE,")
    lines.append("    .underline_position = 0,")
    lines.append("    .underline_thickness = 0,")
    lines.append("    .dsc = &font_dsc,")
    lines.append("    .fallback = NULL,")
    lines.append("    .user_data = NULL")
    lines.append("};")
    lines.append("")
    lines.append(f"#endif /* {font_name.upper()} */")
    lines.append("")

    return "\n".join(lines)


# =============================================================================
# Main
# =============================================================================

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <output_dir> [--font-dir <dir>]")
        sys.exit(1)

    output_dir = sys.argv[1]
    font_dir = "/tmp/icon_fonts"

    if "--font-dir" in sys.argv:
        idx = sys.argv.index("--font-dir")
        if idx + 1 < len(sys.argv):
            font_dir = sys.argv[idx + 1]

    # Ensure FA TTF is available
    fa_ttf = ensure_fa_ttf(font_dir)

    # For label text, try to use a system monospace font, fall back to default
    label_font = fa_ttf  # FA itself won't have latin glyphs, need alternative
    # Try common paths for a monospace font
    mono_candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
        "/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf",
    ]
    label_ttf = None
    for candidate in mono_candidates:
        if os.path.exists(candidate):
            label_ttf = candidate
            break

    if label_ttf is None:
        print("  WARNING: No system monospace TTF found, labels will use default font")
        label_ttf = None  # Will use PIL default

    for sz in SIZES:
        font_name = f"asuro_icons_{sz}"
        print(f"  Generating {font_name} ({sz}px, {len(ICONS)} icons)...")

        icons_data = []
        for pua_cp, fa_cp, label, color in ICONS:
            img = render_glyph(fa_ttf, label_ttf, sz, fa_cp, label, color)
            bm = quantize_4bpp(img)
            icons_data.append((pua_cp, bm, sz, sz))

        c_source = generate_font_c(icons_data, sz, font_name)

        out_path = os.path.join(output_dir, f"{font_name}.c")
        with open(out_path, "w") as f:
            f.write(c_source)

        line_count = c_source.count("\n")
        print(f"  Wrote {out_path} ({line_count} lines)")

    print("  Icon font generation complete.")


if __name__ == "__main__":
    main()
