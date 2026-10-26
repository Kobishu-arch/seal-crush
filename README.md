# Seal Crush

Match-3 prototype in Godot 4.7 using the pixel-art critter sheets.

## Run

    godot4 --path . 

Click two neighbouring pieces to swap. A swap that makes no match reverts.
`R` retries the level, `SPACE` advances after a win, `ESC` steps back a screen,
`M` mutes, `F12` writes a screenshot to `user://shot.png`.

## Look

### Scenes

`art/mkbg.py` draws two 320x380 antarctic scenes with no dependencies, shown at
2x so their pixels match the 2x sprites. Shared primitives live in
`art/bgkit.py` (gradients, aurora, bergs, igloo, penguins, snow banks).

- **`bg_menu.png`** - a wide vista: aurora sky, two snow-capped ridges, a
  frozen sea of faceted bergs, a wide ice shelf the menu critters stand on, and
  a near bank with a glowing igloo.
- **`bg_map.png`** - the level map's own scene: a lane of water meandering down
  between ice banks, with bergs on the banks and floes adrift. A vertical trail
  wants a channel, not the board's square pool, which select had been borrowing.
- **`bg_play.png`** - the board as a **pool of water cut into an ice field**.
  The water overhangs the board rect by 5px so its deliberately irregular edge
  never reaches a playable cell; a bright ice lip rims it with a shadow cast
  into the pool; bergs sit on the surrounding ice, some overhanging the lip.

The board is the water - there is no panel over a picture. Cell tints are down
to alpha 0.025/0.055, just enough structure to read as a grid.

`bg_play.png` is also drawn a second time as `bg_front`, showing its top slice
above the pieces, which is what hides pieces falling in from above the board. A
test asserts that slice height matches `ORIGIN.y`.

### Free reshuffle

`S` rearranges the board once per level. It costs no move and leaves score,
goal progress and the move counter untouched - it runs the same routine the
deadlock rescue uses, so the result is still match-free and still has a legal
move. If no valid arrangement is found the shuffle is refunded rather than
silently consumed. The remaining count shows in the key line.

### Legend

The play screen's help was one run-on line of text, which did not scan. It is
now a legend of **icon + label pairs** built from the real piece art - striped,
wrapped, bomb - with the key bindings on a second line beneath.

The labels name the *match*, not the piece: "MATCH 4", "L OR T SHAPE",
"MATCH 5". The middle one is spelled out because the wrapped piece is the only
special defined by shape rather than run length - a horizontal and a vertical
run sharing a piece - and a two-word label did not convey that.

Both the legend and the level-select rows briefly had boxes behind them for
contrast. They were dropped: the legend sits on the bottom vignette, and the
select screen now uses `bg_play.png`, whose dark pool gives the list uniform
contrast and frames it with the ice edge. Boxes for contrast are a sign the
background is wrong underneath.

Icons stay at 1x. A 1.5x pass made the markings clearer but any fractional
scale breaks the pixel grid, doubling some rows of pixels and not others.

### UI vignettes

The HUD needs contrast over the scene. A flat `ColorRect` scrim gave it, but
left a hard seam straight across the artwork at the board's top edge. Two
generated alpha ramps (`ui_fade_top.png`, `ui_fade_bot.png`) replace it; each
reaches zero alpha exactly where the board begins or ends, so there is no edge
anywhere. The bottom band also darkens the near snow, which is why the play
hint is light text rather than dark.

### Type

`art/mkfont.py` emits a 5x7 pixel font as a PNG atlas plus a BMFont `.fnt`
descriptor, which Godot imports as a real `FontFile`. Everything uses it, at
multiples of the 7px base (14/21/28/35/42) so it stays crisp. Menu entries are
bare text with hover colour and flanking diamonds - no boxes.

Four things the screenshots caught here:

1. **Lowercase rendered as tofu.** The font is caps-only by design, and the
   HUD is full of lowercase ("score", "moves", "clear the jelly"). `a-z` are
   now aliased onto the uppercase glyph boxes, and a test walks all 26 codes.
2. **Godot ignores `outline_size` for bitmap fonts** - it builds outlines from
   vector glyph data. Thin pixel strokes vanished against the snow caps, so
   titles get an outline the manual way, from eight offset copies behind.
