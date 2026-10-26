import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import critters as C

OUT = sys.argv[1] if len(sys.argv) > 1 else '.'
POSES = [(0, False), (-1, False), (0, False), (0, True)]   # same idle beat

# specials: 12 columns (stripe_h x4, stripe_v x4, wrapped x4), one row per species
rows = []
for sp in C.SPECIES:
    row = []
    for kind in ('h', 'v', 'w'):
        for dy, blink in POSES:
            g = C.render(sp, dy=dy, blink=blink)
            if kind == 'h':
                C.band(g, sp["c"], True, 13, 3)
            elif kind == 'v':
                C.band(g, sp["c"], False, 14, 3)
            else:
                C.brackets(g, sp['c'])
            row.append(g)
    rows.append(row)
sheet = C.grid(rows)
C.png(sheet, os.path.join(OUT, 'critters_special_sheet.png'), 1)
C.png(sheet, os.path.join(OUT, 'critters_special_sheet@4x.png'), 4)
print('special sheet', len(sheet[0]), 'x', len(sheet))

# colour bomb: one row of 4 idle frames, species-independent
bomb = []
for dy, blink in POSES:
    g = C.render(C.SPECIES[0], dy=dy, blink=blink, tone=C.BOMB_TONE)
    C.sprinkle(g)
    bomb.append(g)
bsheet = C.grid([bomb])
C.png(bsheet, os.path.join(OUT, 'bomb_sheet.png'), 1)
C.png(bsheet, os.path.join(OUT, 'bomb_sheet@4x.png'), 4)
print('bomb sheet', len(bsheet[0]), 'x', len(bsheet))
