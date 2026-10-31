extends RefCounted
## The level bot and the tools built on it.
##
## The bot plays greedily: every move it looks one swap ahead and takes the
## one worth most to the level's goal - matched cells, specials made, pieces
## of the collect species, jelly cleared. That is a far better stand-in for a
## person than random play, which never aims at anything and so made jelly
## levels look several times harder than they are.
##
## Everything here drives the board node `b` in fast mode (no animation).

const CAP := 60                  # moves a calibration game may run to

var b: Node


func _init(board: Node) -> void:
	b = board


func value(mv: Array) -> float:
	"""What one swap is worth toward the current goal, looking one move ahead
	(cascades are not simulated). Leaves the board exactly as it found it."""
	var a: Vector2i = mv[0]
	var c: Vector2i = mv[1]
	var ka: int = b.special[a.y][a.x]
	var kc: int = b.special[c.y][c.x]
	if ka != b.SP_NONE and kc != b.SP_NONE:
		return 60.0 + randf()               # two specials: always worth it
	b._swap_grid(a, c)
	var cells: Array = []
	var bonus := 0.0
	if ka != b.SP_NONE or kc != b.SP_NONE:
		# a single special goes off where it landed
		var seed: Array = []
		var target := -1
		for p in [a, c]:
			if b.special[p.y][p.x] != b.SP_NONE:
				seed.append(p)
				if b.special[p.y][p.x] == b.SP_BOMB:
					var other: Vector2i = c if p == a else a
					target = b.grid[other.y][other.x]
		cells = b._expand(seed, target)
	else:
		var seen := {}
		for g in b._groups():
			var made: int = b._classify(g)
			if made == b.SP_BOMB:
				bonus += 14.0
			elif made == b.SP_WRAPPED:
				bonus += 9.0
			elif made != b.SP_NONE:
				bonus += 6.0
			for cell in g["cells"]:
				seen[cell] = true
		cells = seen.keys()
	var v: float = cells.size() + bonus
	var kind: int = int(b.goal.get("kind", b.GOAL_SCORE))
	for cell in cells:
		if kind == b.GOAL_COLLECT and b.grid[cell.y][cell.x] == int(b.goal["species"]):
			v += 3.0
		elif kind == b.GOAL_JELLY and b.jelly[cell.y][cell.x] > 0:
			v += 4.0
	b._swap_grid(a, c)
	return v + randf() * 0.5            # random tie-break


func pick() -> Array:
	var best: Array = []
	var best_v := -1.0
	for mv in b._all_moves():
		var v: float = value(mv)
		if v > best_v:
			best_v = v
			best = mv
	return best


func play(i: int, cap: int = CAP) -> Dictionary:
	"""One game of level i with no move limit up to `cap`. Returns the move on
	which the goal was first met (-1 if never), so one game answers 'would it
	clear on N moves' for every N at once. Collect and jelly games end there;
	score games play on to MOVES_MAX and keep the score after every move, which
	is what the 2- and 3-star scores are measured from."""
	b._load_level(i)
	b.moves_left = cap + 1
	await b._settle()
	var reached := -1
	var scores: Array = []
	var kind: int = int(b.goal.get("kind", b.GOAL_SCORE))
	var last: int = cap if kind != b.GOAL_SCORE else mini(cap, b.MOVES_MAX)
	for m in last:
		var mv: Array = pick()
		if mv.is_empty():
			break
		await b._try_swap(mv[0], mv[1])
		scores.append(b.score)
		if reached < 0 and b._goal_met():
			reached = m + 1
			if kind != b.GOAL_SCORE:
				break                       # collect and jelly end when met
	return {"reached": reached, "scores": scores}


func score_at(g: Dictionary, budget: int) -> int:
	var sc: Array = g["scores"]
	if sc.is_empty():
		return 0
	return int(sc[mini(budget, sc.size()) - 1])


