# Progression ideas

A brainstorm for after the two fixes already queued for next session: the free
reshuffle without the star wallet, and holey boards that are actually visible.
Nothing here is built. It is a menu to pick from, with my recommendations up
front.

**Decided order:** the reshuffle fix, then the shape fix, then shortlist item 1
(your seal on the map). All three are built. Next to pick from: the rest of
the shortlist, starting at item 2.

## The yardstick

The brief: the game should change enough to stay interesting, but not so much
that it gets annoying or becomes a lot to think about. The core is already fun.
Every idea below was held to five rules that follow from that:

1. **Change the feel before the rules.** A new sky, new music or a new face on
   the board costs the player no thought at all. A new rule costs some. Spend
   the rules budget slowly.
2. **One new idea at a time, learnable in one level without reading.** If it
   needs a tutorial paragraph, it is too much. At most one new mechanic per
   chapter, and at most two kinds of obstacle active in any level.
3. **Earn, don't spend.** The star wallet failed because stars come in at 1-3
   per level and the gates already claim them. Meta progression should unlock
   things at milestones of a total that only ever goes up. If a spendable
   currency ever comes back, measure the earn rate first.
4. **Never punish.** No lives, energy, timers or streaks you can lose. Those
   exist in commercial match-3 to sell refills; here they would only annoy.
5. **Measure before tuning.** The balance sweep already reports clear rates.
   Any difficulty change gets swept, the way the level curve was.

## The shortlist

If I had to pick, in this order:

### 1. Your seal on the map

A critter token sits on the floe you are up to, and after a win it hops along
the trail to the next one. If that trail crosses a gate you have just paid,
the ice ridge sinks as it passes.

This is the payoff for today's change sending both ends of a level back to the
map. Right now the map is the place you return to; with a token on it, it
becomes the place where progress *happens*, and that moment is what makes the
three-star chase and the gates feel like a journey rather than a counter. The
gate currently just appears dimmed the next time you look - the sinking ridge
turns paying the toll into an event.

Cost: low to moderate. A sprite on `map_content`, a tween along `_node_pos`,
and remembering which level was just cleared when `_next_level()` opens the
map.

### 2. A new sky every chapter

Each chapter re-tints the play scene and the map: polar night with aurora (what
exists now), then dawn, falling snow, bright noon, midnight sun. The
composition stays the same - `bgkit.py` already builds the scenes
procedurally, so this is a palette and a snowfall layer rather than new art.
Pair each sky with a variation of the music; `mkaudio.py` generates the track,
and a re-voiced or re-harmonised variant also answers the old complaint about
music wearing thin over a long session.

This is the cheapest way to make the game feel different over time, and it
makes paying a gate feel like *arriving somewhere*. Zero rules change.

### 3. A chapter rhythm with a finale

Give every chapter the same shape:

- **Level 1 opens gently** - the reward for getting through the gate.
- **Levels 2-9 sawtooth** - hard ones followed by easy ones, not a straight
  climb.
- **Level 10 is a finale** - a bigger floe on the map with a flag, a larger
  goal with more moves, and a mix of everything that chapter introduced.

The generator already tapers moves across a chapter and resets them, so this
is mostly placing difficulty on purpose. The sweep data says difficulty is
currently driven by *goal type* more than by the curve: with random play,
score levels clear 30-45% of the time, collect levels 40-70%, and ice levels
only 10-20%. Ice levels sit on fixed slots (steps 3 and 7), so the spikes land
by accident. Real players beat random ones, but the ratio holds, and that is
the lever to pull.

### 4. One new idea per chapter

Introduced at chapter boundaries, so the gate doubles as the "something new
starts here" moment. Candidates, cheapest and lowest-thought first:

- **Frozen critters.** A critter inside an ice cube. It can't be swapped, but
  a match that includes it, or a special that hits it, cracks it free. It reads
  instantly, it is perfectly on theme, and because it is a *piece*, it falls
  with gravity and breaks nothing.
- **Snowbanks that melt.** Snow fills the bottom of some columns; a match next
  to it melts a layer, and the board *grows* as pieces drop into the space.
  Digging the board out is a new feeling with no new controls.
- **Feed the pups.** A fish that can't be matched rides down with gravity and
  has to reach the bottom row. A new goal type built from movement the player
  already understands.
- **Small boards.** A 6x8 or 7x7 board for quick, punchy breather levels, done
  with a shape mask rather than changing the grid size, so no layout work.

