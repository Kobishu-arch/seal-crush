import json, struct, zlib

CW = CH = 32
CREAM, NOSE, BLUSH, WHITE = '#fff4e3', '#f2718f', '#ff95bb', '#ffffff'
IVORY, ORANGE, ORANGED, INEAR = '#fdf3dc', '#f5a23c', '#d9801f', '#e88ba6'
EYE = '#1b2436'

def ell(x, y, cx, cy, rx, ry):
    a = (x + 0.5 - cx) / rx
    b = (y + 0.5 - cy) / ry
    return a * a + b * b <= 1.0

def tones(k, b, l, h, d, D):
    return dict(k=k, b=b, l=l, h=h, d=d, D=D)

SPECIES = [
  dict(name='seal', c=tones('#17395c','#4fa8dd','#7fcbee','#bde5fb','#3684b8','#215878'),
       flip=(5.6,24.2,4.2,2.8), muzzle=(15.5,20.2,5.3,4.0), nose=(14,17),
       smile=True, whisk=True, blush=True, eyes=(7,11,20,11)),
  dict(name='penguin', c=tones('#141c2e','#38456b','#4d5c88','#7686b5','#27314f','#171f36'),
       flip=(4.4,20.5,3.3,5.2), belly=(15.5,19.8,6.6,7.6,WHITE), beak=(13,17),
       blush=True, feet=True, eyes=(8,11,19,11)),
  dict(name='otter', c=tones('#4a2614','#b3703a','#cf8d52','#e8b985','#8c5228','#5e3518'),
       flip=(5.6,24.4,4.0,2.8), ears=(7.6,5.6,3.0), muzzle=(15.5,20.4,5.6,3.8),
       nose=(14,17), smile=True, whisk=True, blush=True, eyes=(7,11,20,11)),
  dict(name='walrus', c=tones('#3b2a52','#9b7bb8','#b99ad1','#d9c6e8','#7a5c96','#543d6e'),
       flip=(5.6,24.8,4.2,2.6), muzzle=(15.5,20.8,6.0,4.2), nose=(14,17),
       tusks=True, whisk=True, blush=True, eyes=(7,11,20,11)),
  dict(name='narwhal', c=tones('#10474a','#3fbfa0','#6ed9bd','#a9eedb','#2d9b83','#1d6f5e'),
       flip=(5.4,23.6,3.8,2.5), belly=(15.5,22.5,6.6,5.2,'#d8f6ec'), horn=True, shift=2, r=12.3,
       muzzle=(15.5,20.6,4.6,3.4), nose=(14,18), smile=True, blush=True, eyes=(7,11,20,11)),
  dict(name='bear', c=tones('#6b5340','#f2e4cf','#fff6e8','#fffdf7','#d9c3a6','#b89a79'),
       flip=(6.0,25.0,4.0,2.9), ears=(7.2,5.2,3.2), muzzle=(15.5,20.6,5.2,3.8),
       nose=(14,17), smile=True, blush=True, eyes=(7,11,20,11)),
]

