"""Generates the two scenes: bg_menu.png (wide vista) and bg_play.png (the
board as a pool of water cut into an ice field).

Base resolution 320x380, shown at 2x. The board covers base x32-288, y80-336,
so the play scene carves water out of the ice there instead of the game
dropping a panel on top of a picture.
"""
import math, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bgkit as K
from bgkit import rgb, blend, lerp, W, H

OUT = sys.argv[1] if len(sys.argv) > 1 else '.'

BOARD = (32, 80, 288, 336)        # base-pixel board rect
MARGIN = 5                        # water overhangs the board, so the wobbly
                                  # ice edge never reaches a playable cell

AURORA = [(rgb('#4fd1a5'), 20.0, 9.0, 46.0, 0.30, 9),
          (rgb('#8ff0cf'), 28.0, 6.0, 31.0, 0.22, 9),
          (rgb('#a884e8'), 38.0, 7.0, 67.0, 0.18, 9)]

BIG = [(-28, 0), (-21, 19), (-9, 27), (2, 23), (12, 31), (22, 12), (28, 0)]
MID = [(-18, 0), (-13, 13), (-4, 18), (6, 14), (14, 8), (18, 0)]
LOW = [(-12, 0), (-7, 7), (0, 10), (7, 6), (12, 0)]
FLOE = [(-14, 0), (-9, 3), (2, 4), (10, 3), (14, 0)]
SHELF = [(-152, 0), (-138, 6), (-92, 8), (-20, 9), (44, 8), (112, 7), (138, 4), (152, 0)]


# --- menu: the wide vista -------------------------------------------------

def compose_menu():
    random.seed(11)
    K.reset()
    K.vgrad(0, 95, rgb('#101631'), rgb('#38507d'))
    K.vgrad(95, H, rgb('#38507d'), rgb('#38507d'))
    K.aurora(AURORA)
    K.stars(90, 0, 58, big=7)
    K.moon(250, 22)
    K.ridge(lambda x: 56 + 8 * math.sin(x / 47.0) + 4 * math.sin(x / 15.0 + 1.0),
            96, rgb('#3c4f74'), rgb('#cfe4f5'))
    K.ridge(lambda x: 70 + 6 * math.sin(x / 31.0 + 2.2) + 3 * math.sin(x / 11.0),
            96, rgb('#2b3a5c'), rgb('#aecbe4'))
    K.vgrad(88, H, rgb('#2f5679'), rgb('#1b3550'))
    for x in range(W):
        for k in range(4):
            blend(x, 88 + k, rgb('#8fc0dd'), 0.45 - k * 0.11)
    for y in range(90, 170):
        for x in range(W):
            if (y + int(3 * math.sin(x / 13.0))) % 5 == 0:
                blend(x, y, rgb('#6fe0b8'), 0.07)
    K.berg(160, 150, SHELF)
    # mid-water floes are kept out of base x105-215, the menu's text column -
    # a pale berg behind "QUIT" swallowed the lettering
    for args in [(60, 152, BIG, 1.0), (250, 141, MID, 1.15), (152, 126, LOW, 1.0),
                 (303, 170, MID, 1.0), (16, 184, LOW, 1.2), (284, 196, FLOE, 1.0),
                 (52, 214, FLOE, 1.3), (292, 232, FLOE, 1.0), (30, 252, FLOE, 1.1),
                 (268, 266, FLOE, 1.2)]:
        K.berg(args[0], args[1], args[2], args[3])
    K.snow_bank(lambda x: 276 + 8 * math.sin(x / 36.0) + 4 * math.sin(x / 13.0 + 2.0))
    K.snow_bank(lambda x: 330 + 7 * math.sin(x / 24.0 + 1.3), depth=40.0)
    K.igloo(62, 344)
    K.lantern(112, 330)
    K.lantern(228, 322)
    K.penguin(244, 318)
    K.penguin(262, 324, 10)
    K.penguin(186, 312, 9)
    K.specks(150, 88, H)
    K.write_png(os.path.join(OUT, 'bg_menu.png'))


# --- play: a pool cut into the ice ---------------------------------------

def water_edges():
    """Per-row and per-column water boundaries, wobbling only inside MARGIN."""
    x0, y0, x1, y1 = BOARD
    left, right = {}, {}
    for y in range(y0 - MARGIN, y1 + MARGIN):
        left[y] = x0 - MARGIN + int(round(MARGIN * (0.5 + 0.5 * math.sin(y / 9.0))))
        right[y] = x1 + MARGIN - int(round(MARGIN * (0.5 + 0.5 * math.sin(y / 7.0 + 2.0))))
    top, bot = {}, {}
    for x in range(x0 - MARGIN, x1 + MARGIN):
        top[x] = y0 - MARGIN + int(round(MARGIN * (0.5 + 0.5 * math.sin(x / 11.0 + 1.0))))
        bot[x] = y1 + MARGIN - int(round(MARGIN * (0.5 + 0.5 * math.sin(x / 8.0))))
    return left, right, top, bot