3. **The pixel font is wider per character.** The play hint overflowed the
   screen and the level-list text collided with the stars. The hint is centred
   and shorter; the rows were re-laid out with short goal labels (`16x SEAL`,
   `28 ICE`).
4. **The ice field was too flat and bright**, competing with the board. It is
   bluer now, with drift mounds, cracks and contact shadows under the bergs.
5. **A pale berg sat behind "QUIT"** and swallowed the lettering. Mid-water
   floes are now kept out of base x105-215, the menu's text column.
6. **The menu critters read as stickers** pasted on the ice. Each has a contact
   shadow and a slight cool tint now, which settles them into the scene.
7. **Foreground detail collided with the play hint.** The igloo, lantern and
   penguins were sitting directly behind the text; they moved below and to the
   side of the band the hint occupies.

## Screens

Three screens, toggled by node layer (`menu_layer`, `select_layer`,
`board_layer` + `hud_layer`) off a `state` variable:

- **Menu** - title over the aurora, the six critters idling on an ice shelf,
  PLAY / LEVELS / QUIT. PLAY opens the map scrolled to the level you are up
  to - the first unlocked one still unstarred, or the furthest unlocked level
  once they are all cleared. LEVELS opens the same map from the top.
- **Level select** - a scrolling map of ice floes with each level's move
  budget, goal summary and earned stars, laid over its own pool scene. A level
  unlocks once the one before it has at least one star *and* its chapter's star
  gate is paid.
- **Play** - the board. Clearing a level returns to the map rather than diving
  into the next one, so the stars just banked and the gate ahead are both in
  view; the result overlay carries LEVELS and REPLAY buttons, because `SPACE`
  and `ESC` are no use on the phones this build is shared with.

`ESC` steps back one screen and only quits from the menu. `M` mutes anywhere.

## Levels and goals

Levels are **generated from a curve**, not typed out. `LEVEL_COUNT` is the only
thing standing between 30 levels and 300.

`_level_spec(n)` derives level n from its index. Three dials move with n: the
goal type cycles so no chapter repeats itself, the move budget tapers across a
chapter and resets at the next, and the magnitude is derived **from the move
budget**, not from n.

That last point is the one that matters. Deriving magnitude from n alone
produced a 4540-point target on a 14-move level - unreachable, since the
balance sweep fitted median score to roughly `75 * moves - 120`. Targets are
now `est_median * pressure`, where pressure climbs from 0.95 to about 1.25
across 30 levels. The hand-tuned levels sit near 0.95-1.0, so the generated
curve continues from them rather than restarting below.

Jelly layouts are generated too, from shape functions (block, octagon, diamond,
cross, ring) rather than hand-drawn strings. **The extent is fitted to the
budget**, because shapes vary hugely in area at the same extent - a block at
2.75 is 36 cells where a cross is 12 - so the extent whose cell count lands
closest to what the budget can clear is chosen. A first pass that only capped
from above gave 12-cell jelly levels on 20 moves, which is trivial.

`_build_levels()` applies **hand-authored overrides** last, so they always win.
Levels 1-6 are pinned: they were balanced against measured medians and have
been played, and they double as the worked example of how to write an override.

    godot4 --headless --path . -- levels     # print the whole curve

One known characteristic: absolute targets **sawtooth** rather than climbing
monotonically, because they track the move budget, which falls through a
chapter and resets. Difficulty still climbs, via pressure - a lower target on a
tighter budget is harder - but the numbers on the map do not read as a straight
line. Smoothing it would mean a budget that only ever shrinks.

### What the sweep found

`-- balance` samples every fourth level, 20 trials each, and reports how often
random play **clears** the goal - the figure that matters, since a rate near
zero means unreachable and near one means trivial.

    godot4 --headless --path . -- balance

Two things it caught:

**Level 1 cleared 20 times out of 20.** Its 1000-point target was set when
reaching one *ended* the level - it took a human three attempts under those
rules. Score levels now play the full budget, so 22 moves reach 1000 almost
regardless. Raising the pass mark is part of that rule change, not a separate
decision; the pinned score targets went to 1250 and 1500.

**The median model was wrong at high budgets.** Measured against the generated
levels, median score fits `105 * moves - 525`; the earlier `75 * moves - 120`
came from a different rule set and undershot by ~250 points at 22 moves. After
refitting, score-level clear rates fell from 40-80% into 30-40%.

