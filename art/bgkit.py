"""Shared drawing helpers for the scene generators."""
import math, os, random, struct, zlib

W, H = 320, 380
px = [[(0.0, 0.0, 0.0) for _ in range(W)] for _ in range(H)]


def reset(col=(0.06, 0.08, 0.18)):
    for y in range(H):
        for x in range(W):
            px[y][x] = col


def rgb(h):
    h = h.lstrip('#')
    return (int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0)


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def blend(x, y, col, a=1.0):
    if a <= 0 or x < 0 or x >= W or y < 0 or y >= H:
        return
    o = px[int(y)][int(x)]
    px[int(y)][int(x)] = (o[0] + (col[0] - o[0]) * a,
                          o[1] + (col[1] - o[1]) * a,
                          o[2] + (col[2] - o[2]) * a)


def vgrad(y0, y1, top, bot, x0=0, x1=W):
    for y in range(max(y0, 0), min(y1, H)):
        c = lerp(top, bot, (y - y0) / max(y1 - y0 - 1, 1))
        for x in range(max(x0, 0), min(x1, W)):
            blend(x, y, c, 1.0)


def stars(n, y0, y1, big=0):
    for _ in range(n):
        blend(random.randrange(W), random.randrange(y0, y1), rgb('#ffffff'),
              random.uniform(0.25, 0.95))
    for _ in range(big):
        x, y = random.randrange(8, W - 8), random.randrange(y0 + 2, y1 - 4)
        blend(x, y, rgb('#ffffff'), 1.0)
        for d in (-1, 1):
            blend(x + d, y, rgb('#cfe3ff'), 0.5)
            blend(x, y + d, rgb('#cfe3ff'), 0.5)


def aurora(bands):
    for col, base, amp, period, peak, spread in bands:
        for x in range(W):
            cy = base + amp * math.sin(x / period) + 3.0 * math.sin(x / 11.0)
            for dy in range(-spread, spread + 1):
                fall = max(0.0, 1.0 - abs(dy) / float(spread)) ** 2
                blend(x, cy + dy, col, peak * fall)


def moon(mx, my, r=7, halo=20):
    for y in range(my - halo, my + halo + 1):
        for x in range(mx - halo, mx + halo + 1):
            d = math.hypot(x - mx, y - my)
            if d <= r:
                blend(x, y, rgb('#fff6d9'), 1.0)
            elif d <= halo:
                blend(x, y, rgb('#ffeeb8'), 0.22 * (1.0 - (d - r) / (halo - r)) ** 2)


def ridge(top_fn, bottom, body, cap, cap_h=3):
    for x in range(W):
        top = int(top_fn(x))
        for y in range(top, bottom):
            blend(x, y, body, 1.0)
        for k in range(cap_h):
            blend(x, top + k, cap, 0.95 - k * 0.22)


def berg(cx, water_y, pts, scale=1.0, reflect=True):
    """Angular flat-topped berg; pts are (dx, height above water)."""
    lit, mid, dark = rgb('#e6f4ff'), rgb('#b4d6ee'), rgb('#7aa8ca')
    xs = [cx + p[0] * scale for p in pts]
    hs = [p[1] * scale for p in pts]
    for x in range(int(xs[0]), int(xs[-1]) + 1):
        seg = 0
        while seg < len(xs) - 2 and x > xs[seg + 1]:
            seg += 1
        span = max(xs[seg + 1] - xs[seg], 0.001)
        t = (x - xs[seg]) / span
        h = hs[seg] + (hs[seg + 1] - hs[seg]) * t
        top = int(water_y - h)
        side = (x - cx) / max((xs[-1] - xs[0]) * 0.5, 0.001)
        col = lit if side < -0.2 else (mid if side < 0.4 else dark)
        for y in range(top, water_y + 1):
            blend(x, y, col, 1.0)
        blend(x, top, rgb('#f7fdff'), 0.85)
    if reflect:
        for x in range(int(xs[0]), int(xs[-1]) + 1):
            blend(x, water_y + 1, rgb('#9fd0ea'), 0.65)
            for k in range(2, 7):
                blend(x, water_y + k, rgb('#bfe2f5'), 0.16 - k * 0.02)