def render(sp, dy=0, blink=False, tone=None, sx=1.0, sy=1.0):
    C = dict(sp['c'])
    if tone: C.update(tone)
    G = [[None] * CW for _ in range(CH)]
    sh_ = sp.get('shift', 0)
    R = sp.get('r', 13.6)
    CX, CY = 15.5, 16.0 + sh_ + dy
    dy = dy + sh_   # ears, flippers and face follow the body
    RX, RY = R * sx, R * sy

    def body(x, y): return ell(x, y, CX, CY, RX, RY)
    ears = sp.get('ears')
    def ear(x, y):
        if not ears: return False
        ex, ey, er = ears
        ex2 = CX + (ex - CX) * sx
        ey2 = CY + (ey + dy - CY) * sy
        return (ell(x, y, ex2, ey2, er * sx, er * sy)
                or ell(x, y, 31 - ex2, ey2, er * sx, er * sy))
    def head(x, y): return body(x, y) or ear(x, y)
    fx, fy, frx, fry = sp['flip']
    fx2 = CX + (fx - CX) * sx
    fy2 = CY + (fy + dy - CY) * sy
    def flip(x, y):
        return (ell(x, y, fx2, fy2, frx * sx, fry * sy)
                or ell(x, y, 31 - fx2, fy2, frx * sx, fry * sy))

    def put(x, y, col):
        if 0 <= x < CW and 0 <= y < CH: G[y][x] = col

    for y in range(CH):
        for x in range(CW):
            if not head(x, y): continue
            diag = (x + 0.5 - CX) + (y + 0.5 - CY)
            col = C['b']
            if ell(x, y, 13.0, 12.5 + dy, 10.6 * sx, 10.0 * sy): col = C['l']
            elif diag > 6: col = C['d']
            rim = not ell(x, y, CX, CY, (R - 2.0) * sx, (R - 2.0) * sy)
            if rim and diag < -8.5: col = C['h']
            if rim and diag > 5.0:  col = C['d']
            if ear(x, y): col = C['d']
            put(x, y, col)
    # inner ear
    if ears:
        ex, ey, er = ears
        for y in range(CH):
            for x in range(CW):
                if ell(x, y, ex, ey + dy, er - 1.9, er - 1.9) or ell(x, y, 31 - ex, ey + dy, er - 1.9, er - 1.9):
                    put(x, y, INEAR)
    # belly
    if sp.get('belly'):
        bx, by, brx, bry, bc = sp['belly']
        for y in range(CH):
            for x in range(CW):
                if body(x, y) and ell(x, y, bx, by + dy, brx, bry): put(x, y, bc)
    # flippers
    for y in range(CH):
        for x in range(CW):
            if flip(x, y): put(x, y, C['D'])
    for y in range(CH):
        for x in range(CW):
            if flip(x, y) and body(x, y) and not flip(x, y - 1): put(x, y, C['k'])
    # muzzle
    if sp.get('muzzle'):
        mx, my, mrx, mry = sp['muzzle']
        for y in range(CH):
            for x in range(CW):
                if body(x, y) and ell(x, y, mx, my + dy, mrx, mry): put(x, y, CREAM)

    def stamp(rows, ox, oy, pal):
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                if ch != '.': put(ox + i, oy + j + dy, pal[ch])

    if sp.get('tusks'):
        tp = {'k': C['k'], 'i': '#ffffff', 'I': '#dfe6ef'}
        tusk = ['kiik', 'kiik', 'kiIk', 'kIik', '.kk.']
        stamp(tusk, 11, 23, tp)
        stamp(tusk, 17, 23, tp)
    if sp.get('horn'):
        hp = {'k': C['k'], 'i': IVORY, 'I': '#dcc9a4'}
        stamp(['..kk.', '.kiik', '.kiIk', '.kiIk', 'kiiIk', 'kiIk.', 'kiIk.', 'kIk..', 'kk...'],
              10, -1, hp)
    if sp.get('feet'):
        stamp(['.oo..oo.', 'oooooooo', '.OO..OO.'], 12, 27, {'o': ORANGE, 'O': ORANGED})
    if sp.get('nose'):
        nx, ny = sp['nose']
        stamp(['.ss.', 'ssss', '.ss.'], nx, ny, {'s': NOSE})
    if sp.get('beak'):
        bx, by = sp['beak']
        stamp(['.ooo.', 'ooooo', '.OOO.'], bx, by, {'o': ORANGE, 'O': ORANGED})
    if sp.get('smile'):
        nx, ny = sp['nose']
        stamp(['k..k', '.kk.'], nx, ny + 3, {'k': C['k']})
    if sp.get('whisk'):
        for yy in (18, 20):
            stamp(['jjj'], 7, yy, {'j': C['k']})
            stamp(['jjj'], 22, yy, {'j': C['k']})
    if sp.get('blush'):
        stamp(['.pp.', 'pppp', '.pp.'], 4, 15, {'p': BLUSH})
        stamp(['.pp.', 'pppp', '.pp.'], 24, 15, {'p': BLUSH})

    ex1, ey1, ex2, ey2 = sp['eyes']
    if blink:
        for ex, ey in ((ex1, ey1), (ex2, ey2)):
            stamp(['eeeee'], ex, ey + 2, {'e': EYE})
    else:
        rows = ['.eee.', 'eWWee', 'eeeee', 'eeeee', '.eee.']
        for ex, ey in ((ex1, ey1), (ex2, ey2)):
            stamp(rows, ex, ey, {'e': EYE, 'W': WHITE})

    NB = [(-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)]
    edge = [(x, y) for y in range(CH) for x in range(CW) if G[y][x] is None
            and any(0 <= x+dx < CW and 0 <= y+dy2 < CH and G[y+dy2][x+dx] is not None
                    for dx, dy2 in NB)]
    for x, y in edge:
        G[y][x] = C['k']
    return G

def sheet(cells):
    W = CW * len(cells)
    S = [[None] * W for _ in range(CH)]
    for i, g in enumerate(cells):
        for y in range(CH):
            for x in range(CW):
                S[y][i * CW + x] = g[y][x]
    return S