Clear rates now run roughly: 90% at level 1, then 30-55%, with jelly at 10-15%.
Jelly reads low because random play is a far weaker proxy there - it never aims
at specific cells - so a human clears those far more often than the number
suggests.

**Still open:** collect levels clear at 40-65% against score levels' 30-40%,
consistently across samples. That gap is larger than the ~11pp standard error
at 20 trials, so the collect counts are probably a little soft. It is not
adjusted here, because the right correction depends on how much a human
outperforms random on *collect* specifically, and that wants playtesting rather
than more proxy runs.

### Board shapes

Every third level narrows the board: cells can be **blocked**, giving shapes
rather than always an 8x8 rectangle. Blocked cells hold no piece, never match,
are not clickable, and are drawn as slabs of ice sitting in the pool.

**Open cells must be contiguous within each column.** That invariant is what
keeps falling straight down - a hole in the middle of a column would split it
into regions with no way to refill the lower one, which is why real match-3
games route pieces diagonally instead. Avoiding that routing is why this
restriction exists, and `_build_blocked()` *enforces* it: a layout that splits
any column is rejected and the board falls back to full, rather than silently
producing a region that can never refill. A ring is the obvious shape this
rules out, and there is a test feeding exactly that.

Two shapes so far, both provably contiguous:

- **corners** - `dx + dy <= extent`; 6.0 shaves the corners (60 of 64 open),
  5.0 gives a chamfered square (52), 4.0 a diamond (40). Tightens by chapter.
- **jagged** - steps cut from the *top* of each column only, which cannot break
  contiguity whatever the pattern (56 of 64).

Six checks cover it, the load-bearing one being `shape_collapse_refills`:
it clears the bottom of every column, runs gravity, then asserts every open
cell refilled and nothing came to rest in a hole.

Goal kinds:Goal kinds:

- **score** - reach a score. The original behaviour.
- **collect** - clear N pieces of one species. Counted in `_resolve` just
  before the cells are popped, while `grid` still holds their species.
- **jelly** - clear every jelly layer. Jelly is a board layer (`jelly[r][c]`,
  0-2 layers), laid out per level as eight strings: `.` none, `1` one layer,
  `2` two. Clearing a cell eats one layer.

Jelly belongs to the **cell, not the piece**, so `_collapse` must never carry it
with a falling piece - there is a test pinning that down.

It is drawn twice: a faint tint in the board's own `_draw` (under the pieces,
which only shows at the cell edges) and a `Polygon2D` wash in `jelly_layer`
above the pieces, which is what actually makes it readable. That layer is
deliberately *not* made of `ColorRect`s - a Control sitting over the board
swallows the clicks meant for it, and a test asserts the layer holds no
Controls.

Winning always banks at least one star, so a level cleared on a thin score is
still a clear.

### Star gates

Stars are the currency of progression, not just a score. A ridge of ice sits on
the map at every chapter boundary, captioned with its toll; crossing it needs
`CHAPTER_GATE` (1.3) stars per level in the chapters behind it - 13 to enter
chapter 2, 26 for chapter 3. Below the toll the ridge stands and the levels
past it stay grey; once paid it sinks away and the caption dims to the chapter
name.

That makes a 1-star clear worth replaying for a 2-star, which multiplies the
content without adding any. The toll is deliberately well under what a chapter
can yield (13 of a possible 30), and `gate_always_payable` fails the build if a
gate ever asks for more stars than the levels before it can give - an unpayable
gate would end the game with no way forward.

### Boosters

Stars had nowhere to go but the gates, so the play HUD carries three, paid for
on use with no inventory to manage:

| Booster | Cost | Effect |
| --- | --- | --- |
| `SHUFFLE` | free once per level, then 1 | rearranges the board, keeping score |
| `+5 MOVES` | 3 | extends the move budget mid-level |
| `HAMMER` | 2 | arms, then the next tap clears that critter |

Two rules keep the economy honest. **Gates read the lifetime star total and
boosters a separate wallet** (`_total_stars()` vs `_stars_available()`, with
`spent_stars` persisted), so no amount of spending can re-lock a chapter you
have already opened - `spending_keeps_gates_open` asserts it. And the **hammer
charges when it lands, not when it arms**, so a misclick or a second press
costs nothing; a tap off the board or on a hole just cancels.