func star_cuts(games: Array, budget: int, kind: int, target: int) -> Array:
	"""The level's 2- and 3-star thresholds, set so the bot earns them
	STAR2_WANT and STAR3_WANT of the time. Score levels: scores. Collect and
	jelly: moves still in hand when the goal is met."""
	if kind == b.GOAL_SCORE:
		var finals: Array = []
		for g in games:
			finals.append(score_at(g, budget))
		finals.sort()
		finals.reverse()                    # best first
		var two: int = int(finals[mini(int(b.STAR2_WANT * finals.size()), finals.size() - 1)])
		var three: int = int(finals[mini(int(b.STAR3_WANT * finals.size()), finals.size() - 1)])
		two = maxi(int(round(two / 50.0)) * 50, target + 50)
		three = maxi(int(round(three / 50.0)) * 50, two + 50)
		return [two, three]
	var used2: int = budget_for(games, b.STAR2_WANT)
	var used3: int = budget_for(games, b.STAR3_WANT)
	var left2: int = clampi(budget - used2, 1, budget) if used2 > 0 else 1
	var left3: int = maxi(budget - used3 if used3 > 0 else left2 + 1, left2 + 1)
	return [left2, left3]


func stars(games: Array, budget: int, kind: int, cuts: Array = []) -> float:
	"""The bot's average stars on `budget`. With `cuts` it uses those
	thresholds; without, the classic rules (for the first 30 levels)."""
	var total := 0.0
	for g in games:
		var r: int = int(g["reached"])
		if r <= 0 or r > budget:
			continue
		if kind == b.GOAL_SCORE:
			var sc: int = score_at(g, budget)
			var two: int = int(cuts[0]) if cuts.size() == 2 else int(b.star_base * b.STAR_2)
			var three: int = int(cuts[1]) if cuts.size() == 2 else int(b.star_base * b.STAR_3)
			total += 3.0 if sc >= three else (2.0 if sc >= two else 1.0)
		elif cuts.size() == 2:
			var left: int = budget - r
			total += 3.0 if left >= int(cuts[1]) else (2.0 if left >= int(cuts[0]) else 1.0)
		else:
			var frac: float = float(budget - r) / float(budget)
			total += 3.0 if frac >= b.STAR_3_MOVES else (2.0 if frac >= b.STAR_2_MOVES else 1.0)
	return total / float(maxi(games.size(), 1))


func budget_for(games: Array, want: float) -> int:
	"""The fewest moves on which the bot clears at least `want` of its games,
	or -1 if even CAP moves are not enough."""
	for m in range(1, CAP + 1):
		if clear_rate(games, m) >= want:
			return m
	return -1


func calibrate(n: int, trials: int) -> Dictionary:
	"""Designs level n, then measures it: plays `trials` games and sets the
	move budget to hit _want_clear(n). If that budget falls outside
	MOVES_MIN..MOVES_MAX the goal is resized and measured again, so the
	design curve can be approximate and the result still lands right."""
	var i: int = n - 1
	while b.level_table.size() < n:
		b.level_table.append({})
	var want: float = b._want_clear(n)
	var mag := 1.0
	var spec: Dictionary = {}
	var games: Array = []
	var budget := -1
	for attempt in 4:
		spec = b._design_spec(n, mag)
		b.level_table[i] = spec
		games = []
		for t in trials:
			games.append(await play(i))
		budget = budget_for(games, want)
		if budget < 0:
			mag *= 0.75
		elif budget > b.MOVES_MAX:
			mag *= float(b.MOVES_MAX - 3) / float(budget)
		elif budget < b.MOVES_MIN:
			mag *= float(b.MOVES_MIN + 3) / float(budget)
		else:
			break
	budget = clampi(budget if budget > 0 else b.MOVES_MAX, b.MOVES_MIN, b.MOVES_MAX)
	var kind: int = int(spec["goal"]["kind"])
	spec["moves"] = budget
	var cuts: Array = star_cuts(games, budget, kind, int(spec["star_base"]))
	spec["stars"] = cuts
	spec["cal"] = {"want": snappedf(want, 0.01),
			"bot": snappedf(clear_rate(games, budget), 0.01),
			"stars": snappedf(stars(games, budget, kind, cuts), 0.01),
			"games": trials, "mag": snappedf(mag, 0.01)}
	b.level_table[i] = spec
	return spec


func clear_rate(games: Array, budget: int) -> float:
	var n := 0
	for g in games:
		if int(g["reached"]) > 0 and int(g["reached"]) <= budget:
			n += 1
	return float(n) / float(maxi(games.size(), 1))
