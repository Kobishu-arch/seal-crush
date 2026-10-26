"""A 5x7 pixel font, emitted as a PNG atlas plus a BMFont .fnt descriptor so
Godot can import it as a real FontFile and use it on any Label or Button.
"""
import os, struct, sys, zlib

GW, GH = 5, 7          # glyph box
CELL_W, CELL_H = 6, 8  # atlas cell (1px gutter)
COLS = 16

G = {
 'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
 'B': ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
 'C': ['.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.'],
 'D': ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
 'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
 'F': ['#####', '#....', '#....', '####.', '#....', '#....', '#....'],
 'G': ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.###.'],
 'H': ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
 'I': ['.###.', '..#..', '..#..', '..#..', '..#..', '..#..', '.###.'],
 'J': ['..###', '...#.', '...#.', '...#.', '...#.', '#..#.', '.##..'],
 'K': ['#...#', '#..#.', '#.#..', '##...', '#.#..', '#..#.', '#...#'],
 'L': ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
 'M': ['#...#', '##.##', '#.#.#', '#...#', '#...#', '#...#', '#...#'],
 'N': ['#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#', '#...#'],
 'O': ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
 'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
 'Q': ['.###.', '#...#', '#...#', '#...#', '#.#.#', '#..#.', '.##.#'],
 'R': ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
 'S': ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
 'T': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
 'U': ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
 'V': ['#...#', '#...#', '#...#', '#...#', '#...#', '.#.#.', '..#..'],
 'W': ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '##.##', '#...#'],
 'X': ['#...#', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '#...#'],
 'Y': ['#...#', '#...#', '.#.#.', '..#..', '..#..', '..#..', '..#..'],
 'Z': ['#####', '....#', '...#.', '..#..', '.#...', '#....', '#####'],
 '0': ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
 '1': ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
 '2': ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
 '3': ['####.', '....#', '....#', '.###.', '....#', '....#', '####.'],
 '4': ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
 '5': ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
 '6': ['.###.', '#...#', '#....', '####.', '#...#', '#...#', '.###.'],
 '7': ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
 '8': ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
 '9': ['.###.', '#...#', '#...#', '.####', '....#', '#...#', '.###.'],
 '.': ['.....', '.....', '.....', '.....', '.....', '.##..', '.##..'],
 ',': ['.....', '.....', '.....', '.....', '.##..', '.##..', '.#...'],
 ':': ['.....', '.##..', '.##..', '.....', '.##..', '.##..', '.....'],
 '-': ['.....', '.....', '.....', '#####', '.....', '.....', '.....'],
 '/': ['....#', '....#', '...#.', '..#..', '.#...', '#....', '#....'],
 '!': ['..#..', '..#..', '..#..', '..#..', '..#..', '.....', '..#..'],
 '?': ['.###.', '#...#', '....#', '...#.', '..#..', '.....', '..#..'],
 '+': ['.....', '..#..', '..#..', '#####', '..#..', '..#..', '.....'],
 "'": ['..#..', '..#..', '.....', '.....', '.....', '.....', '.....'],
}

ORDER = [c for c in
         "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,:-/!?+'"]
ROWS = (len(ORDER) + COLS - 1) // COLS
AW, AH = COLS * CELL_W, ROWS * CELL_H


def narrow(rows):
    """Trim blank left/right columns so letters are proportionally spaced."""
    cols = [any(r[i] == '#' for r in rows) for i in range(GW)]
    if not any(cols):
        return 0, GW
    return cols.index(True), GW - cols[::-1].index(True)


def build(out_dir):
    pix = [[0 for _ in range(AW)] for _ in range(AH)]
    chars = []
    for i, ch in enumerate(ORDER):
        gx, gy = (i % COLS) * CELL_W, (i // COLS) * CELL_H
        rows = G[ch]
        lo, hi = narrow(rows)
        wid = hi - lo
        for y in range(GH):
            for x in range(lo, hi):
                if rows[y][x] == '#':
                    pix[gy + y][gx + (x - lo)] = 1
        chars.append((ord(ch), gx, gy, wid, GH, wid + 1))
    # alias a-z onto the uppercase glyphs: the font is caps-only by design, and
    # without this every lowercase string in the UI renders as tofu boxes
    for cid, gx, gy, wid, h, adv in list(chars):
        if 65 <= cid <= 90:
            chars.append((cid + 32, gx, gy, wid, h, adv))
    chars.append((32, 0, 0, 0, 0, 3))   # space

    raw = b''
    for y in range(AH):
        line = b''
        for x in range(AW):
            line += b'\xff\xff\xff\xff' if pix[y][x] else b'\x00\x00\x00\x00'
        raw += b'\x00' + line

    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', AW, AH, 8, 6, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    open(os.path.join(out_dir, 'pixelfont.png'), 'wb').write(png)

    lines = [
        'info face="SealPixel" size=%d bold=0 italic=0 charset="" unicode=1 '
        'stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1 outline=0' % GH,
        'common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0 '
        'alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0' % (GH + 2, GH, AW, AH),
        'page id=0 file="pixelfont.png"',
        'chars count=%d' % len(chars),
    ]
    for cid, x, y, w, h, adv in sorted(chars):
        lines.append('char id=%d x=%d y=%d width=%d height=%d xoffset=0 '
                     'yoffset=0 xadvance=%d page=0 chnl=15' % (cid, x, y, w, h, adv))
    open(os.path.join(out_dir, 'pixelfont.fnt'), 'w').write('\n'.join(lines) + '\n')
    print('pixelfont.png %dx%d, %d glyphs' % (AW, AH, len(chars)))


build(sys.argv[1] if len(sys.argv) > 1 else '.')