The bar is squeezed into the 88px between the board and the bottom of the
window - and the window is **760** tall, not 768, which is how the key line
came to be drawn half off the screen. `hud_inside_viewport` measures the
lowest row's ink against `get_viewport_rect()` rather than trusting a constant,
and `boost_bar_fits` measures each label against its own button, since the
first draft overflowed by a hair that no amount of reading the code revealed.

The bar also gave the free reshuffle a button. It had been advertised on the
key line as `S SHUFFLE` since it was written, but `KEY_S` was never bound to
anything, so no player could ever have used it - and on the iOS browsers this
build exists for, a keyboard hint is no use anyway. `S` works now too.

`_is_unlocked(i)` is the one place both rules live, so the map, PLAY and the
end-of-level advance cannot disagree about what is reachable: winning the last
level of a chapter without the stars for the next drops back to the map, where
the toll is on screen.

### Tuning

`-- balance` plays random legal moves with animation skipped (`fast = true`)
and `no_finish = true` so every move gets played, then reports the median score
and median goal progress per level:

    godot4 --path . --headless -- balance
    [balance] L2 moves=22  score med= 1870 (min  810 max  3980)   goal med= 22 (min   8 max  34) of 12
    [balance] L4 moves=20  score med= 1340 (min  710 max  2620)   goal med= 14 (min   7 max  16) of 16

Four things that sweep taught us, in order:

1. **Six trials was not enough.** Levels with *fewer* moves scored higher than
   levels with more - noise, with a 540-1890 spread. Thirty trials fixed it.
2. **Picking the first legal move biases play to the top-left** and rarely
   triggers specials. `_all_moves()` plus a random pick models naive play far
   better, and roughly doubled measured scores.
3. **Use the median, not the mean.** Scores are badly right-skewed - one
   runaway cascade hit 7890 against a ~2300 median and dragged the mean with
   it. On means the levels ordered wrongly; on medians they order correctly.
4. **Random play is a much weaker model for jelly than for score.** Clearing
   jelly is about aiming at specific cells, which random play never does, so
   the baseline understates human performance far more here. The jelly finale
   started at 44 layers and random play never cleared it even at its best; at
   36 it still never did; it is 28 now, which random clears about half the time.
5. **Report raw progress, not clamped progress.** `_goal_done()` clamps a
   collect goal at its target, so the first sweep showed "12 of 12" and hid how
   far past it runs actually got. Reporting the raw count showed a median of
   **22** seals collected against a target of 12 - the level was trivial and the
   clamped figure could never have revealed it.

Even at thirty trials the medians carry roughly +-10% noise. Treat the ratios
as indicative - the difficulty curve is monotonic by construction (targets rise
while move budgets shrink), not by measurement.

The anchor is a real playtest: 20 moves at 1200 points took a human three
attempts, and that configuration's median is ~1380, so a score target at
roughly 0.85x the median is "challenging but fair".

## Specials

| Match | Piece | Effect |
|---|---|---|
| 4 in a row | striped (band behind the face) | clears that row |
| 4 in a column | striped (vertical band) | clears that column |
| L or T shape | wrapped (corner brackets) | 3x3 blast |
| 5+ in a line | colour bomb (dark, sprinkled) | clears every piece of one species |

The new piece appears at the swapped cell and survives its own match.
Swapping a special sets it off whether or not the swap makes a match; a bomb
clears the species of whatever it was swapped with. Specials caught in another
special's blast chain-react.

Each cascade step raises the multiplier: cleared cells x 10 x combo step.

## Pair combos

Swapping two specials into each other combines them instead of just chaining:

| Pair | Effect |
|---|---|
| stripe + stripe | full cross through the swap cell |
| stripe + wrapped | three rows and three columns |
| stripe + bomb | every piece of the partner species fires as a stripe |
| wrapped + wrapped | 5x5 blast |
| wrapped + bomb | every piece of the partner species fires as a 3x3 |
| bomb + bomb | the whole board |

A bomb takes the colour of whatever it was combined with. Both source pieces
are consumed by the combo rather than firing individually, but other specials
caught in the blast still chain normally.

