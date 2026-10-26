import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import critters as C

CW = CH = 32
CXC, CYC = 15.5, 16.0

def blank():
    return [[None] * CW for _ in range(CH)]

def put(g, x, y, col):
    if 0 <= x < CW and 0 <= y < CH:
        g[y][x] = col

def recolor(g, col):
    return [[col if c else None for c in row] for row in g]

def ring(g, r, col, w=0.7, cx=CXC, cy=CYC):
    for y in range(CH):
        for x in range(CW):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if abs(d - r) <= w:
                put(g, x, y, col)

def shards(g, r, size, col, n=8, phase=0.0, cx=CXC, cy=CYC):
    for i in range(n):
        a = phase + i * 2 * math.pi / n
        px = int(round(cx + math.cos(a) * r - size / 2))
        py = int(round(cy + math.sin(a) * r - size / 2))
        for dy in range(size):
            for dx in range(size):
                put(g, px + dx, py + dy, col)

def lum(h):
    h = h.lstrip('#')
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def vis(c, prefer, fallback, limit=0.80):
    """Keep particles readable: fall back to a darker tone for pale species."""
    return c[prefer] if lum(c[prefer]) <= limit else c[fallback]

def flash(g, c):
    """Blow the interior out to the lightest tone, keep the dark outline."""
    return [[(c['h'] if col != c['k'] else col) if col else None for col in row] for row in g]

def pop_frames(sp):
    """7-frame match/pop: scrunch, stretch, squash, flash, burst, spread, fade."""
    c = sp['c']
    rc, sc, fc = vis(c, 'l', 'd'), vis(c, 'b', 'D'), vis(c, 'd', 'k')
    out = []

    # 1 scrunch - eyes squeezed shut
    out.append((C.render(sp, blink=True), 0.06))
    # 2 anticipation - stretch tall
    out.append((C.render(sp, blink=True, dy=-1, sx=0.90, sy=1.14), 0.05))
    # 3 squash wide
    out.append((C.render(sp, blink=True, dy=1, sx=1.20, sy=0.84), 0.05))
    # 4 flash - interior blows out, shockwave starts
    out.append((flash(C.render(sp, blink=True, dy=1, sx=1.22, sy=0.88), c), 0.05))
    # 5 burst - body gone, ring plus eight shards
    g = blank()
    ring(g, 9.5, rc, 0.8)
    shards(g, 12.5, 2, sc, 8, math.pi / 8)
    out.append((g, 0.06))
    # 6 spread
    g = blank()
    ring(g, 13.6, rc, 0.5)
    shards(g, 8.0, 1, fc, 4, math.pi / 8)
    shards(g, 14.6, 1, sc, 8, 0.0)
    out.append((g, 0.06))
    # 7 fade - last few sparks
    g = blank()
    shards(g, 12.0, 1, fc, 4, math.pi / 4)
    out.append((g, 0.05))
    # 8 empty - piece is gone
    out.append((blank(), 0.08))
    return out

def strip(frames):
    """Lay frames out side by side for inspection."""
    W = CW * len(frames)
    S = [[None] * W for _ in range(CH)]
    for i, (g, _) in enumerate(frames):
        for y in range(CH):
            for x in range(CW):
                S[y][i * CW + x] = g[y][x]
    return S