def igloo(cx, base_y, r=22):
    for y in range(base_y - r, base_y + 1):
        for x in range(cx - r, cx + r + 1):
            d = math.hypot((x - cx) / r, (y - base_y) / r)
            if d <= 1.0:
                shade = rgb('#fbfdff') if (x - cx) < -r * 0.15 else rgb('#d2e4f3')
                if d > 0.92:
                    shade = rgb('#aecae0')
                blend(x, y, shade, 1.0)
    for k in range(1, 4):
        yy = base_y - int(r * k / 4.0)
        for x in range(cx - r, cx + r + 1):
            if math.hypot((x - cx) / r, (yy - base_y) / r) <= 0.97:
                blend(x, yy, rgb('#a9c5dc'), 0.5)
    for y in range(base_y - 11, base_y + 1):
        for x in range(cx - 6, cx + 7):
            if math.hypot((x - cx) / 6.0, (y - base_y) / 11.0) <= 1.0:
                blend(x, y, rgb('#20304a'), 1.0)
    for y in range(base_y - 8, base_y + 1):
        for x in range(cx - 4, cx + 5):
            if math.hypot((x - cx) / 4.0, (y - base_y) / 8.0) <= 1.0:
                blend(x, y, rgb('#ffd79a'), 0.92)
    for y in range(base_y - 6, base_y + 12):
        for x in range(cx - 22, cx + 23):
            f = max(0.0, 1.0 - math.hypot((x - cx) / 22.0, (y - base_y - 3) / 11.0))
            blend(x, y, rgb('#ffcf8a'), 0.34 * f * f)


def lantern(x, y, reach=6):
    blend(x, y, rgb('#6b4a2a'), 1.0)
    blend(x, y + 1, rgb('#6b4a2a'), 1.0)
    blend(x, y - 1, rgb('#ffd79a'), 1.0)
    for dy in range(-reach, reach + 1):
        for dx in range(-reach, reach + 1):
            f = max(0.0, 1.0 - math.hypot(dx / float(reach), dy / float(reach)))
            blend(x + dx, y - 1 + dy, rgb('#ffcf8a'), 0.26 * f * f)


def penguin(x, y, h=12):
    body, belly = rgb('#1b2340'), rgb('#f2f9ff')
    for j in range(h):
        wmax = 4 if 1 < j < h - 1 else 3
        for i in range(-wmax, wmax + 1):
            blend(x + i, y + j, body, 1.0)
    for j in range(4, h - 1):
        for i in range(-2, 3):
            blend(x + i, y + j, belly, 1.0)
    for i in (-1, 0, 1):
        blend(x + i, y + h, rgb('#f0a24a'), 1.0)
    blend(x + 3, y + 2, rgb('#f0a24a'), 1.0)
    blend(x - 1, y + 2, rgb('#ffffff'), 0.9)


def snow_bank(top_fn, lit=None, mid=None, depth=70.0):
    lit = lit or rgb('#eef7ff')
    mid = mid or rgb('#c6ddf1')
    for x in range(W):
        top = int(top_fn(x))
        for y in range(top, H):
            blend(x, y, lerp(lit, mid, min((y - top) / depth, 1.0)), 1.0)
        blend(x, top, rgb('#ffffff'), 0.85)
        blend(x, top + 1, rgb('#dcecfa'), 0.5)


def specks(n, y0, y1, lo=0.08, hi=0.30):
    for _ in range(n):
        blend(random.randrange(W), random.randrange(y0, y1), rgb('#ffffff'),
              random.uniform(lo, hi))


def write_png(path, scale=1):
    raw = b''
    for y in range(H):
        line = b''
        for x in range(W):
            r, g, b = px[y][x]
            line += bytes((int(max(0.0, min(1.0, r)) * 255),
                           int(max(0.0, min(1.0, g)) * 255),
                           int(max(0.0, min(1.0, b)) * 255), 255)) * scale
        raw += (b'\x00' + line) * scale

    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    data = (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', W * scale, H * scale, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    open(path, 'wb').write(data)
    print('%-16s %dx%d  %d bytes' % (os.path.basename(path), W * scale, H * scale,
                                     os.path.getsize(path)))


def write_fade(path, h, a_top, a_bot, col='#0a1726', w=4, ease=2.0):
    """A vertical alpha ramp used as a soft UI vignette, so the HUD does not
    need a hard-edged scrim rectangle across the scene."""
    import struct as _s, zlib as _z
    r, g, b = rgb(col)
    raw = b''
    for y in range(h):
        t = y / float(max(h - 1, 1))
        a = a_top + (a_bot - a_top) * (t ** ease if a_bot < a_top else 1.0 - (1.0 - t) ** ease)
        px4 = bytes((int(r * 255), int(g * 255), int(b * 255), int(max(0.0, min(1.0, a)) * 255)))
        raw += b'\x00' + px4 * w

    def chunk(t_, d):
        c = t_ + d
        return _s.pack('>I', len(d)) + c + _s.pack('>I', _z.crc32(c) & 0xffffffff)

    data = (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', _s.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', _z.compress(raw, 9)) + chunk(b'IEND', b''))
    open(path, 'wb').write(data)
    print('%-16s %dx%d' % (os.path.basename(path), w, h))