## No legal moves

After every swap the board is checked for a playable move: each adjacent pair
is swapped in the data model, tested for a match and swapped back. Any special
on the board counts as a move on its own, since swapping one always sets it off.

With no move left the plain pieces are shuffled in place, keeping the species
multiset. Placement is greedy in row-major order - it prefers a species that
does not complete a run with the cells already placed - because a purely random
reshuffle of a low-variety board almost always contains a ready-made match.
Falls back to a fresh board if 30 arrangements fail.

## Assets

Both sheets are 32x32 cells, one row per species
(seal, penguin, otter, walrus, narwhal, bear):

- `assets/critters_idle_sheet.png`    - 128x192, 4 idle frames across
- `assets/critters_pop_sheet.png`     - 256x192, 8 match/pop frames across
- `assets/critters_special_sheet.png` - 384x192, 12 across (stripe_h, stripe_v, wrapped x4)
- `assets/bomb_sheet.png`             - 128x32, 4 frames, species independent

Sources and the generators live in `art/` (carrying a `.gdignore` so Godot
skips them). Regenerate the special sheets with `python3 art/mkspecials.py art`.

`SpriteFrames` are built in code from `AtlasTexture` regions, with the
per-frame durations in `IDLE_DUR` / `POP_DUR` matching the Aseprite timings.

## Audio

All of it is synthesised by `art/mkaudio.py` (pure stdlib - `wave`, `math`,
`random`, no sample libraries), 16-bit mono at 22050 Hz into `assets/audio/`:

| File | When |
|---|---|
| `move.wav` | a swap starts |
| `pop.wav` | each cascade step, pitched up 9% per step (capped at 1.7x) |
| `invalid.wav` | a swap that makes no match reverts |
| `special.wav` | a special piece is created |
| `combo.wav` | two specials are combined |
| `shuffle.wav` | the board reshuffles |
| `music.wav` | 60s loop, 24 bars at 96 BPM in an A / B / A' shape |
| `voice_*.wav` | clicking a piece - one call per species |

Each animal has its own voice, pitched into its own register so they stay
distinguishable by ear alone:

| Species | Voice |
|---|---|
| seal | two descending pulse barks with a noise transient |
| penguin | two very high square chirps, rising |
| otter | five fast alternating blips - a chitter |
| walrus | low vibrato rumble, sliding down |
| narwhal | sine sweep up with a quieter octave shimmer |
| bear | low square huff with a noise edge |

One shared player handles voices, so clicking quickly cuts the previous call
off rather than stacking.

One pop plays per cascade *step*, not per cleared cell - twenty overlapping
pops is noise, and the rising pitch per step is what makes a cascade feel good.
`M` toggles the master bus mute.

### Levels

Every wav is normalised to a target **RMS**, not a target peak. Peak
normalisation makes a clicky transient and a sustained tone with the same peak
sound nothing alike - the first pass had a 7.6 dB spread in perceived loudness
across the effects. Levelling by energy and soft-clipping transients with
`tanh` holds them all inside 0.25 dB, which makes the `volume_db` values in
`SFX` an actual mix rather than a correction:

    move -22   invalid -20   shuffle -18   special -16
    pop  -15   voice   -15   combo   -13   music   -24

Frequent sounds sit well back; rewards come forward.

### Music

Triangle lead over a soft sine pad, no hats - a repeating tick is the first
thing that grates on a long loop. The form is A (8 bars) / B (8, sitting
higher and moving more) / A' (8, resolving home), over C, G/B, Am, Em, F, Dm
and G, with phrases of two bars that close on a rest so it breathes. The last
15 ms is tapered and the loop seam is sample-aligned at zero, so there is no
click on repeat. 2.6 MB as a wav; Godot imports it as QOA.

Note: Godot 4.7's wav importer does not carry `edit/loop_mode` onto the
resource when `compress/mode` is QOA, so the music loop is set on the stream
in `_build_audio()`, with a `finished` reconnect as a safety net.

## Play it

**https://kobishu-arch.github.io/seal-crush/**

Published by GitHub Actions on every push to `main`. Verified end to end: the
page loads, the menu renders, PLAY starts a level and the browser console is
clean.

### Progress and saves