def encode(grids):
    colors = sorted({c for g in grids for row in g for c in row if c})
    pool = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*+=?'
    assert len(colors) <= len(pool), len(colors)
    key = {c: pool[i] for i, c in enumerate(colors)}
    pal = {v: k for k, v in key.items()}
    out = [[''.join(key[c] if c else '.' for c in row) for row in g] for g in grids]
    return pal, out

def png(grid, path, S=6):
    H2, W2 = len(grid), len(grid[0])
    raw = b''
    for row in grid:
        line = b''
        for c in row:
            if c:
                h = c.lstrip('#')
                px = bytes((int(h[0:2],16), int(h[2:4],16), int(h[4:6],16), 255))
            else:
                px = b'\x00\x00\x00\x00'
            line += px * S
        raw += (b'\x00' + line) * S
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W2*S, H2*S, 8, 6, 0, 0, 0)) \
           + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    open(path, 'wb').write(data)

def grid(rows_of_cells):
    """Sprite-sheet grid: one list of cells per row, all cells 32x32."""
    cols = max(len(r) for r in rows_of_cells)
    W, H = CW * cols, CH * len(rows_of_cells)
    S = [[None] * W for _ in range(H)]
    for ry, row in enumerate(rows_of_cells):
        for cx, g in enumerate(row):
            for y in range(CH):
                for x in range(CW):
                    S[ry * CH + y][cx * CW + x] = g[y][x]
    return S


# --- special pieces -------------------------------------------------------

def band(g, c, horizontal, pos=14, thick=3):
    """Bright dark-edged stripe, painted only over body tones so it runs
    BEHIND the face instead of blindfolding the critter."""
    body = {c['b'], c['l'], c['h'], c['d'], c['D']}
    for i in range(-1, thick + 1):
        col = c['k'] if (i == -1 or i == thick) else '#ffffff'
        for t in range(CW):
            x, y = (t, pos + i) if horizontal else (pos + i, t)
            if 0 <= x < CW and 0 <= y < CH and g[y][x] in body:
                g[y][x] = col


def brackets(g, c):
    """Corner brackets marking a wrapped piece (uses the free cell corners)."""
    pat = ['wwwk', 'wwk.', 'wk..', 'k...']
    pal = {'w': '#ffffff', 'k': c['k']}
    for ox, oy, fx, fy in ((0, 0, 1, 1), (CW - 1, 0, -1, 1),
                           (0, CH - 1, 1, -1), (CW - 1, CH - 1, -1, -1)):
        for j, row in enumerate(pat):
            for i, ch in enumerate(row):
                if ch == '.':
                    continue
                x, y = ox + i * fx, oy + j * fy
                if 0 <= x < CW and 0 <= y < CH:
                    g[y][x] = pal[ch]


BOMB_TONE = dict(k='#070a14', b='#2b2f48', l='#3c4264', h='#565d84',
                 d='#1e2236', D='#13162a')
SPRINKLES = [(9, 8), (21, 9), (6, 18), (24, 19), (15, 5), (16, 25)]


def sprinkle(g):
    """Scatter one dot per species colour - the all-colours cue."""
    cols = [sp['c']['b'] for sp in SPECIES]
    for i, (x, y) in enumerate(SPRINKLES):
        for dy in range(2):
            for dx in range(2):
                X, Y = x + dx, y + dy
                if 0 <= X < CW and 0 <= Y < CH and g[Y][X] is not None:
                    g[Y][X] = cols[i % len(cols)]


# --- ui bits --------------------------------------------------------------

def star_grid(size=16, fill='#ffd977', edge='#9a6b12', dim='#2a3f57'):
    """Two cells: an earned star and an empty one. Drawn as a real polygon so
    it does not depend on a font having U+2605."""
    import math as _m
    pts = []
    for i in range(10):
        a = -_m.pi / 2 + i * _m.pi / 5
        r = (size * 0.46) if i % 2 == 0 else (size * 0.20)
        pts.append((size / 2 + _m.cos(a) * r, size / 2 + _m.sin(a) * r))

    def inside(px, py):
        hit = False
        j = len(pts) - 1
        for i in range(len(pts)):
            xi, yi = pts[i]
            xj, yj = pts[j]
            if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi:
                hit = not hit
            j = i
        return hit

    cells = []
    for earned in (True, False):
        g = [[None] * size for _ in range(size)]
        for y in range(size):
            for x in range(size):
                if inside(x + 0.5, y + 0.5):
                    g[y][x] = fill if earned else dim
        # outline the shape
        nb = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        ring = [(x, y) for y in range(size) for x in range(size) if g[y][x] is None
                and any(0 <= x + dx < size and 0 <= y + dy < size
                        and g[y + dy][x + dx] is not None for dx, dy in nb)]
        for x, y in ring:
            g[y][x] = edge
        cells.append(g)
    return cells