**The constraint all of these respect.** `_build_blocked()` requires every
column's open cells to be contiguous, because a hole in the middle of a column
splits it into a part gravity can never refill. So anything that sits in the
middle of the board must be a piece (frozen critters, fish), and anything that
is not a piece must sit at a column's ends (snowbanks from the bottom, shapes
from the edges). Snowbanks work *because* they melt from the bottom up. A
fully blocked column passes the `first >= 0` guard but has never been
exercised, so small boards need a test before they ship.

### 5. Star milestones instead of a wallet

The lifetime star total already exists and never goes down. Hang permanent
unlocks on it at points **halfway between gates**, so there is always
something next: gate, unlock, gate, unlock.

This is where extra reshuffles belong, as you suggested: a second free
reshuffle per level at the first milestone. After that, cosmetics - winter
scarves on the critters, a different board frame - rather than gameplay
buffs, so the game never gets easier than it was tuned for.

Before picking thresholds, add a stars-earned column to the balance sweep, so
the numbers come from how stars actually accumulate rather than from what
looks reasonable.

### 6. The colony on the menu

The menu shelf shows the six critters idling. Let it grow with you: babies of
each species join as you three-star chapters, an igloo appears after chapter
2, a fishing hole, a snowman, a little flag per chapter cleared. The menu
becomes a picture of your progress that you see every time you open the game.

`render()` in `critters.py` already takes `sx`/`sy` scale parameters, so pups
may be close to free.

## The longer list

**Linear (level to level)**

- **New critters that rotate in.** A beluga, puffin or arctic fox *replaces*
  one species for a chapter rather than adding a seventh colour, so it brings
  new faces and a new voice without making the board harder. Each new critter
  needs its own silhouette (tusks, horn, beak, ears) as well as its own colour,
  as the current six already do, so the game stays readable for colour-blind
  players.
- **Chapter intro card.** "CHAPTER 3 - SNOWFALL" with one line about the new
  idea, shown once, on the first level of the chapter.
- **Bigger boards later on.** A 9x9 board needs a smaller cell (about 56px) to
  fit above the HUD, so it is a layout job rather than a tweak. It only
  matters if small boards prove that board size is a lever worth pulling.

**Meta (across the game)**

- **Daily floe.** A level generated from today's date, the same for everyone,
  so "three stars on today's floe" is something to share via the same link
  people already pass around. The level spec is deterministic, but the board
  fill uses the global `randomize()`, so the daily needs its own seeded RNG to
  be identical for everyone. No streaks.
- **Field guide.** A page per critter that fills in as you clear them over the
  whole game: a fact card at 100 cleared, an alternate idle animation at 500.
  It needs per-species lifetime counters (today `collected` resets every
  level) and a new screen, so it comes after the cheaper ideas.
- **Endless chapters.** `LEVEL_COUNT` is the only limit on the generator.
  Past the authored chapters, keep generating and cycle the skies.

**Feel touches (cheap polish on moments that already exist)**

- Stars pop into the map node when you return with a new best.
- Critters do a little hop on the board when you three-star a level.
- A soft fanfare when a gate opens, distinct from the level-clear sound.

## What I would avoid

- **Lives, energy, timers, streaks** - punishment with nothing to sell.
- **A seventh colour on the board** - measurably harder, and the screen gets
  busier. Rotate critters instead.
- **Spendable currency without measuring its earn rate first** - today's lesson.
- **More than one new mechanic per chapter** - it stops being learnable in a
  level.
- **Text tutorials** - if it needs explaining, simplify it instead.
- **Static obstacles in the middle of a column** - gravity can't refill below
  them. Make it a piece, or anchor it to a column's end.

## A sample run of chapters

| Chapter | Sky | New idea |
| --- | --- | --- |
| 1 | Polar night (today's) | The basics: score, collect, ice |
| 2 | Dawn | Visible board shapes |
| 3 | Snowfall | Frozen critters |
| 4 | Bright noon | Small, quick boards |
| 5 | Aurora storm | Snowbanks that melt and grow the board |
| 6 | Midnight sun | A new critter rotates in |
| 7 | Blue hour | Feed the pups |
| 8+ | Skies cycle | Remixes of everything, two ideas at most per level |

## Decisions that are yours

- **How many levels is the target?** That decides whether this table needs 5
  chapters or 15.
- **New critters - yes or no?** Each one is art and a voice, though both
  pipelines are procedural.
- **Daily floe - wanted?**
- **Colony** - all six critters on the menu from the start with babies and
  decorations added over time (my preference), or start with one seal and
  have the rest join?