Progress is per visitor, in their own browser. The game writes
`user://progress.cfg`, which Godot's web build maps to **IndexedDB** through
Emscripten's IDBFS (mounted at `/userfs`, flushed with `syncfs`). There is no
server, so nothing is shared, nothing syncs across devices, and nobody - the
author included - can read anyone else's progress.

Two consequences worth knowing:

- **iOS Safari evicts it.** Script-writable storage, IndexedDB included, is
  deleted after roughly 7 days without interaction. Casual iPhone visitors will
  lose their stars.
- **The store is per origin, not per path.** IDBFS keys its database on the
  mount point, so every Godot build on `kobishu-arch.github.io` shares one
  `/userfs` store. A second game writing `progress.cfg` would collide with this
  one.

## Web build

    godot4 --headless --path . --export-release "Web" build/index.html

Output is ~39 MB raw, **10.3 MB gzipped** (9.7 MB engine wasm, 0.6 MB pack).
`seal-crush-web.zip` has `index.html` at its root, which is what itch.io wants -
upload it and tick "This file will be played in the browser".

### Always-fresh builds

Pages serves everything with `cache-control: max-age=600` and that header
cannot be changed, while Godot exports fixed filenames with no content hash.
A returning visitor therefore sat on a stale build for up to ten minutes, and
reopening the tab re-read the cache rather than refetching.

Hashing the filenames would not have fixed it: `index.html` is cached too, so a
returning visitor reads old HTML pointing at the old names it already holds.
The build id has to be discovered at load time from a URL that cannot be
cached. `tools/cachebust.py` therefore:

- writes `version.txt` containing the commit SHA
- injects a script into `<head>` that reads `version.txt?t=<now>` - unique on
  every load, so never served from cache - and appends `?v=<id>` to the `.wasm`
  and `.pck` requests

The injected script is byte-identical in every build, so `index.html` being
cacheable is harmless: the logic inside it runs fresh each load. Verified by
serving a build locally and reading the network log:

    GET /version.txt?t=1793053441370        -> 200
    GET /index.wasm?v=local-test-ed78bd1    -> 200
    GET /index.pck?v=local-test-ed78bd1     -> 200

`index.js` still arrives via a plain script tag and stays cacheable; it only
changes when the engine version does.

The preset exports with `variant/thread_support=false`. The single-threaded
build needs no `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy`
headers, so it works on any static host, GitHub Pages included. The threaded
build is faster but only runs where those headers can be set (itch.io,
Netlify, Cloudflare Pages).

Verified in a browser, not just built: it loads, plays, and the console shows
only `single-threaded, no GDExtension support` with no errors.

### What the browser forced

- **`get_tree().quit()` does nothing in a tab.** The QUIT entry and ESC-to-quit
  are hidden behind `OS.has_feature("web")`, and the menu footer drops to
  "M MUTE" - otherwise the game looks broken.
- **Audio is blocked until a user gesture.** `music.play()` ran in `_ready()`,
  before any click, and simply never produced sound. It now starts on the first
  input via `_input()` - not `_unhandled_input()`, because buttons consume
  their own clicks and the menu's first click is always a button.
- **`window/stretch/aspect="keep"`** so the 640x760 viewport letterboxes
  instead of distorting.
- The renderer was already `gl_compatibility`, which is what web needs;
  Forward+ requires Vulkan and does not run in a browser.

On mobile the viewport is downscaled below 1x, which softens the pixel art -
a responsive layout would be the fix, not a setting. iOS Safari is the weakest
target for Godot web generally; test there early.

### Continuous deployment

`.github/workflows/pages.yml` exports and publishes to GitHub Pages on every
push to `main`. Steps: install Godot, fetch the web templates (cached between
runs), import resources, **run the self-test as a gate**, export, upload, deploy.

The gate works because `_selftest()` now ends with `get_tree().quit(0 if ok
else 1)`. Without that it always exited 0 and CI would have deployed over a
failing assertion - a gate that cannot fail is not a gate.

**Enable Pages by hand before the first run**: *Settings -> Pages -> Source:
GitHub Actions*. `configure-pages` fails outright when the repository has no
Pages site, and `enablement: true` did not create one either - the default
`GITHUB_TOKEN` could not, despite `pages: write`. Two runs died on this before
the setting was flipped manually. The repo must be public for Pages on a free
plan.