def compose_play():
    random.seed(29)
    K.reset()
    x0, y0, x1, y1 = BOARD

    # sky, kept shallow so the shore and pool edge fit above the board
    K.vgrad(0, 36, rgb('#101631'), rgb('#27365e'))
    K.aurora([(rgb('#4fd1a5'), 13.0, 6.0, 44.0, 0.30, 7),
              (rgb('#8ff0cf'), 19.0, 5.0, 29.0, 0.20, 6),
              (rgb('#a884e8'), 25.0, 5.0, 61.0, 0.16, 6)])
    K.stars(55, 0, 30, big=4)
    K.moon(264, 14, r=5, halo=14)
    K.ridge(lambda x: 30 + 6 * math.sin(x / 41.0) + 3 * math.sin(x / 14.0 + 1.0),
            54, rgb('#3c4f74'), rgb('#cfe4f5'))
    K.ridge(lambda x: 41 + 4 * math.sin(x / 27.0 + 2.2) + 2 * math.sin(x / 10.0),
            54, rgb('#2b3a5c'), rgb('#aecbe4'))

    # the ice field everything else is cut from - kept bluer than white so the
    # dark pool stays the focus rather than the frame
    K.vgrad(50, H, rgb('#cadff1'), rgb('#9dc0dd'))
    for x in range(W):
        top = int(50 + 3 * math.sin(x / 19.0) + 2 * math.sin(x / 7.0 + 1.0))
        for y in range(top, min(top + 3, H)):
            blend(x, y, rgb('#f2fbff'), 0.9 - (y - top) * 0.25)
    # drift mounds, so the field reads as snow rather than a slab
    for _ in range(40):
        mx, my = random.randrange(W), random.randrange(54, H)
        rw, rh = random.randrange(10, 26), random.randrange(3, 7)
        for dy in range(-rh, rh + 1):
            for dx in range(-rw, rw + 1):
                d = math.hypot(dx / float(rw), dy / float(rh))
                if d <= 1.0:
                    up = rgb('#eaf6ff') if dy < 0 else rgb('#a9c8e0')
                    blend(mx + dx, my + dy, up, 0.30 * (1.0 - d))
    # cracks
    for _ in range(34):
        cx, cy = random.randrange(W), random.randrange(52, H)
        ln = random.randrange(6, 20)
        ang = random.uniform(0, math.pi)
        for t in range(ln):
            blend(cx + math.cos(ang) * t, cy + math.sin(ang) * t, rgb('#8fb2cf'), 0.32)

    left, right, top, bot = water_edges()

    def in_water(x, y):
        if y in left:
            if not (left[y] <= x <= right[y]):
                return False
        if x in top:
            if not (top[x] <= y <= bot[x]):
                return False
        return (y0 - MARGIN <= y <= y1 + MARGIN) and (x0 - MARGIN <= x <= x1 + MARGIN)

    # water, deepening toward the middle
    for y in range(y0 - MARGIN, y1 + MARGIN + 1):
        for x in range(x0 - MARGIN, x1 + MARGIN + 1):
            if not in_water(x, y):
                continue
            t = (y - (y0 - MARGIN)) / float(y1 - y0 + 2 * MARGIN)
            blend(x, y, lerp(rgb('#2b5273'), rgb('#15293f'), t), 1.0)

    # bright ice lip where the field meets the water, plus a shadow in the water
    for y in range(y0 - MARGIN, y1 + MARGIN + 1):
        for xx, d in ((left.get(y, x0), 1), (right.get(y, x1), -1)):
            blend(xx - d, y, rgb('#f4fbff'), 0.95)
            blend(xx - d * 2, y, rgb('#cfe6f6'), 0.6)
            blend(xx + d, y, rgb('#0f2235'), 0.35)
    for x in range(x0 - MARGIN, x1 + MARGIN + 1):
        for yy, d in ((top.get(x, y0), 1), (bot.get(x, y1), -1)):
            blend(x, yy - d, rgb('#f4fbff'), 0.95)
            blend(x, yy - d * 2, rgb('#cfe6f6'), 0.6)
            blend(x, yy + d, rgb('#0f2235'), 0.4)

    # water surface: aurora reflection near the top, lazy ripples below
    for y in range(y0, y0 + 60):
        for x in range(x0, x1):
            if in_water(x, y) and (y + int(3 * math.sin(x / 13.0))) % 5 == 0:
                blend(x, y, rgb('#6fe0b8'), 0.06)
    for y in range(y0, y1):
        for x in range(x0, x1):
            if in_water(x, y) and (y + int(4 * math.sin(x / 17.0))) % 19 == 0:
                blend(x, y, rgb('#bfe4f7'), 0.05)

    # bergs sitting on the ice around the pool, a couple overhanging the lip
    def shadowed(cx, by, pts, sc):
        for dx in range(-int(16 * sc), int(16 * sc)):
            blend(cx + dx + 3, by + 1, rgb('#8aadc9'), 0.35)
            blend(cx + dx + 4, by + 2, rgb('#8aadc9'), 0.18)
        K.berg(cx, by, pts, sc, reflect=False)

    shadowed(14, 76, MID, 0.75)
    shadowed(303, 72, MID, 0.85)
    shadowed(84, 64, MID, 0.85)
    shadowed(214, 61, LOW, 1.0)
    shadowed(13, 212, MID, 0.7)
    shadowed(307, 258, MID, 0.75)
    shadowed(15, 332, LOW, 0.8)
    shadowed(62, 372, MID, 0.9)
    shadowed(196, 376, LOW, 1.1)

    # a cosy corner on the near bank
    K.igloo(272, 378, r=16)
    K.lantern(36, 368, reach=7)
    K.penguin(62, 370, 9)
    K.penguin(78, 374, 8)
    K.specks(70, 52, H, 0.06, 0.18)
    K.write_png(os.path.join(OUT, 'bg_play.png'))


compose_menu()
compose_play()
K.write_fade(os.path.join(OUT, 'ui_fade_top.png'), 80, 0.80, 0.0)
K.write_fade(os.path.join(OUT, 'ui_fade_bot.png'), 44, 0.0, 0.84)