### Export templates

This install only had the Linux and Windows templates. Get the web ones with
the editor's *Manage Export Templates*, or pull just the web entries out of
the 1.28 GB pack with HTTP range requests - GitHub release assets send
`accept-ranges: bytes`, so reading the zip's central directory and fetching
only the `web_*` members costs **84 MB instead of 1,222 MB**.

With `thread_support=false` the exporter uses `web_nothreads_release.zip`.

### Level map

Level select is a **scrolling map**: a winding trail of ice floes down a water
channel, one per level, each showing its number, move budget, goal and earned
stars. Locked floes are dimmed.

Each marker is a real chunk of ice, not a disc - a 9-sided irregular polygon
with a dark rim, a mid-tone face and a lit facet offset up-left, shaded like
the bergs. The shape is seeded per level, so every floe differs but none of
them change between runs.

The numbers take the same treatment as every other heading: light fill with
the eight-copy dark outline. They were already the pixel font - a 4x zoom
confirmed it - but bare dark-on-pale read as a UI widget rather than game art. The path is generated -

    Vector2(320 + 150 * sin(i * 0.95), 54 + i * 118)

- so it extends to any level count, and the scroll content grows with it. This
replaced a fixed list of absolutely positioned rows that fitted exactly six
levels before colliding with the BACK button.

`map_holds_every_level` asserts the scroll content is tall enough for the last
node's full extent (disc, stars and info line), measured from the real nodes
rather than by redoing the layout arithmetic.

Spacing is 118px, not 100: at 100 each node's info line landed inside the next
floe's disc. The numbers invert to dark on the pale floe face - inherited light
button text was invisible there.

## Dev harnesses## Dev harnesses

    godot4 --path . --headless -- selftest   # 13 checks: classification, blasts, cascade
    godot4 --path . -- shot                  # screenshot the board
    godot4 --path . -- shotpop               # screenshot mid-pop
    godot4 --path . -- shotspecial           # screenshot with every special placed
    godot4 --path . -- shotshuffle           # screenshot a deadlocked board reshuffling
    godot4 --path . -- shotcombo             # screenshot a stripe + bomb combo firing
    godot4 --path . -- shotwin               # screenshot the level-cleared overlay
    godot4 --path . -- shotmenu              # screenshot the menu
    godot4 --path . -- shotselect            # screenshot level select with stars
    godot4 --path . -- shotjelly             # screenshot a jelly level
    python3 art/mkbg.py assets               # regenerate both scenes
    python3 art/mkfont.py assets             # regenerate the pixel font
    godot4 --path . --headless -- balance    # median score per level, 30 runs each

`selftest` prints one PASS/FAIL line per check and ends with ALL PASS. 85
checks: match classification (4h/4v/5/L), each blast shape, special
chain-reactions, a full cascade ending with no empty cells and exactly 64
sprites (so nothing leaks per cascade), deadlock detection plus reshuffle
against a known move-free board, and every pair combo - the bomb pairings
asserted by property (all partner-species pieces caught, reach wider than
those pieces alone) rather than by a hardcoded count, audio loading, the music
loop, that selecting a piece cues that species' own voice, and the level rules
(a reverted swap is free, a matching swap costs exactly one, win and lose fire
at the right thresholds, restart reloads the level), star thresholds, and the
progress file round-tripping without ever lowering a banked score, and both
new goal kinds (collect counting, jelly totals, a double layer taking two
clears, jelly surviving a collapse, winning always banking a star, and losing
on moves even with a huge score).

Two checks exist because of bugs they would have caught:

- `star_texture` asserts the star sheet actually loaded. `load()` on a PNG
  Godot has not imported yet returns null **silently**, so the first build of
  the win screen showed no stars while every other check passed.
- `no_stray_widgets` asserts no Label, ColorRect, Button, TextureRect or
  AnimatedSprite2D hangs directly off the root. When the screens were split
  into layers one label kept its `add_child(...)` call and showed up on top of
  the menu. Anything screen-specific must live on a layer.

## Not done

Pair combos are not previewed before you commit the swap. The
audio, voices included, was synthesised blind - it is verified as valid,
normalised, non-silent and correctly wired, but nobody has listened to it yet.
