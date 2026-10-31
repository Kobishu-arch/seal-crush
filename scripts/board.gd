extends Node2D

# Match-3 prototype driven by the critter sheets.
#   idle    sheet: 4 frames across, 6 species down
#   pop     sheet: 8 frames across, 6 species down
#   special sheet: 12 across (stripe_h x4, stripe_v x4, wrapped x4), 6 down
#   bomb    sheet: 4 frames across, species independent

const COLS := 8
const ROWS := 8
const CELL := 64
const SPECIES := 6
const IDLE_DUR := [0.35, 0.25, 0.25, 0.09]
const POP_DUR := [0.06, 0.05, 0.05, 0.05, 0.06, 0.06, 0.05, 0.08]
const ORIGIN := Vector2(64, 160)
const BG := Color("0d2137")
# Levels are data (LEVELS_PATH), written by `-- bake`: _design_spec(n) says
# what a level asks for, and the bot measures how many moves that takes. Jelly
# layouts in it are eight strings: '.' none, '1' one layer, '2' two.
const LEVELS_PATH := "res://data/levels.json"
# Bot clear rate wanted on a level's budget: CLEAR_START in chapter 1, easing
# to CLEAR_FLOOR by chapter CLEAR_RAMP_CHAPTERS, plus a per-step shape inside
# each chapter (an easy opener, a sawtooth, a harder finale).
const CLEAR_START := 0.85
const CLEAR_FLOOR := 0.68
const CLEAR_RAMP_CHAPTERS := 8.0
const STEP_EASE := [0.10, 0.02, 0.0, -0.03, 0.04, -0.02, 0.03, -0.05, 0.0, -0.10]
const MOVES_MIN := 14            # a calibrated budget must land in here,
const MOVES_MAX := 30            # or the goal is resized and measured again
const BAKE_TRIALS := 40
# Stars on generated levels are measured too: the bot should earn 2 stars this
# often, and 3 stars this often. Fixed rules (1.3x the target, a share of the
# budget left) paid less and less as levels tightened, until chapters no
# longer paid for their own gate.
const STAR2_WANT := 0.5
const STAR3_WANT := 0.22
const CHAPTER := 10          # levels per chapter; the move budget resets here
# Total stars needed to enter each chapter. Winning always banks at least one
# star, so finishing a chapter guarantees CHAPTER stars - the gate asks for a
# 1.3 average, which means a few 2 and 3 star finishes rather than a grind.
const CHAPTER_GATE := 1.3
# Free reshuffles every level starts with. Stars are never spent: they only
# open chapter gates. Extra shuffles are for meta progression to hand out later.
const SHUFFLES_PER_LEVEL := 1

# Named board outlines, each a per-column [top, bottom] open range. Describing a
# shape by its column ranges makes the contiguity rule hold by construction:
# a column can lose cells from its top or its bottom, never from its middle.
const SHAPES := {
	"heart":  [[1, 0, 0, 1, 1, 0, 0, 1], [4, 5, 6, 7, 7, 6, 5, 4]],
	"igloo":  [[3, 1, 0, 0, 0, 0, 1, 3], [7, 7, 7, 5, 5, 7, 7, 7]],
	"valley": [[0, 1, 2, 3, 3, 2, 1, 0], [7, 7, 7, 7, 7, 7, 7, 7]],
	"castle": [[0, 2, 0, 2, 2, 0, 2, 0], [7, 7, 7, 6, 6, 7, 7, 7]],
	"bridge": [[0, 0, 0, 0, 0, 0, 0, 0], [7, 6, 5, 4, 4, 5, 6, 7]],
	"stairs": [[0, 0, 1, 1, 2, 2, 3, 3], [7, 7, 7, 7, 7, 7, 7, 7]],
}
# The rotation for shape levels (every third level). "floe" is the rounded
# corners mask from _shape_mask, cut deep enough to read as a shape.
const SHAPE_ORDER := ["floe", "floe", "heart", "igloo", "valley", "castle",
		"bridge", "stairs"]
# From this chapter on (0-based), the levels between shape levels get a
# random ragged edge too - seeded per level, so it is the same every play.
const DRIFT_FROM_CHAPTER := 1

# the seal on the map
const TOKEN_SCALE := 1.4
const TOKEN_OFFSET := Vector2(52, 4)
const HOPS_PER_FLOE := 3
const MAX_HOP_FLOES := 2        # further behind than this, it skips ahead
const HOP_SECS := 0.2
const HOP_HEIGHT := 22.0
const GATE_SINK := 7.0          # px the ridge drops once paid
const GATE_SINK_SECS := 0.5

const STAR_2_MOVES := 0.25      # fraction of the move budget still unspent
const STAR_3_MOVES := 0.45
const STAR_2 := 1.3          # multiples of target
const STAR_3 := 1.6
const SAVE_PATH := "user://progress.cfg"

# goal kinds
const GOAL_SCORE := 0
const GOAL_COLLECT := 1
const GOAL_JELLY := 2

const SPECIES_NAMES := ["seals", "penguins", "otters", "walruses", "narwhals", "bears"]
# short forms for the level list, where the pixel font leaves little room
const SPECIES_SHORT := ["SEAL", "PENG", "OTTR", "WALR", "NARW", "BEAR"]

# screens
const ST_MENU := 0
const ST_SELECT := 1
const ST_PLAY := 2

# special kinds
const SP_NONE := 0
const SP_STRIPE_H := 1   # clears its row
const SP_STRIPE_V := 2   # clears its column
const SP_WRAPPED := 3    # 3x3 blast
const SP_BOMB := 4       # clears every piece of one species

var grid: Array = []       # grid[r][c] = species index, -1 = empty
var special: Array = []    # special[r][c] = SP_*
var pieces: Array = []     # pieces[r][c] = AnimatedSprite2D or null
var frames: Array = []     # frames[species] -> plain SpriteFrames
var frames_sp: Array = []  # frames_sp[species][kind-1] -> special SpriteFrames
var frames_bomb: SpriteFrames
var selected := Vector2i(-1, -1)
var last_swap: Array = []
var busy := false
var score := 0
var score_label: Label
var combo_label: Label
var notice_label: Label
var keys_label: Label
var sfx: Dictionary = {}
var music: AudioStreamPlayer
var muted := false
var music_started := false
var moves_left := 0
var target := 0
var game_over := false
var species_count := SPECIES
var level := 0
var stars := 0
var best: Dictionary = {}
var level_label: Label
var star_nodes: Array = []
var star_full: AtlasTexture
var star_empty: AtlasTexture
var bg_layer: Node2D
var bg_front: Sprite2D
var bg_back: Sprite2D
var ui_font: Font
var menu_marks: Array = []
var bg_menu_tex: Texture2D
var bg_play_tex: Texture2D
var bg_map_tex: Texture2D
var board_layer: Node2D
var jelly_layer: Node2D
var hud_layer: Node2D
var menu_layer: Node2D
var select_layer: Node2D
var state := ST_MENU
var select_buttons: Array = []
var select_stars: Array = []
var select_back: Button
var select_total: Control
var map_content: Control
# The seal on the map: it stands on the level you are up to and hops along the
# trail when that moves on. token_at is where it stands (-1 = not placed yet);
# gates_shown is each gate as last drawn, so a gate that opened since sinks
# on screen instead of just appearing open.
var map_token: Node2D
var map_token_sprite: AnimatedSprite2D
var token_at := -1
var token_hopping := false
var gates_shown: Dictionary = {}
var map_scroll: ScrollContainer
var node_faces: Array = []
var node_numbers: Array = []
var gate_marks: Array = []   # one per chapter boundary: {chapter, text, floes}
var jelly: Array = []          # jelly[r][c] layers left on that cell, 0 = none
var jelly_left := 0
var collected := 0             # pieces of the goal species cleared this level
var goal: Dictionary = {}
var star_base := 0
var no_finish := false   # dev: balance harness plays every move
var shuffles_left := 0
var shuffle_button: Button
var level_table: Array = []
var board_shape: Array = []  # per-level outline, '#' marks a hole
var blocked: Array = []      # blocked[r][c]: a hole in the board
var col_top: Array = []      # highest open row per column, -1 if the column is closed
var col_bot: Array = []      # lowest open row per column
var fast := false          # dev: skip animation waits (balance harness)
var won := false
var moves_label: Label
var target_label: Label
var bar_bg: ColorRect
var bar_fill: ColorRect
var overlay: ColorRect
var result_label: Label
var result_sub: Label
var result_go: Button
var menu_play: Button
var result_retry: Button
var voices: Array = []
var voice_player: AudioStreamPlayer
var idle_tex: Texture2D
var pop_tex: Texture2D
var sp_tex: Texture2D
var bomb_tex: Texture2D


func _ready() -> void:
	randomize()
	idle_tex = load("res://assets/critters_idle_sheet.png")
	pop_tex = load("res://assets/critters_pop_sheet.png")
	sp_tex = load("res://assets/critters_special_sheet.png")
	bomb_tex = load("res://assets/bomb_sheet.png")
	for s in SPECIES:
		frames.append(_build_frames(s))
		frames_sp.append([
			_build_special_frames(s, SP_STRIPE_H),
			_build_special_frames(s, SP_STRIPE_V),
			_build_special_frames(s, SP_WRAPPED),
		])
	frames_bomb = _build_bomb_frames()
	_build_ui()
	_build_audio()
	_build_levels()
	_load_progress()
	_build_menu()
	var t_map: int = Time.get_ticks_usec()
	_build_select()
	if OS.get_cmdline_user_args().has("shotmap"):
		print("[map] %d levels built in %.1f ms" % [level_table.size(),
				(Time.get_ticks_usec() - t_map) / 1000.0])
	_goto(ST_MENU)
	queue_redraw()
	var args := OS.get_cmdline_user_args()
	if args.has("shot"):
		_auto_shot()
	elif args.has("selftest"):
		_selftest()
	elif args.has("shotpop"):
		_shot_pop()
	elif args.has("shotspecial"):
		_shot_special()
	elif args.has("shotshuffle"):
		_shot_shuffle()
	elif args.has("shotcombo"):
		_shot_combo()
	elif args.has("balance"):
		_balance()
	elif args.has("botcheck"):
		_bot_check()
	elif args.has("bake"):
		_bake()
	elif args.has("shotwin"):
		_shot_win()
	elif args.has("shotmenu"):
		_shot_menu()
	elif args.has("shotplay"):
		_shot_play()
	elif args.has("shothud"):
		_shot_hud()
	elif args.has("shotmap"):
		_shot_map()
	elif args.has("shotseal"):
		_shot_seal()
	elif args.has("shotgate"):
		_shot_gate()
	elif args.has("shotselect"):
		_shot_select()
	elif args.has("shotjelly"):
		_shot_jelly()
	elif args.has("shotshape"):
		_shot_shape()
	elif args.has("levels"):
		_print_levels()


func _atlas(tex: Texture2D, col: int, row: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(col * 32, row * 32, 32, 32)
	return at


func _add_pop(sf: SpriteFrames, s: int) -> void:
	sf.add_animation("pop")
	sf.set_animation_loop("pop", false)
	sf.set_animation_speed("pop", 1.0)
	for i in POP_DUR.size():
		sf.add_frame("pop", _atlas(pop_tex, i, s), POP_DUR[i])


func _build_frames(s: int) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("idle")
	sf.set_animation_loop("idle", true)
	sf.set_animation_speed("idle", 1.0)
	for i in IDLE_DUR.size():
		sf.add_frame("idle", _atlas(idle_tex, i, s), IDLE_DUR[i])
	_add_pop(sf, s)
	return sf


func _build_special_frames(s: int, kind: int) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("idle")
	sf.set_animation_loop("idle", true)
	sf.set_animation_speed("idle", 1.0)
	var base: int = (kind - 1) * 4
	for i in IDLE_DUR.size():
		sf.add_frame("idle", _atlas(sp_tex, base + i, s), IDLE_DUR[i])
	_add_pop(sf, s)
	return sf


func _build_bomb_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("idle")
	sf.set_animation_loop("idle", true)
	sf.set_animation_speed("idle", 1.0)
	for i in IDLE_DUR.size():
		sf.add_frame("idle", _atlas(bomb_tex, i, 0), IDLE_DUR[i])
	_add_pop(sf, 0)
	return sf


func _frames_for(s: int, kind: int) -> SpriteFrames:
	if kind == SP_BOMB:
		return frames_bomb
	if kind == SP_NONE:
		return frames[s]
	return frames_sp[s][kind - 1]


# --- ui -------------------------------------------------------------------

func _font(c: Control, size: int, col: Color, shadow: bool = true) -> void:
	if ui_font != null:
		c.add_theme_font_override("font", ui_font)
	c.add_theme_font_size_override("font_size", size)
	c.add_theme_color_override("font_color", col)
	if shadow:
		c.add_theme_color_override("font_shadow_color", Color(0.02, 0.06, 0.13, 0.85))
		c.add_theme_constant_override("shadow_offset_x", 2)
		c.add_theme_constant_override("shadow_offset_y", 2)
		c.add_theme_color_override("font_outline_color", Color(0.03, 0.08, 0.16, 0.95))
		c.add_theme_constant_override("outline_size", 4)


func _build_ui() -> void:
	ui_font = load("res://assets/pixelfont.fnt")
	assert(ui_font != null, "assets/pixelfont.fnt missing or not imported")
	bg_layer = Node2D.new()
	add_child(bg_layer)
	bg_menu_tex = load("res://assets/bg_menu.png")
	bg_play_tex = load("res://assets/bg_play.png")
	bg_map_tex = load("res://assets/bg_map.png")
	assert(bg_menu_tex != null and bg_play_tex != null and bg_map_tex != null,
			"a background scene is missing or not imported")
	bg_back = Sprite2D.new()
	bg_back.texture = bg_menu_tex
	bg_back.centered = false
	bg_back.scale = Vector2(2, 2)
	bg_back.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg_back.z_index = -20
	bg_layer.add_child(bg_back)
	# the same image again over the header strip, so pieces falling in from
	# above the board are hidden behind a seamless slice of the sky
	var top := AtlasTexture.new()
	top.atlas = bg_play_tex
	top.region = Rect2(0, 0, 320, ORIGIN.y / 2)
	bg_front = Sprite2D.new()
	bg_front.texture = top
	bg_front.centered = false
	bg_front.scale = Vector2(2, 2)
	bg_front.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg_front.z_index = 4
	bg_layer.add_child(bg_front)

	board_layer = Node2D.new()
	add_child(board_layer)
	# above the pieces, so jelly is actually visible; Polygon2D rather than a
	# ColorRect because a Control here would swallow clicks meant for the board
	jelly_layer = Node2D.new()
	add_child(jelly_layer)
	hud_layer = Node2D.new()
	add_child(hud_layer)
	menu_layer = Node2D.new()
	add_child(menu_layer)
	select_layer = Node2D.new()
	add_child(select_layer)

	var title := Label.new()
	title.text = "SEAL CRUSH"
	title.position = Vector2(64, 44)
	_font(title, 28, Color("bdeeff"))
	title.z_index = 6
	hud_layer.add_child(title)

	score_label = Label.new()
	score_label.position = Vector2(64, 80)
	_font(score_label, 21, Color("ffd977"))
	score_label.z_index = 6
	hud_layer.add_child(score_label)

	# Soft vignettes instead of a scrim rectangle: a flat panel left a hard
	# seam straight across the scene at the board's top edge. These ramp to
	# zero alpha exactly where the board begins, so there is no edge at all.
	for spec in [["res://assets/ui_fade_top.png", 0.0, 80.0],
			["res://assets/ui_fade_bot.png", 672.0, 44.0]]:
		var fade := Sprite2D.new()
		fade.texture = load(spec[0])
		assert(fade.texture != null, "%s missing or not imported" % spec[0])
		fade.centered = false
		fade.position = Vector2(0, spec[1])
		fade.scale = Vector2(160, 2)
		fade.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fade.z_index = 5
		hud_layer.add_child(fade)

	level_label = Label.new()
	level_label.position = Vector2(458, 42)
	_font(level_label, 14, Color(0.80, 0.90, 1.0, 0.85))
	level_label.z_index = 6
	hud_layer.add_child(level_label)

	moves_label = Label.new()
	moves_label.position = Vector2(458, 80)
	_font(moves_label, 21, Color("9fe3ff"))
	moves_label.z_index = 6
	hud_layer.add_child(moves_label)

	target_label = Label.new()
	target_label.position = Vector2(64, 110)
	_font(target_label, 14, Color(0.88, 0.95, 1.0, 0.92))
	target_label.z_index = 6
	hud_layer.add_child(target_label)

	bar_bg = ColorRect.new()
	bar_bg.position = Vector2(64, 136)
	bar_bg.size = Vector2(512, 6)
	bar_bg.color = Color(1, 1, 1, 0.12)
	bar_bg.z_index = 6
	hud_layer.add_child(bar_bg)

	bar_fill = ColorRect.new()
	bar_fill.position = Vector2(64, 136)
	bar_fill.size = Vector2(0, 6)
	bar_fill.color = Color("ffd977")
	bar_fill.z_index = 7
	hud_layer.add_child(bar_fill)

	combo_label = Label.new()
	combo_label.position = Vector2(300, 110)
	combo_label.size = Vector2(276, 22)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_font(combo_label, 14, Color("ff95bb"))
	combo_label.modulate.a = 0.0
	combo_label.z_index = 6
	hud_layer.add_child(combo_label)

	notice_label = Label.new()
	notice_label.position = Vector2(0, 392)
	notice_label.size = Vector2(640, 40)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(notice_label, 21, Color("ffd977"))
	notice_label.modulate.a = 0.0
	notice_label.z_index = 7
	hud_layer.add_child(notice_label)

	_build_legend()

	overlay = ColorRect.new()
	overlay.size = Vector2(640, 760)
	overlay.color = Color(0.03, 0.09, 0.16, 0.80)
	overlay.z_index = 10
	overlay.visible = false
	hud_layer.add_child(overlay)

	var star_sheet: Texture2D = load("res://assets/stars.png")
	assert(star_sheet != null, "assets/stars.png is missing or not imported")
	star_full = AtlasTexture.new()
	star_full.atlas = star_sheet
	star_full.region = Rect2(0, 0, 16, 16)
	star_empty = AtlasTexture.new()
	star_empty.atlas = star_sheet
	star_empty.region = Rect2(16, 0, 16, 16)
	for i in 3:
		var tr := TextureRect.new()
		tr.position = Vector2(264 + i * 40, 278)
		tr.scale = Vector2(2, 2)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.z_index = 11
		tr.visible = false
		hud_layer.add_child(tr)
		star_nodes.append(tr)

	result_label = Label.new()
	result_label.position = Vector2(0, 330)
	result_label.size = Vector2(640, 50)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 35)
	result_label.z_index = 11
	result_label.visible = false
	hud_layer.add_child(result_label)

	result_go = _button("LEVELS", Vector2(120, 436), Vector2(180, 48), 26)
	result_go.z_index = 11
	result_go.visible = false
	result_go.pressed.connect(func(): _next_level())
	hud_layer.add_child(result_go)

	result_retry = _button("REPLAY", Vector2(340, 436), Vector2(180, 48), 26)
	result_retry.z_index = 11
	result_retry.visible = false
	result_retry.pressed.connect(func(): _restart())
	hud_layer.add_child(result_retry)

	result_sub = Label.new()
	result_sub.position = Vector2(0, 390)
	result_sub.size = Vector2(640, 30)
	result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(result_sub, 14, Color(0.9, 0.95, 1.0, 0.9))
	result_sub.z_index = 11
	result_sub.visible = false
	hud_layer.add_child(result_sub)

	_update_score()


func _button(text: String, pos: Vector2, size: Vector2, font_size: int = 22) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = size
	b.flat = true
	for key in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(key, StyleBoxEmpty.new())
	_font(b, font_size, Color("dff1ff"))
	b.add_theme_color_override("font_hover_color", Color("fff1c9"))
	b.add_theme_color_override("font_pressed_color", Color("9fe3ff"))
	b.add_theme_color_override("font_disabled_color", Color(0.62, 0.72, 0.84, 0.45))
	return b


func _retext(ctrl: Control, text: String) -> void:
	for ch in ctrl.get_children():
		if ch is Label:
			ch.text = text


func _outlined(text: String, pos: Vector2, size: Vector2, font_size: int,
		col: Color, outline: bool = true) -> Control:
	# Godot ignores outline_size for bitmap fonts - it builds outlines from
	# vector glyph data - so thin pixel strokes get an outline the manual way,
	# from eight offset copies behind the real label.
	var root := Control.new()
	root.position = pos
	root.size = size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if outline:
		for o in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2),
				Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2)]:
			var sh := Label.new()
			sh.text = text
			sh.position = o
			sh.size = size
			sh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_font(sh, font_size, Color(0.02, 0.06, 0.14, 0.95), false)
			root.add_child(sh)
	var l := Label.new()
	l.text = text
	l.size = size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font(l, font_size, col, false)
	root.add_child(l)
	return root


func _screen_label(text: String, y: float, font_size: int, col: Color,
		outline: bool = false) -> Control:
	return _outlined(text, Vector2(0, y), Vector2(640, font_size + 14),
			font_size, col, outline)


func _star_rect(pos: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.position = pos
	tr.scale = Vector2(1.6, 1.6)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.texture = star_empty
	return tr


func _hover_marks(b: Button, font_size: int) -> void:
	var w: float = 60.0
	if ui_font != null:
		w = ui_font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var cy: float = b.position.y + b.size.y * 0.5
	var pair: Array = []
	for side in [-1.0, 1.0]:
		var pg := Polygon2D.new()
		pg.polygon = PackedVector2Array([Vector2(0, -5), Vector2(5, 0),
				Vector2(0, 5), Vector2(-5, 0)])
		pg.position = Vector2(320.0 + side * (w * 0.5 + 22.0), cy)
		pg.color = Color("9fe3ff")
		pg.visible = false
		menu_layer.add_child(pg)
		pair.append(pg)
	b.mouse_entered.connect(func():
		for pg in pair:
			pg.visible = true)
	b.mouse_exited.connect(func():
		for pg in pair:
			pg.visible = false)
	menu_marks.append(pair)


func _build_menu() -> void:
	menu_layer.add_child(_screen_label("SEAL CRUSH", 112, 42, Color("bdeeff"), true))
	menu_layer.add_child(_screen_label("A TINY MATCH-3", 172, 14, Color(0.80, 0.90, 1.0, 0.85), true))

	# the cast, idling
	for i in SPECIES:
		# contact shadow first - without one they read as stickers pasted on
		var shade := Polygon2D.new()
		var ring := PackedVector2Array()
		for k in 14:
			var a := TAU * k / 14.0
			ring.append(Vector2(cos(a) * 27.0, sin(a) * 6.5))
		shade.polygon = ring
		shade.position = Vector2(80 + i * 96, 297)
		shade.color = Color(0.06, 0.15, 0.24, 0.30)
		menu_layer.add_child(shade)

		var sp := AnimatedSprite2D.new()
		sp.sprite_frames = frames[i]
		sp.scale = Vector2(2, 2)
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.position = Vector2(80 + i * 96, 262)
		sp.modulate = Color(0.95, 0.98, 1.0)      # settle them into the night
		menu_layer.add_child(sp)
		sp.play("idle")
		sp.frame = i % IDLE_DUR.size()

	menu_play = _button("PLAY", Vector2(210, 348), Vector2(220, 54), 35)
	var play := menu_play
	play.pressed.connect(func(): _goto_select_at(_focus_level()))
	menu_layer.add_child(play)
	_hover_marks(play, 35)

	var levels := _button("LEVELS", Vector2(210, 414), Vector2(220, 54), 35)
	levels.pressed.connect(func(): _goto(ST_SELECT))
	menu_layer.add_child(levels)
	_hover_marks(levels, 35)

	if not OS.has_feature("web"):
		var quit := _button("QUIT", Vector2(210, 480), Vector2(220, 54), 35)
		quit.pressed.connect(func(): get_tree().quit())
		menu_layer.add_child(quit)
		_hover_marks(quit, 35)

	menu_layer.add_child(_screen_label(
			"M MUTE" if OS.has_feature("web") else "M MUTE    ESC QUIT", 700, 14,
			Color(0.13, 0.21, 0.33, 0.95), false))


func _disc(radius: float, col: Color, sides: int = 22) -> Polygon2D:
	var pts := PackedVector2Array()
	for k in sides:
		var a := TAU * k / float(sides)
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	var pg := Polygon2D.new()
	pg.polygon = pts
	pg.color = col
	return pg


func _floe_points(r: float, sides: int, seed_i: int) -> PackedVector2Array:
	"""An angular, slightly irregular chunk of ice. Deterministic per level, so
	each floe has its own shape but never changes between runs."""
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + seed_i
	var pts := PackedVector2Array()
	for k in sides:
		var a: float = TAU * k / float(sides) + rng.randf_range(-0.10, 0.10)
		var rr: float = r * rng.randf_range(0.84, 1.06)
		pts.append(Vector2(cos(a) * rr, sin(a) * rr))
	return pts


func _floe(r: float, col: Color, seed_i: int, offset := Vector2.ZERO) -> Polygon2D:
	var pg := Polygon2D.new()
	pg.polygon = _floe_points(r, 9, seed_i)
	pg.color = col
	pg.position = offset
	return pg


func _node_pos(i: int) -> Vector2:
	# A winding trail: the path is generated, so it extends to any level count.
	# Each chapter boundary opens an extra gap for the star gate to stand in.
	return Vector2(320.0 + 150.0 * sin(i * 0.95),
			54.0 + i * 118.0 + float(i / CHAPTER) * 110.0)


func _build_select() -> void:
	select_layer.add_child(_screen_label("SELECT LEVEL", 54, 28, Color("bdeeff"), true))

	# A scrolling map rather than a fixed list: the old rows were absolutely
	# positioned and fitted exactly six levels before colliding with BACK.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 104)
	scroll.size = Vector2(640, 580)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	select_layer.add_child(scroll)

	map_scroll = scroll
	map_content = Control.new()
	var last := _node_pos(level_table.size() - 1)
	map_content.custom_minimum_size = Vector2(640, last.y + 110.0)
	scroll.add_child(map_content)

	# stepping-stone trail between the floes
	for i in level_table.size() - 1:
		var a := _node_pos(i)
		var b := _node_pos(i + 1)
		if (i + 1) % CHAPTER == 0:
			_build_gate((i + 1) / CHAPTER, (a.y + b.y) * 0.5)
			continue        # a star gate stands here, not stepping stones
		for k in range(1, 5):
			var dot := _disc(4.0, Color(0.82, 0.92, 0.99, 0.72), 8)
			dot.position = a.lerp(b, k / 5.0)
			map_content.add_child(dot)

	for i in level_table.size():
		var c := _node_pos(i)

		# a chunk of ice, shaded like the bergs: dark rim, mid face, lit facet
		var rim := _floe(35.0, Color(0.05, 0.12, 0.21, 0.80), i, c)
		map_content.add_child(rim)
		var face := _floe(30.0, Color("a7cde8"), i, c)
		map_content.add_child(face)
		var facet := _floe(21.0, Color("e6f4ff"), i, c + Vector2(-4, -5))
		map_content.add_child(facet)
		node_faces.append([face, facet])

		# the number gets the same treatment as every other heading in the game:
		# light fill with a dark outline, rather than bare dark-on-pale
		var num := _outlined(str(i + 1), Vector2(c.x - 34.0, c.y - 20.0),
				Vector2(68, 40), 28, Color("f4fbff"))
		map_content.add_child(num)
		node_numbers.append(num)

		var b := _button("", Vector2(c.x - 34.0, c.y - 34.0), Vector2(68, 68), 28)
		b.pressed.connect(_start_level.bind(i))
		map_content.add_child(b)
		select_buttons.append(b)

		var info := Label.new()
		info.text = "%d MOVES   %s" % [level_table[i]["moves"], _level_summary(i)]
		info.position = Vector2(c.x - 150.0, c.y + 60.0)
		info.size = Vector2(300, 20)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_font(info, 14, Color(0.88, 0.95, 1.0, 0.85))
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_content.add_child(info)

		var row: Array = []
		for j in 3:
			var tr := _star_rect(Vector2(c.x - 31.0 + j * 22.0, c.y + 37.0))
			tr.scale = Vector2(1.2, 1.2)
			map_content.add_child(tr)
			row.append(tr)
		select_stars.append(row)

	# the seal goes in last, so it stands on top of floes, stars and labels
	map_token = Node2D.new()
	map_token.z_index = 3
	var shade := Polygon2D.new()
	var ring := PackedVector2Array()
	for k in 14:
		var a := TAU * k / 14.0
		ring.append(Vector2(cos(a) * 17.0, sin(a) * 4.5))
	shade.polygon = ring
	shade.color = Color(0.04, 0.10, 0.18, 0.40)
	map_token.add_child(shade)
	map_token_sprite = AnimatedSprite2D.new()
	map_token_sprite.sprite_frames = frames[0]
	map_token_sprite.scale = Vector2(TOKEN_SCALE, TOKEN_SCALE)
	map_token_sprite.position = Vector2(0, -16.0 * TOKEN_SCALE + 3.0)
	map_token_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_token.add_child(map_token_sprite)
	map_token_sprite.play("idle")
	map_token.visible = false
	map_content.add_child(map_token)

	select_total = _outlined("", Vector2(16, 710), Vector2(220, 26), 17,
			Color("d8f1ff"))
	select_layer.add_child(select_total)

	select_back = _button("BACK", Vector2(250, 700), Vector2(140, 46), 21)
	select_back.pressed.connect(func(): _goto(ST_MENU))
	select_layer.add_child(select_back)


func _build_gate(chapter: int, y: float) -> void:
	"""A ridge of ice across the channel where one chapter ends and the next
	begins, captioned with the star toll. _refresh_select fills in the text."""
	var floes: Array = []
	for k in 6:
		var x: float = 140.0 + k * 76.0
		var rim := _floe(26.0, Color(0.05, 0.12, 0.21, 0.70), chapter * 31 + k,
				Vector2(x, y))
		rim.scale = Vector2(1.0, 0.42)
		map_content.add_child(rim)
		var face := _floe(22.0, Color("9dc4e0"), chapter * 31 + k, Vector2(x, y - 2))
		face.scale = Vector2(1.0, 0.42)
		map_content.add_child(face)
		floes.append([rim, face])

	var cap := _outlined("", Vector2(120, y + 14.0), Vector2(400, 34), 20,
			Color("f4fbff"))
	map_content.add_child(cap)
	gate_marks.append({"chapter": chapter, "cap": cap, "floes": floes, "y": y})


func _refresh_select(arriving: bool = false) -> void:
	"""Redraws the map from progress. When the player is arriving on the map
	(`arriving`), a gate that opened since it was last drawn is left standing
	for _advance_token() to sink on screen; otherwise everything snaps."""
	var total: int = _total_stars()
	_retext(select_total, "%d OF %d STARS" % [total, level_table.size() * 3])
	for g in gate_marks:
		var ch: int = int(g["chapter"])
		var open_gate: bool = total >= _chapter_gate(ch)
		var shown: bool = bool(gates_shown.get(ch, open_gate))
		if arriving and open_gate and not shown:
			_gate_look(g, false)        # pending: it sinks once the seal is here
		else:
			_gate_look(g, open_gate)

	for i in level_table.size():
		var unlocked: bool = _is_unlocked(i)
		select_buttons[i].disabled = not unlocked
		node_faces[i][0].color = Color("a7cde8") if unlocked else Color(0.40, 0.49, 0.58, 0.80)
		node_faces[i][1].color = Color("e6f4ff") if unlocked else Color(0.52, 0.60, 0.68, 0.80)
		node_numbers[i].modulate.a = 1.0 if unlocked else 0.45
		var earned: int = int(best.get(i, 0))
		for j in 3:
			select_stars[i][j].texture = star_full if j < earned else star_empty
			select_stars[i][j].modulate.a = 1.0 if unlocked else 0.3


func _level_summary(i: int) -> String:
	var g: Dictionary = level_table[i]["goal"]
	match int(g["kind"]):
		GOAL_COLLECT:
			return "%dx %s" % [int(g["count"]), SPECIES_SHORT[int(g["species"])]]
		GOAL_JELLY:
			var n := 0
			for line in g["layout"]:
				for ch in line:
					if ch == "1" or ch == "2":
						n += int(ch)
			return "%d ICE" % n
		_:
			return "%d PTS" % int(g["score"])


func _total_stars() -> int:
	var n := 0
	for i in level_table.size():
		n += int(best.get(i, 0))
	return n


func _chapter_gate(ch: int) -> int:
	return int(round(ch * CHAPTER * CHAPTER_GATE))


func _is_unlocked(i: int) -> bool:
	"""Two rules at once: the previous level must have a star, and the
	chapter's star gate must be met. Centralised so the map, PLAY and the
	end-of-level advance cannot disagree about what is reachable."""
	if i <= 0:
		return true
	if int(best.get(i - 1, 0)) <= 0:
		return false
	return _total_stars() >= _chapter_gate(i / CHAPTER)


func _focus_level() -> int:
	"""The level the player is up to: the first unlocked one still unstarred,
	or the furthest unlocked level once they are all cleared."""
	var i: int = _next_unplayed()
	if int(best.get(i, 0)) > 0:
		for j in level_table.size():
			if _is_unlocked(j):
				i = j
	return i


func _scroll_to_level(i: int) -> void:
	if map_scroll == null:
		return
	var y: float = _node_pos(clampi(i, 0, level_table.size() - 1)).y
	map_scroll.scroll_vertical = int(maxf(y - 260.0, 0.0))


func _gate_look(g: Dictionary, open_gate: bool, secs: float = 0.0) -> void:
	"""Draws a gate standing or sunk. With `secs`, the ridge sinks over that
	long rather than snapping - the moment the toll is paid, made visible."""
	var ch: int = int(g["chapter"])
	gates_shown[ch] = open_gate
	if open_gate:
		_retext(g["cap"], "CHAPTER %d" % (ch + 1))
	else:
		_retext(g["cap"], "CHAPTER %d  %d OF %d STARS"
				% [ch + 1, _total_stars(), _chapter_gate(ch)])
	var cap_a: float = 0.55 if open_gate else 1.0
	var rim_col := Color(0.05, 0.12, 0.21, 0.18 if open_gate else 0.70)
	var face_col: Color = Color(0.70, 0.84, 0.93, 0.25) if open_gate else Color("9dc4e0")
	var sink: float = GATE_SINK if open_gate else 0.0
	var y: float = float(g["y"])
	if secs <= 0.0:
		g["cap"].modulate.a = cap_a
		for pair in g["floes"]:
			pair[0].color = rim_col
			pair[1].color = face_col
			pair[0].position.y = y + sink
			pair[1].position.y = y - 2.0 + sink
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(g["cap"], "modulate:a", cap_a, secs)
	var k := 0
	for pair in g["floes"]:
		# outer floes go under a beat after the middle ones, like a wave
		var d: float = absf(k - 2.5) * 0.05
		tw.tween_property(pair[0], "color", rim_col, secs).set_delay(d)
		tw.tween_property(pair[1], "color", face_col, secs).set_delay(d)
		tw.tween_property(pair[0], "position:y", y + sink, secs) \
				.set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(pair[1], "position:y", y - 2.0 + sink, secs) \
				.set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		k += 1
	await tw.finished


func _token_spot(i: int) -> Vector2:
	# feet on the floe's right shoulder, clear of the number and the stars
	return _node_pos(clampi(i, 0, level_table.size() - 1)) + TOKEN_OFFSET


func _gate_y(ch: int) -> float:
	for g in gate_marks:
		if int(g["chapter"]) == ch:
			return float(g["y"])
	return 0.0


func _advance_token() -> void:
	"""Moves the seal to the level the player is up to. The first time, and
	when going backwards, it is just placed; otherwise it hops along the trail
	one floe at a time, and a gate it crosses that has just opened sinks as it
	lands on the ridge. Gates that opened elsewhere sink once it is done."""
	if map_token == null or token_hopping:
		return
	var target: int = _focus_level()
	map_token.visible = true
	if token_at < 0 or target < token_at or fast:
		token_at = target
		map_token.position = _token_spot(target)
		_sink_pending(0.0)
		return
	if target - token_at > MAX_HOP_FLOES:
		# a long way behind: it is the last stretch that tells the story
		token_at = target - 1
		map_token.position = _token_spot(token_at)
	token_hopping = true
	while token_at < _focus_level():
		var a: Vector2 = _token_spot(token_at)
		var b: Vector2 = _token_spot(token_at + 1)
		var ch: int = (token_at + 1) / CHAPTER
		var crosses: bool = (token_at + 1) % CHAPTER == 0
		if crosses:
			# two hops up onto the ridge, the ridge sinks, two hops off it
			var ridge := Vector2((a.x + b.x) * 0.5, _gate_y(ch) - 6.0)
			for k in 2:
				await _hop(a.lerp(ridge, (k + 1) / 2.0))
			for g in gate_marks:
				if int(g["chapter"]) == ch and not bool(gates_shown.get(ch, true)):
					_play("combo")
					await _gate_look(g, true, GATE_SINK_SECS)
			for k in 2:
				await _hop(ridge.lerp(b, (k + 1) / 2.0))
		else:
			for k in HOPS_PER_FLOE:
				await _hop(a.lerp(b, (k + 1) / float(HOPS_PER_FLOE)))
		token_at += 1
	token_hopping = false
	if state == ST_SELECT:
		_play_voice(0)          # the seal says hello from its new floe
	_sink_pending(GATE_SINK_SECS)


func _hop(to: Vector2) -> void:
	var from: Vector2 = map_token.position
	_play("move", 1.15)
	var arc := func(t: float) -> void:
		map_token.position = from.lerp(to, t) + Vector2(0, -sin(PI * t) * HOP_HEIGHT)
	var tw := create_tween()
	tw.tween_method(arc, 0.0, 1.0, HOP_SECS)
	await tw.finished
	# a little squash on landing
	var sq := create_tween()
	map_token_sprite.scale = Vector2(TOKEN_SCALE * 1.15, TOKEN_SCALE * 0.85)
	sq.tween_property(map_token_sprite, "scale",
			Vector2(TOKEN_SCALE, TOKEN_SCALE), 0.08)
	await sq.finished


func _sink_pending(secs: float) -> void:
	var total: int = _total_stars()
	for g in gate_marks:
		var ch: int = int(g["chapter"])
		if total >= _chapter_gate(ch) and not bool(gates_shown.get(ch, true)):
			_gate_look(g, true, secs)


func _goto_select_at(i: int) -> void:
	var from: int = token_at
	_goto(ST_SELECT)
	_scroll_to_level(i)
	# Across a gate the floes are 228px apart, not 118: pull the view up so
	# the floe the seal hops from is still on screen.
	if from >= 0 and from < i and i - from <= 2 and map_scroll != null:
		map_scroll.scroll_vertical = mini(map_scroll.scroll_vertical,
				int(maxf(_node_pos(from).y - 90.0, 0.0)))


func _next_unplayed() -> int:
	for i in level_table.size():
		if int(best.get(i, 0)) == 0 and _is_unlocked(i):
			return i
	return 0


func _goto(s: int) -> void:
	state = s
	menu_layer.visible = s == ST_MENU
	select_layer.visible = s == ST_SELECT
	board_layer.visible = s == ST_PLAY
	jelly_layer.visible = s == ST_PLAY
	bg_front.visible = s == ST_PLAY
	# each screen has its own scene: vista, channel, pool
	if s == ST_MENU:
		bg_back.texture = bg_menu_tex
	elif s == ST_SELECT:
		bg_back.texture = bg_map_tex
	else:
		bg_back.texture = bg_play_tex
	hud_layer.visible = s == ST_PLAY
	if s != ST_PLAY:
		_hide_result()
	if s == ST_SELECT:
		_refresh_select(true)
		_advance_token()
	queue_redraw()


func _start_level(i: int) -> void:
	if busy:
		return
	busy = true
	_goto(ST_PLAY)
	_load_level(i)
	await _settle()
	busy = false


func _build_legend() -> void:
	# Icon + label pairs rather than one run-on line, grouped by meaning, with
	# the key bindings on their own row beneath. Icons stay at 1x - any
	# fractional scale breaks the pixel grid.
	var entries := [
		["MATCH 4", sp_tex, 0],     # striped
		["L OR T SHAPE", sp_tex, 8],   # wrapped
		["MATCH 5", bomb_tex, 0],   # colour bomb
	]
	var icon := 32.0
	var inner := 6.0        # label to icon
	var gap := 34.0         # between groups, now that there are no chips
	var widths: Array = []
	var total := -gap
	for e in entries:
		var w: float = 60.0
		if ui_font != null:
			w = ui_font.get_string_size(e[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		widths.append(w)
		total += w + inner + icon + gap
	var x: float = (640.0 - total) * 0.5
	for i in entries.size():
		var cw: float = widths[i] + inner + icon
		var lab := Label.new()
		lab.text = entries[i][0]
		lab.position = Vector2(x, 683)
		_font(lab, 14, Color(0.90, 0.95, 1.0, 0.96))
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lab.z_index = 7
		hud_layer.add_child(lab)

		var at := AtlasTexture.new()
		at.atlas = entries[i][1]
		at.region = Rect2(entries[i][2] * 32, 0, 32, 32)
		var ic := TextureRect.new()
		ic.texture = at
		ic.position = Vector2(x + widths[i] + inner, 676)
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.z_index = 7
		hud_layer.add_child(ic)
		x += cw + gap

	# The level's free reshuffle. A button as well as the S key, so it is
	# reachable on touch screens.
	shuffle_button = _button("", Vector2(220, 710), Vector2(200, 30), 14)
	shuffle_button.z_index = 7
	shuffle_button.pressed.connect(func(): _use_shuffle())
	hud_layer.add_child(shuffle_button)

	keys_label = Label.new()
	var keys := keys_label
	keys.text = "R RETRY     ESC LEVELS     M MUTE"
	keys.position = Vector2(0, 742)
	keys.size = Vector2(640, 20)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_font(keys, 12, Color(0.72, 0.84, 0.96, 0.88))
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keys.z_index = 6
	hud_layer.add_child(keys)


func _draw() -> void:
	if state != ST_PLAY:
		return
	for r in ROWS:
		for c in COLS:
			var p: Vector2 = ORIGIN + Vector2(c * CELL, r * CELL)
			if not _is_open(r, c):
				# a slab of ice sitting in the pool
				draw_rect(Rect2(p + Vector2(1, 1), Vector2(CELL - 2, CELL - 2)),
						Color(0.70, 0.83, 0.92, 0.95), true)
				draw_rect(Rect2(p + Vector2(1, 1), Vector2(CELL - 2, 6)),
						Color(0.90, 0.96, 1.0, 0.95), true)
				draw_rect(Rect2(p + Vector2(1, 1), Vector2(CELL - 2, CELL - 2)),
						Color(0.35, 0.50, 0.62, 0.8), false, 2.0)
				continue
			var tint := Color(1, 1, 1, 0.025) if (r + c) % 2 == 0 else Color(1, 1, 1, 0.055)
			draw_rect(Rect2(p, Vector2(CELL, CELL)), tint, true)
			if jelly.size() == ROWS and jelly[r][c] > 0:
				var a: float = 0.12 if jelly[r][c] == 1 else 0.22
				draw_rect(Rect2(p + Vector2(2, 2), Vector2(CELL - 4, CELL - 4)),
					Color(1.0, 0.58, 0.72, a), true)
				draw_rect(Rect2(p + Vector2(2, 2), Vector2(CELL - 4, CELL - 4)),
					Color(1.0, 0.70, 0.82, 0.35), false, 1.0)


func _update_score() -> void:
	score_label.text = "score  %d" % score
	moves_label.text = "moves  %d" % max(moves_left, 0)
	target_label.text = _goal_text()
	level_label.text = "LEVEL %d/%d" % [level + 1, level_table.size()]
	if keys_label != null:
		keys_label.text = "S SHUFFLE     R RETRY     ESC LEVELS     M MUTE"
	_refresh_shuffle()
	var frac: float = clampf(float(_goal_done()) / float(maxi(_goal_total(), 1)), 0.0, 1.0)
	bar_fill.size = Vector2(512.0 * frac, 6)


func _show_combo(combo: int, gained: int) -> void:
	if combo > 1:
		combo_label.text = "COMBO x%d  +%d" % [combo, gained]
	else:
		combo_label.text = "+%d" % gained
	combo_label.modulate.a = 1.0


func _show_notice(text: String) -> void:
	notice_label.text = text
	notice_label.modulate.a = 1.0


func _hide_notice() -> void:
	create_tween().tween_property(notice_label, "modulate:a", 0.0, 0.4)


func _fade_combo() -> void:
	var t := create_tween()
	t.tween_interval(0.4)
	t.tween_property(combo_label, "modulate:a", 0.0, 0.5)


# --- audio ----------------------------------------------------------------

# one per species, in SPECIES order: seal, penguin, otter, walrus, narwhal, bear
const VOICE_FILES := ["voice_seal.wav", "voice_penguin.wav", "voice_otter.wav",
		"voice_walrus.wav", "voice_narwhal.wav", "voice_bear.wav"]

# The wavs are RMS-normalised to equal loudness, so these are a real mix:
# frequent sounds sit well back, rewards come forward.
const SFX := {
	"move":    ["move.wav",    -22.0],
	"pop":     ["pop.wav",     -15.0],
	"invalid": ["invalid.wav", -20.0],
	"special": ["special.wav", -16.0],
	"combo":   ["combo.wav",   -13.0],
	"shuffle": ["shuffle.wav", -18.0],
}


func _build_audio() -> void:
	for key in SFX:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://assets/audio/" + SFX[key][0])
		p.volume_db = SFX[key][1]
		add_child(p)
		sfx[key] = p
	voice_player = AudioStreamPlayer.new()
	voice_player.volume_db = -15.0
	add_child(voice_player)
	for name in VOICE_FILES:
		voices.append(load("res://assets/audio/" + name))

	music = AudioStreamPlayer.new()
	music.stream = load("res://assets/audio/music.wav")
	music.volume_db = -24.0
	# Godot 4.7's wav importer does not carry edit/loop_mode onto the resource
	# when compress/mode is QOA, so set the loop on the stream directly.
	if music.stream is AudioStreamWAV:
		var w: AudioStreamWAV = music.stream
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	add_child(music)
	music.finished.connect(_restart_music)   # safety net if the loop is lost
	if OS.has_feature("web"):
		return          # wait for a user gesture, see _input()
	music.play()
	music_started = true


func _input(event: InputEvent) -> void:
	# First gesture unlocks the browser's audio context. Buttons consume their
	# own clicks, so this has to be _input, not _unhandled_input.
	if music_started or music == null:
		return
	if event is InputEventMouseButton or event is InputEventKey \
			or event is InputEventScreenTouch:
		music_started = true
		if not muted:
			music.play()


func _restart_music() -> void:
	if not muted:
		music.play()


func _play(key: String, pitch: float = 1.0) -> void:
	var p: AudioStreamPlayer = sfx.get(key)
	if p == null:
		return
	p.pitch_scale = pitch
	p.play()


func _play_voice(s: int) -> void:
	if s < 0 or s >= voices.size() or voice_player == null:
		return
	voice_player.stream = voices[s]
	voice_player.play()


func _toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)
	_show_notice("sound off" if muted else "sound on")
	_hide_notice()


# --- board ----------------------------------------------------------------

func _cell_pos(r: int, c: int) -> Vector2:
	return ORIGIN + Vector2(c * CELL + CELL * 0.5, r * CELL + CELL * 0.5)


func _cell_at(pos: Vector2) -> Vector2i:
	var local := pos - ORIGIN
	var c := int(floor(local.x / CELL))
	var r := int(floor(local.y / CELL))
	if c < 0 or c >= COLS or r < 0 or r >= ROWS:
		return Vector2i(-1, -1)
	if not _is_open(r, c):
		return Vector2i(-1, -1)
	return Vector2i(c, r)


func _in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < COLS and p.y >= 0 and p.y < ROWS


func _spawn(r: int, c: int, s: int) -> AnimatedSprite2D:
	var sp := AnimatedSprite2D.new()
	sp.sprite_frames = frames[s]
	sp.scale = Vector2(2, 2)
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.position = _cell_pos(r, c)
	board_layer.add_child(sp)
	sp.play("idle")
	sp.frame = randi() % IDLE_DUR.size()
	return sp


func _fill_board() -> void:
	for row in pieces:
		for sp in row:
			if sp != null:
				sp.queue_free()
	grid.clear()
	special.clear()
	pieces.clear()
	for r in ROWS:
		grid.append([])
		special.append([])
		pieces.append([])
		for c in COLS:
			grid[r].append(-1)
			special[r].append(SP_NONE)
			pieces[r].append(null)
	for r in ROWS:
		for c in COLS:
			if not _is_open(r, c):
				continue
			var choices: Array = []
			for s in species_count:
				if not _would_match(r, c, s):
					choices.append(s)
			if choices.is_empty():
				choices = range(species_count)
			var s: int = choices[randi() % choices.size()]
			grid[r][c] = s
			pieces[r][c] = _spawn(r, c, s)


func _would_match(r: int, c: int, s: int) -> bool:
	if c >= 2 and grid[r][c - 1] == s and grid[r][c - 2] == s:
		return true
	if r >= 2 and grid[r - 1][c] == s and grid[r - 2][c] == s:
		return true
	return false


# --- match analysis -------------------------------------------------------

func _runs() -> Array:
	var out: Array = []
	if grid.size() < ROWS:
		return out           # no board yet (menu screen)
	for r in ROWS:
		var c := 0
		while c < COLS:
			var s: int = grid[r][c]
			var e := c
			while e + 1 < COLS and s >= 0 and grid[r][e + 1] == s:
				e += 1
			if s >= 0 and e - c + 1 >= 3:
				var cells: Array = []
				for k in range(c, e + 1):
					cells.append(Vector2i(k, r))
				out.append({"cells": cells, "horizontal": true, "species": s})
			c = e + 1
	for c in COLS:
		var r := 0
		while r < ROWS:
			var s: int = grid[r][c]
			var e := r
			while e + 1 < ROWS and s >= 0 and grid[e + 1][c] == s:
				e += 1
			if s >= 0 and e - r + 1 >= 3:
				var cells: Array = []
				for k in range(r, e + 1):
					cells.append(Vector2i(c, k))
				out.append({"cells": cells, "horizontal": false, "species": s})
			r = e + 1
	return out


func _groups() -> Array:
	var runs := _runs()
	var used: Array = []
	used.resize(runs.size())
	used.fill(false)
	var groups: Array = []
	for i in runs.size():
		if used[i]:
			continue
		used[i] = true
		var g := {"runs": [runs[i]], "cells": {}}
		for cell in runs[i]["cells"]:
			g["cells"][cell] = true
		var grew := true
		while grew:
			grew = false
			for j in runs.size():
				if used[j]:
					continue
				for cell in runs[j]["cells"]:
					if g["cells"].has(cell):
						used[j] = true
						g["runs"].append(runs[j])
						for c2 in runs[j]["cells"]:
							g["cells"][c2] = true
						grew = true
						break
		groups.append(g)
	return groups


func _classify(g: Dictionary) -> int:
	var has_h := false
	var has_v := false
	var longest := 0
	for run in g["runs"]:
		var n: int = run["cells"].size()
		if n > longest:
			longest = n
		if run["horizontal"]:
			has_h = true
		else:
			has_v = true
	if has_h and has_v:
		return SP_WRAPPED
	if longest >= 5:
		return SP_BOMB
	if longest == 4:
		return SP_STRIPE_H if g["runs"][0]["horizontal"] else SP_STRIPE_V
	return SP_NONE


func _creation_cell(g: Dictionary, kind: int) -> Vector2i:
	for cell in last_swap:
		if g["cells"].has(cell):
			return cell
	if kind == SP_WRAPPED:
		for a in g["runs"]:
			for b in g["runs"]:
				if a["horizontal"] == b["horizontal"]:
					continue
				for cell in a["cells"]:
					if b["cells"].has(cell):
						return cell
	var best: Array = g["runs"][0]["cells"]
	for run in g["runs"]:
		if run["cells"].size() > best.size():
			best = run["cells"]
	return best[best.size() / 2]


func _find_matches() -> Array:
	var out := {}
	for g in _groups():
		for cell in g["cells"]:
			out[cell] = true
	return out.keys()


# --- specials -------------------------------------------------------------

func _blast(cell: Vector2i, kind: int, bomb_species: int) -> Array:
	var out: Array = []
	if kind == SP_STRIPE_H:
		for c in COLS:
			out.append(Vector2i(c, cell.y))
	elif kind == SP_STRIPE_V:
		for r in ROWS:
			out.append(Vector2i(cell.x, r))
	elif kind == SP_WRAPPED:
		for dr in range(-1, 2):
			for dc in range(-1, 2):
				var p := cell + Vector2i(dc, dr)
				if _in_bounds(p):
					out.append(p)
	elif kind == SP_BOMB:
		for r in ROWS:
			for c in COLS:
				if grid[r][c] == bomb_species:
					out.append(Vector2i(c, r))
	return out


func _expand(seed: Array, bomb_target: int) -> Array:
	var out := {}
	var queue: Array = seed.duplicate()
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		if out.has(cell) or not _in_bounds(cell):
			continue
		if grid[cell.y][cell.x] < 0:
			continue
		out[cell] = true
		var kind: int = special[cell.y][cell.x]
		if kind != SP_NONE:
			var target: int = bomb_target if bomb_target >= 0 else grid[cell.y][cell.x]
			for extra in _blast(cell, kind, target):
				if not out.has(extra):
					queue.append(extra)
	return out.keys()


func _make_special(cell: Vector2i, kind: int, species: int) -> void:
	special[cell.y][cell.x] = kind
	grid[cell.y][cell.x] = species
	_play("special")
	var sp: AnimatedSprite2D = pieces[cell.y][cell.x]
	if sp == null:
		sp = _spawn(cell.y, cell.x, species)
		pieces[cell.y][cell.x] = sp
	sp.sprite_frames = _frames_for(species, kind)
	sp.play("idle")
	if not fast:
		sp.scale = Vector2(2.9, 2.9)
		create_tween().tween_property(sp, "scale", Vector2(2, 2), 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- input ----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_M:
			_toggle_mute()
		elif event.keycode == KEY_F12:
			_save_shot("user://shot.png")
		elif event.keycode == KEY_ESCAPE:
			# step back a screen; quit only from the menu
			if state == ST_PLAY:
				_goto(ST_SELECT)
			elif state == ST_SELECT:
				_goto(ST_MENU)
			elif not OS.has_feature("web"):
				get_tree().quit()
		elif state == ST_PLAY and not busy:
			if event.keycode == KEY_R:
				_restart()
			elif event.keycode == KEY_S:
				_use_shuffle()
			elif event.keycode in [KEY_SPACE, KEY_ENTER] and game_over and won:
				_next_level()
		return
	if state != ST_PLAY or busy or game_over:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_at(event.position)
		if cell.x < 0:
			return
		if selected.x < 0:
			_select(cell)
			return
		_highlight(selected, false)
		var d: int = abs(cell.x - selected.x) + abs(cell.y - selected.y)
		var from := selected
		selected = Vector2i(-1, -1)
		if d == 1:
			_try_swap(from, cell)
		elif cell != from:
			_select(cell)


func _select(cell: Vector2i) -> void:
	selected = cell
	_highlight(cell, true)
	_play_voice(grid[cell.y][cell.x])


func _highlight(cell: Vector2i, on: bool) -> void:
	if cell.x < 0:
		return
	var sp: AnimatedSprite2D = pieces[cell.y][cell.x]
	if sp == null:
		return
	sp.scale = Vector2(2.3, 2.3) if on else Vector2(2, 2)
	sp.modulate = Color(1.3, 1.3, 1.3) if on else Color(1, 1, 1)


func _swap_grid(a: Vector2i, b: Vector2i) -> void:
	# the data half of a swap, without touching sprites - the bot's lookahead
	var g: int = grid[a.y][a.x]
	grid[a.y][a.x] = grid[b.y][b.x]
	grid[b.y][b.x] = g
	var k: int = special[a.y][a.x]
	special[a.y][a.x] = special[b.y][b.x]
	special[b.y][b.x] = k


func _swap_data(a: Vector2i, b: Vector2i) -> void:
	var g: int = grid[a.y][a.x]
	grid[a.y][a.x] = grid[b.y][b.x]
	grid[b.y][b.x] = g
	var k: int = special[a.y][a.x]
	special[a.y][a.x] = special[b.y][b.x]
	special[b.y][b.x] = k
	var p: AnimatedSprite2D = pieces[a.y][a.x]
	pieces[a.y][a.x] = pieces[b.y][b.x]
	pieces[b.y][b.x] = p


func _animate_swap(a: Vector2i, b: Vector2i) -> void:
	var sa: AnimatedSprite2D = pieces[a.y][a.x]
	var sb: AnimatedSprite2D = pieces[b.y][b.x]
	var pa := sa.position
	var pb := sb.position
	if fast:
		sa.position = pb
		sb.position = pa
		return
	var t := create_tween().set_parallel(true)
	t.tween_property(sa, "position", pb, 0.14).set_trans(Tween.TRANS_QUAD)
	t.tween_property(sb, "position", pa, 0.14).set_trans(Tween.TRANS_QUAD)
	await t.finished


func _try_swap(a: Vector2i, b: Vector2i) -> void:
	busy = true
	var spent := true
	_play("move")
	await _animate_swap(a, b)
	_swap_data(a, b)
	last_swap = [a, b]
	var ka: int = special[a.y][a.x]
	var kb: int = special[b.y][b.x]
	if ka != SP_NONE and kb != SP_NONE:
		# two specials combine into one bigger effect
		var cells := _combo_blast(a, b, ka, kb)
		special[a.y][a.x] = SP_NONE
		special[b.y][b.x] = SP_NONE
		_show_notice(_combo_name(ka, kb))
		_play("combo")
		await _resolve(cells, -1)
		_hide_notice()
	elif ka != SP_NONE or kb != SP_NONE:
		# swapping a single special sets it off, match or not
		var seed: Array = []
		var target := -1
		if ka != SP_NONE:
			seed.append(a)
		if kb != SP_NONE:
			seed.append(b)
		if ka == SP_BOMB:
			target = grid[b.y][b.x]
		elif kb == SP_BOMB:
			target = grid[a.y][a.x]
		await _resolve(seed, target)
	elif _find_matches().is_empty():
		spent = false                       # a swap that does nothing is free
		_play("invalid")
		_swap_data(a, b)
		await _animate_swap(a, b)
	else:
		await _resolve()
	last_swap = []
	if spent:
		moves_left -= 1
		_update_score()
	await _settle()
	_check_outcome()
	busy = false


# --- resolution -----------------------------------------------------------

func _pop(cells: Array) -> void:
	if cells.is_empty():
		return
	var total := 0.0
	for d in POP_DUR:
		total += d
	var ate_jelly := false
	for cell in cells:
		var sp: AnimatedSprite2D = pieces[cell.y][cell.x]
		if sp != null:
			sp.scale = Vector2(2, 2)
			sp.modulate = Color(1, 1, 1)
			sp.z_index = 1
			sp.play("pop")
		if jelly.size() == ROWS and jelly[cell.y][cell.x] > 0:
			jelly[cell.y][cell.x] -= 1
			jelly_left -= 1
			ate_jelly = true
		grid[cell.y][cell.x] = -1
		special[cell.y][cell.x] = SP_NONE
	if ate_jelly:
		_refresh_jelly_view()
		queue_redraw()
	if not fast:
		await get_tree().create_timer(total).timeout
	for cell in cells:
		var sp: AnimatedSprite2D = pieces[cell.y][cell.x]
		if sp != null:
			sp.queue_free()
		pieces[cell.y][cell.x] = null


func _collapse() -> void:
	var t: Tween = null
	if not fast:
		t = create_tween().set_parallel(true)
	var moved := false
	for c in COLS:
		# Falling is confined to the column's open span. The contiguity
		# invariant from _build_blocked() is what makes this correct: with no
		# hole inside the span, straight-down compaction never has to route a
		# piece around anything.
		var bottom: int = col_bot[c] if col_bot.size() == COLS else ROWS - 1
		var ceiling: int = col_top[c] if col_top.size() == COLS else 0
		if bottom < 0:
			continue
		var write := bottom
		for r in range(bottom, ceiling - 1, -1):
			if grid[r][c] >= 0:
				if r != write:
					grid[write][c] = grid[r][c]
					special[write][c] = special[r][c]
					pieces[write][c] = pieces[r][c]
					grid[r][c] = -1
					special[r][c] = SP_NONE
					pieces[r][c] = null
					if fast:
						pieces[write][c].position = _cell_pos(write, c)
					else:
						t.tween_property(pieces[write][c], "position",
							_cell_pos(write, c), 0.18) \
							.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
					moved = true
				write -= 1
		var empties := write - ceiling + 1
		for r in range(write, ceiling - 1, -1):
			var s := randi() % species_count
			grid[r][c] = s
			special[r][c] = SP_NONE
			var sp := _spawn(r, c, s)
			pieces[r][c] = sp
			if not fast:
				sp.position = _cell_pos(r, c) - Vector2(0, empties * CELL)
				t.tween_property(sp, "position", _cell_pos(r, c), 0.22) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			moved = true
	if fast:
		return
	if moved:
		await t.finished
	else:
		t.kill()


func _resolve(seed: Array = [], bomb_target: int = -1) -> void:
	var combo := 0
	var pending: Array = seed.duplicate()
	var guard := 0
	while guard < 64:
		guard += 1
		var creations: Array = []
		var clear := {}
		for g in _groups():
			var kind: int = _classify(g)
			var make := Vector2i(-1, -1)
			if kind != SP_NONE:
				make = _creation_cell(g, kind)
				creations.append({"cell": make, "kind": kind, "species": g["runs"][0]["species"]})
			for cell in g["cells"]:
				if cell != make:
					clear[cell] = true
		for cell in pending:
			clear[cell] = true
		pending = []
		if clear.is_empty():
			break
		combo += 1
		var hit := _expand(clear.keys(), bomb_target)
		bomb_target = -1
		# a cell that is turning into a special must survive this blast
		var keep := {}
		for cr in creations:
			keep[cr["cell"]] = true
		var final_cells: Array = []
		for cell in hit:
			if not keep.has(cell):
				final_cells.append(cell)
		if int(goal.get("kind", GOAL_SCORE)) == GOAL_COLLECT:
			var want: int = int(goal["species"])
			for cell in final_cells:
				if grid[cell.y][cell.x] == want:
					collected += 1
		var gained: int = final_cells.size() * 10 * combo
		score += gained
		_update_score()
		_show_combo(combo, gained)
		_play("pop", min(1.0 + 0.09 * (combo - 1), 1.7))
		await _pop(final_cells)
		for cr in creations:
			_make_special(cr["cell"], cr["kind"], cr["species"])
		await _collapse()
	_fade_combo()


# --- special pair combos --------------------------------------------------
#   stripe + stripe   full cross through the swap cell
#   stripe + wrapped  three rows and three columns
#   stripe + bomb     every piece of the partner species fires as a stripe
#   wrapped + wrapped 5x5 blast
#   wrapped + bomb    every piece of the partner species fires as a 3x3
#   bomb + bomb       the whole board

func _combo_name(ka: int, kb: int) -> String:
	var n := {SP_STRIPE_H: "stripe", SP_STRIPE_V: "stripe",
			SP_WRAPPED: "wrapped", SP_BOMB: "bomb"}
	return "%s + %s!" % [n[ka], n[kb]]


func _square(out: Dictionary, centre: Vector2i, radius: int) -> void:
	for dr in range(-radius, radius + 1):
		for dc in range(-radius, radius + 1):
			var p := Vector2i(centre.x + dc, centre.y + dr)
			if _in_bounds(p):
				out[p] = true


func _combo_blast(a: Vector2i, b: Vector2i, ka: int, kb: int) -> Array:
	var stripes := 0
	var wraps := 0
	var bombs := 0
	for k in [ka, kb]:
		if k == SP_STRIPE_H or k == SP_STRIPE_V:
			stripes += 1
		elif k == SP_WRAPPED:
			wraps += 1
		elif k == SP_BOMB:
			bombs += 1
	# a bomb takes the colour of whatever it was combined with
	var target: int = grid[b.y][b.x] if ka == SP_BOMB else grid[a.y][a.x]
	var out := {}
	out[a] = true
	out[b] = true

	if bombs == 2:
		for r in ROWS:
			for c in COLS:
				out[Vector2i(c, r)] = true
	elif bombs == 1 and stripes == 1:
		for r in ROWS:
			for c in COLS:
				if grid[r][c] == target:
					if (r + c) % 2 == 0:
						for cc in COLS:
							out[Vector2i(cc, r)] = true
					else:
						for rr in ROWS:
							out[Vector2i(c, rr)] = true
	elif bombs == 1 and wraps == 1:
		for r in ROWS:
			for c in COLS:
				if grid[r][c] == target:
					_square(out, Vector2i(c, r), 1)
	elif stripes == 2:
		for c in COLS:
			out[Vector2i(c, b.y)] = true
		for r in ROWS:
			out[Vector2i(b.x, r)] = true
	elif stripes == 1 and wraps == 1:
		for d in range(-1, 2):
			var rr: int = b.y + d
			var cc: int = b.x + d
			if rr >= 0 and rr < ROWS:
				for c in COLS:
					out[Vector2i(c, rr)] = true
			if cc >= 0 and cc < COLS:
				for r in ROWS:
					out[Vector2i(cc, r)] = true
	elif wraps == 2:
		_square(out, b, 2)
	return out.keys()


# --- level outcome --------------------------------------------------------

func _goal_total() -> int:
	match int(goal.get("kind", GOAL_SCORE)):
		GOAL_COLLECT: return int(goal["count"])
		GOAL_JELLY:   return int(goal.get("total", 0))
		_:            return int(goal.get("score", 0))


func _goal_done() -> int:
	match int(goal.get("kind", GOAL_SCORE)):
		GOAL_COLLECT: return mini(collected, int(goal["count"]))
		GOAL_JELLY:   return int(goal.get("total", 0)) - jelly_left
		_:            return mini(score, int(goal.get("score", 0)))


func _goal_met() -> bool:
	return _goal_done() >= _goal_total()


func _goal_text() -> String:
	match int(goal.get("kind", GOAL_SCORE)):
		GOAL_COLLECT:
			return "collect %d %s   %d/%d" % [int(goal["count"]),
				SPECIES_NAMES[int(goal["species"])], _goal_done(), int(goal["count"])]
		GOAL_JELLY:
			return "clear the jelly   %d left" % jelly_left
		_:
			return "target  %d" % int(goal.get("score", 0))


func _stars_earned() -> int:
	if int(goal.get("kind", GOAL_SCORE)) == GOAL_SCORE:
		return _stars_for(score)
	# Generated levels carry measured thresholds: moves still in hand for 2
	# and for 3 stars. The classic 30 use the fraction-of-budget rule below.
	var cut: Array = level_table[level].get("stars", [])
	if cut.size() == 2:
		if moves_left >= int(cut[1]):
			return 3
		if moves_left >= int(cut[0]):
			return 2
		return 1
	var budget: float = float(level_table[level]["moves"])
	var left: float = float(maxi(moves_left, 0)) / maxf(budget, 1.0)
	if left >= STAR_3_MOVES:
		return 3
	if left >= STAR_2_MOVES:
		return 2
	return 1


func _stars_for(sc: int) -> int:
	# stars always reflect score, whatever the level's goal is
	var cut: Array = level_table[level].get("stars", []) if level < level_table.size() else []
	if cut.size() == 2 and int(goal.get("kind", GOAL_SCORE)) == GOAL_SCORE:
		if sc >= int(cut[1]):
			return 3
		if sc >= int(cut[0]):
			return 2
		return 1 if sc >= star_base else 0
	if sc >= int(star_base * STAR_3):
		return 3
	if sc >= int(star_base * STAR_2):
		return 2
	if sc >= star_base:
		return 1
	return 0


func _shape_mask(shape: String, extent: float) -> Array:
	"""Board outline as 8 strings: '.' open, '#' blocked.

	Only shapes whose open cells are CONTIGUOUS per column are usable. That
	invariant is what lets pieces keep falling straight down - a hole in the
	middle of a column would split it into regions with no way to refill the
	lower one, which is why real match-3 games route pieces diagonally. A ring
	is the obvious shape this rules out; _build_blocked() rejects any layout
	that breaks it rather than letting it fail silently at runtime.
	"""
	var rows: Array = []
	for r in ROWS:
		var line := ""
		for c in COLS:
			var dx: float = abs(c - (COLS - 1) / 2.0)
			var dy: float = abs(r - (ROWS - 1) / 2.0)
			var open_cell := true
			match shape:
				"floe":
					# dx+dy <= extent: 6.0 shaves the corners (60 of 64 open),
					# 5.0 a rounded floe (52), 4.0 a diamond (40)
					open_cell = dx + dy <= extent
				_:
					if SHAPES.has(shape):
						var prof: Array = SHAPES[shape]
						open_cell = r >= int(prof[0][c]) and r <= int(prof[1][c])
					else:
						open_cell = true
			line += "." if open_cell else "#"
		rows.append(line)
	return rows


func _drift_mask(seed_n: int) -> Array:
	"""A random ragged edge: a few cells nibbled off the top and bottom of the
	columns, never the middle, so it cannot split a column. The walk keeps
	neighbouring columns within one row of each other, which reads as a
	natural floe edge rather than noise. Seeded, so a level never changes."""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n * 7919 + 104729
	for attempt in 50:
		var tops: Array = []
		var bots: Array = []
		var t: int = rng.randi_range(0, 2)
		var b: int = rng.randi_range(6, 7)
		for c in COLS:
			t = clampi(t + rng.randi_range(-1, 1), 0, 2)
			b = clampi(b + rng.randi_range(-1, 1), 6, 7)
			tops.append(t)
			bots.append(b)
		var cut := 0
		for c in COLS:
			cut += int(tops[c]) + (ROWS - 1 - int(bots[c]))
		if cut < 7 or cut > 12:
			continue
		var rows: Array = []
		for r in ROWS:
			var line := ""
			for c in COLS:
				line += "." if r >= int(tops[c]) and r <= int(bots[c]) else "#"
			rows.append(line)
		return rows
	return []


func _mask_open(mask: Array) -> int:
	var n := 0
	for r in ROWS:
		for c in COLS:
			if r >= mask.size() or c >= String(mask[r]).length() \
					or String(mask[r])[c] != "#":
				n += 1
	return n


func _jelly_on_open(layout: Array, mask: Array) -> Array:
	# jelly on a hole could never be cleared, so drop any the mask covers
	if mask.is_empty():
		return layout
	var out: Array = []
	for r in layout.size():
		var line := ""
		for c in String(layout[r]).length():
			var hole: bool = r < mask.size() and c < String(mask[r]).length() \
					and String(mask[r])[c] == "#"
			line += "." if hole else String(layout[r])[c]
		out.append(line)
	return out


func _is_open(r: int, c: int) -> bool:
	if blocked.size() < ROWS:
		return true
	return not blocked[r][c]


func _build_blocked() -> void:
	blocked = []
	for r in ROWS:
		blocked.append([])
		for c in COLS:
			blocked[r].append(false)
	var mask: Array = board_shape
	for r in mini(mask.size(), ROWS):
		var line: String = mask[r]
		for c in mini(line.length(), COLS):
			if line[c] == "#":
				blocked[r][c] = true

	# enforce the contiguity invariant; fall back to a full board if broken
	col_top = []
	col_bot = []
	for c in COLS:
		var first := -1
		var last := -1
		for r in ROWS:
			if not blocked[r][c]:
				if first < 0:
					first = r
				last = r
		var gap := false
		if first >= 0:
			for r in range(first, last + 1):
				if blocked[r][c]:
					gap = true
		if gap:
			push_warning("board shape splits column %d; falling back to a full board" % c)
			_build_blocked_full()
			return
		col_top.append(first)
		col_bot.append(last)


func _build_blocked_full() -> void:
	blocked = []
	col_top = []
	col_bot = []
	for r in ROWS:
		blocked.append([])
		for c in COLS:
			blocked[r].append(false)
	for c in COLS:
		col_top.append(0)
		col_bot.append(ROWS - 1)


func _jelly_pattern(shape: String, extent: float) -> Array:
	"""Builds an 8-string jelly layout. Generated rather than typed so jelly
	levels scale with the curve instead of needing a new hand-drawn layout."""
	var rows: Array = []
	for r in ROWS:
		var line := ""
		for c in COLS:
			var dx: float = abs(c - (COLS - 1) / 2.0)
			var dy: float = abs(r - (ROWS - 1) / 2.0)
			var inside := false
			match shape:
				"block":
					inside = dx <= extent and dy <= extent
				"diamond":
					inside = dx + dy <= extent * 1.4
				"octagon":
					inside = dx <= extent and dy <= extent and dx + dy <= extent * 1.55
				"ring":
					inside = max(dx, dy) <= extent and max(dx, dy) > extent - 1.5
				"cross":
					inside = (dx <= 1.0 or dy <= 1.0) and dx <= extent and dy <= extent
				_:
					inside = dx <= extent and dy <= extent
			line += "1" if inside else "."
		rows.append(line)
	return rows


func _layout_cells(rows: Array) -> int:
	var n := 0
	for line in rows:
		for ch in line:
			if ch == "1" or ch == "2":
				n += int(ch)
	return n


func _design_spec(n: int, mag: float = 1.0) -> Dictionary:
	"""What level n (1-based) asks of the player, before calibration.

	This decides the goal and its size; it does NOT decide difficulty. The
	bake plays the level with the bot and sets the move budget so that it
	clears as often as _want_clear(n) says. So magnitudes here can simply
	climb and level off - the numbers on the map go up - without the curve
	having to guess how hard that makes the level. `mag` lets the bake
	resize the goal when the budget it finds falls outside MOVES_MIN..MAX.
	"""
	var idx: int = n - 1
	var chapter: int = idx / CHAPTER
	var step: int = idx % CHAPTER
	# 0 at level 1, about 0.75 by level 100: growth that levels off
	var grow: float = 1.0 - exp(-float(idx) / 70.0)

	# one in four is a score level, the rest alternate collect and jelly
	var kind: int = GOAL_SCORE
	if step % 4 == 1:
		kind = GOAL_COLLECT
	elif step % 4 == 3:
		kind = GOAL_JELLY

	var spec := {"species": SPECIES, "source": "generated"}
	# Every third level gets a named outline. From DRIFT_FROM_CHAPTER on, the
	# levels in between (bar each chapter's opener) get a random ragged edge.
	var mask: Array = []
	if step % 3 == 2:
		var shape_name: String = SHAPE_ORDER[(chapter * 3 + step / 3) % SHAPE_ORDER.size()]
		mask = _shape_mask(shape_name, 5.0)
	elif step % 3 == 1 and chapter >= DRIFT_FROM_CHAPTER:
		mask = _drift_mask(n)
	if not mask.is_empty():
		spec["shape"] = mask
	# a smaller board asks for less, so budgets stay comparable
	var area: float = float(_mask_open(mask)) / float(ROWS * COLS)
	var fit: float = mag * area

	match kind:
		GOAL_COLLECT:
			var count: int = maxi(int(round((14.0 + 14.0 * grow) * fit)), 8)
			spec["goal"] = {"kind": GOAL_COLLECT, "species": idx % SPECIES, "count": count}
		GOAL_JELLY:
			# fit the shape's extent to the wanted cell count: shapes vary
			# hugely in area at the same extent
			var shapes := ["block", "octagon", "diamond", "cross", "ring"]
			var shape: String = shapes[(idx / 4) % shapes.size()]
			var want: int = maxi(int(round((16.0 + 16.0 * grow) * fit)), 8)
			var layout: Array = _jelly_on_open(_jelly_pattern(shape, 2.0), mask)
			var best_gap: int = 9999
			for tenths in range(40, 141, 5):            # extent 1.00 .. 3.50
				var trial: Array = _jelly_on_open(_jelly_pattern(shape, tenths / 40.0), mask)
				var gap: int = absi(_layout_cells(trial) - want)
				if gap < best_gap:
					best_gap = gap
					layout = trial
			spec["goal"] = {"kind": GOAL_JELLY, "layout": layout}
		_:
			var target: int = int(round((1150.0 + 700.0 * grow) * fit / 50.0) * 50)
			spec["goal"] = {"kind": GOAL_SCORE, "score": target}
	var g: Dictionary = spec["goal"]
	spec["star_base"] = int(g.get("score", 0)) if kind == GOAL_SCORE \
			else int(round((1150.0 + 700.0 * grow) / 50.0) * 50)
	# a placeholder budget; the bake replaces it with a measured one
	spec["moves"] = 20
	return spec


func _want_clear(n: int) -> float:
	"""How often the bot should clear level n on its budget. Each chapter opens
	easy, sawtooths, and ends on a harder finale; across chapters the middle
	of that range drifts down and then levels off, so the game firms up
	without ever turning into a grind."""
	var idx: int = n - 1
	var chapter: int = idx / CHAPTER
	var step: int = idx % CHAPTER
	var ramp: float = clampf(float(chapter) / CLEAR_RAMP_CHAPTERS, 0.0, 1.0)
	var base: float = lerpf(CLEAR_START, CLEAR_FLOOR, ramp)
	return clampf(base + float(STEP_EASE[step]), 0.45, 0.97)


func _build_levels() -> void:
	"""Levels are data: data/levels.json, written by `-- bake`. The first 30
	are the original hand-tuned and curve-built levels, frozen as they were
	played; everything after is generated by _design_spec and calibrated by
	the bot. Without the file the game still runs on uncalibrated specs."""
	level_table = _read_level_file(LEVELS_PATH)
	if level_table.is_empty():
		push_warning("no level file at %s - using uncalibrated levels" % LEVELS_PATH)
		for n in range(1, CHAPTER * 3 + 1):
			level_table.append(_design_spec(n))


func _load_level(i: int) -> void:
	level = clampi(i, 0, level_table.size() - 1)
	var cfg: Dictionary = level_table[level]
	species_count = cfg.get("species", SPECIES)
	moves_left = cfg["moves"]
	star_base = cfg["star_base"]
	goal = (cfg["goal"] as Dictionary).duplicate(true)
	board_shape = cfg.get("shape", [])
	target = int(goal.get("score", star_base))
	collected = 0
	shuffles_left = SHUFFLES_PER_LEVEL
	_build_blocked()
	_build_jelly()
	score = 0
	stars = 0
	game_over = false
	won = false
	selected = Vector2i(-1, -1)
	_hide_result()
	_update_score()
	_fill_board()


func _refresh_jelly_view() -> void:
	for ch in jelly_layer.get_children():
		ch.queue_free()
	if jelly.size() < ROWS:
		return
	var w := float(CELL - 6)
	for r in ROWS:
		for c in COLS:
			if jelly[r][c] <= 0:
				continue
			var pg := Polygon2D.new()
			pg.polygon = PackedVector2Array([Vector2(0, 0), Vector2(w, 0),
					Vector2(w, w), Vector2(0, w)])
			pg.position = ORIGIN + Vector2(c * CELL + 3, r * CELL + 3)
			pg.color = Color(1.0, 0.56, 0.74, 0.26 if jelly[r][c] == 1 else 0.46)
			jelly_layer.add_child(pg)


func _build_jelly() -> void:
	jelly = []
	jelly_left = 0
	for r in ROWS:
		jelly.append([])
		for c in COLS:
			jelly[r].append(0)
	if int(goal.get("kind", GOAL_SCORE)) != GOAL_JELLY:
		_refresh_jelly_view()
		return
	var rows: Array = goal["layout"]
	for r in mini(rows.size(), ROWS):
		var line: String = rows[r]
		for c in mini(line.length(), COLS):
			var ch := line[c]
			if (ch == "1" or ch == "2") and _is_open(r, c):
				var n := int(ch)
				jelly[r][c] = n
				jelly_left += n
	goal["total"] = jelly_left
	_refresh_jelly_view()


func _hide_result() -> void:
	overlay.visible = false
	result_label.visible = false
	result_sub.visible = false
	if result_go != null:
		result_go.visible = false
		result_retry.visible = false
	for n in star_nodes:
		n.visible = false


func _check_outcome() -> void:
	if game_over or no_finish:
		return
	# A collect or jelly goal has nothing left to do once met, so it ends.
	# A score goal does not: the target is the pass mark, and the remaining
	# moves are how you reach 2 and 3 stars. Ending on the target made those
	# unreachable except by overshooting in a final cascade.
	var kind: int = int(goal.get("kind", GOAL_SCORE))
	if _goal_met() and kind != GOAL_SCORE:
		_finish(true)
	elif moves_left <= 0:
		_finish(_goal_met())


func _finish(did_win: bool) -> void:
	game_over = true
	won = did_win
	stars = maxi(1, _stars_earned()) if won else 0
	selected = Vector2i(-1, -1)
	if won:
		best[level] = maxi(int(best.get(level, 0)), stars)
		_save_progress()
	if ui_font != null:
		result_label.add_theme_font_override("font", ui_font)
	result_label.text = "LEVEL CLEARED!" if won else "OUT OF MOVES"
	result_label.add_theme_color_override("font_color",
		Color("9fe3ff") if won else Color("ff95bb"))
	if won and level + 1 >= level_table.size():
		result_sub.text = "score %d          all levels cleared!" % score
	elif won:
		result_sub.text = "score %d" % score
	else:
		result_sub.text = "score %d of %d" % [score, target]
	overlay.visible = true
	result_label.visible = true
	result_sub.visible = true
	result_go.visible = true
	result_retry.visible = true
	for i in 3:
		star_nodes[i].texture = star_full if i < stars else star_empty
		star_nodes[i].visible = won
	_play("combo" if won else "invalid")


func _load_progress() -> void:
	var cf := ConfigFile.new()
	var loaded: bool = cf.load(SAVE_PATH) == OK
	for i in level_table.size():
		best[i] = int(cf.get_value("stars", str(i), 0)) if loaded else 0


func _save_progress() -> void:
	var cf := ConfigFile.new()
	for i in level_table.size():
		cf.set_value("stars", str(i), int(best.get(i, 0)))
	cf.save(SAVE_PATH)


func _all_moves() -> Array:
	# every legal swap, for the balance harness - picking the first one found
	# biases play toward the top-left and is not a fair model of naive play
	var out: Array = []
	for r in ROWS:
		for c in COLS:
			if not _is_open(r, c):
				continue
			if c + 1 < COLS and _is_open(r, c + 1) \
					and (special[r][c] != SP_NONE or special[r][c + 1] != SP_NONE
					or _swap_makes_match(Vector2i(c, r), Vector2i(c + 1, r))):
				out.append([Vector2i(c, r), Vector2i(c + 1, r)])
			if r + 1 < ROWS and _is_open(r + 1, c) \
					and (special[r][c] != SP_NONE or special[r + 1][c] != SP_NONE
					or _swap_makes_match(Vector2i(c, r), Vector2i(c, r + 1))):
				out.append([Vector2i(c, r), Vector2i(c, r + 1)])
	return out


func _find_any_move() -> Array:
	# first legal swap found - used by the balance harness, and the basis for
	# a hint button if one is ever wanted
	for r in ROWS:
		for c in COLS:
			if special[r][c] != SP_NONE and c + 1 < COLS:
				return [Vector2i(c, r), Vector2i(c + 1, r)]
			if c + 1 < COLS and _swap_makes_match(Vector2i(c, r), Vector2i(c + 1, r)):
				return [Vector2i(c, r), Vector2i(c + 1, r)]
			if r + 1 < ROWS and _swap_makes_match(Vector2i(c, r), Vector2i(c, r + 1)):
				return [Vector2i(c, r), Vector2i(c, r + 1)]
	return []


# --- deadlock detection and reshuffle -------------------------------------

func _swap_makes_match(a: Vector2i, b: Vector2i) -> bool:
	if not _is_open(a.y, a.x) or not _is_open(b.y, b.x):
		return false
	var ga: int = grid[a.y][a.x]
	var gb: int = grid[b.y][b.x]
	if ga == gb:
		return false
	grid[a.y][a.x] = gb
	grid[b.y][b.x] = ga
	var hit: bool = not _find_matches().is_empty()
	grid[a.y][a.x] = ga
	grid[b.y][b.x] = gb
	return hit


func _has_legal_move() -> bool:
	if grid.size() < ROWS:
		return true
	# any special is itself a move: swapping one always sets it off
	for r in ROWS:
		for c in COLS:
			if _is_open(r, c) and special[r][c] != SP_NONE:
				return true
	for r in ROWS:
		for c in COLS:
			if not _is_open(r, c):
				continue
			if c + 1 < COLS and _swap_makes_match(Vector2i(c, r), Vector2i(c + 1, r)):
				return true
			if r + 1 < ROWS and _swap_makes_match(Vector2i(c, r), Vector2i(c, r + 1)):
				return true
	return false


func _arrange(cells: Array, bag: Array) -> void:
	# Greedy placement in row-major order, same rule as the initial fill:
	# prefer a species that does not complete a run with the cells already
	# placed to the left and above. Random reshuffles of a low-variety board
	# almost always contain a ready-made match, this almost never does.
	var pool: Array = bag.duplicate()
	pool.shuffle()
	for cell in cells:
		var pick := -1
		for i in pool.size():
			if not _would_match(cell.y, cell.x, pool[i]):
				pick = i
				break
		if pick < 0:
			pick = 0
		grid[cell.y][cell.x] = pool[pick]
		pool.remove_at(pick)


func _refresh_shuffle() -> void:
	if shuffle_button == null:
		return
	shuffle_button.text = "SHUFFLE" if shuffles_left > 0 else "SHUFFLE USED"
	shuffle_button.disabled = busy or game_over or shuffles_left <= 0


func _use_shuffle() -> bool:
	# A free rearrange that costs no move and keeps score and progress. The
	# board is reshuffled by the same routine the deadlock rescue uses, so the
	# result is still match-free and still has a legal move.
	if busy or game_over or shuffles_left <= 0:
		return false
	busy = true
	shuffles_left -= 1
	_update_score()
	var done: bool = await _reshuffle("shuffling the board")
	if not done:
		shuffles_left += 1      # could not arrange one; do not charge for it
	await _settle()
	busy = false
	_update_score()
	return done


func _reshuffle(notice: String = "no moves - shuffling") -> bool:
	# Shuffle the plain pieces in place, keeping the species multiset, until the
	# board has no ready-made match but does have at least one legal move.
	var cells: Array = []
	var bag: Array = []
	for r in ROWS:
		for c in COLS:
			if special[r][c] == SP_NONE and grid[r][c] >= 0:
				cells.append(Vector2i(c, r))
				bag.append(grid[r][c])
	if cells.size() < 2:
		return false
	var found := false
	for attempt in 30:
		_arrange(cells, bag)
		if _find_matches().is_empty() and _has_legal_move():
			found = true
			break
	if not found:
		return false
	if fast:
		for cell in cells:
			pieces[cell.y][cell.x].sprite_frames = frames[grid[cell.y][cell.x]]
		return true
	_show_notice(notice)
	_play("shuffle")
	var out := create_tween().set_parallel(true)
	for cell in cells:
		out.tween_property(pieces[cell.y][cell.x], "scale", Vector2(0.2, 0.2), 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await out.finished
	for cell in cells:
		var sp: AnimatedSprite2D = pieces[cell.y][cell.x]
		sp.sprite_frames = frames[grid[cell.y][cell.x]]
		sp.play("idle")
		sp.frame = randi() % IDLE_DUR.size()
	var back := create_tween().set_parallel(true)
	for cell in cells:
		back.tween_property(pieces[cell.y][cell.x], "scale", Vector2(2, 2), 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await back.finished
	_hide_notice()
	return true


func _settle() -> void:
	# Resolve anything outstanding, then guarantee the board is playable.
	var guard := 0
	while guard < 20:
		guard += 1
		if not _find_matches().is_empty():
			await _resolve()
			continue
		if _has_legal_move():
			return
		var shuffled: bool = await _reshuffle()
		if not shuffled:
			_fill_board()


func _restart() -> void:
	busy = true
	_load_level(level)
	await _settle()
	busy = false


func _next_level() -> void:
	# Clearing a level returns to the map rather than diving straight into the
	# next one: the stars just banked, the progress toward the gate ahead and
	# the choice of what to replay are all on that screen.
	_goto_select_at(mini(level + 1, level_table.size() - 1))


# --- dev harnesses --------------------------------------------------------

func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)


func _auto_shot() -> void:
	await _start_level(0)
	await get_tree().create_timer(0.5).timeout
	await _save_shot("user://shot.png")
	get_tree().quit()


func _shot_pop() -> void:
	await _start_level(0)
	await get_tree().create_timer(0.4).timeout
	_force_triple()
	_resolve()
	await get_tree().create_timer(0.22).timeout
	await _save_shot("user://shot_pop.png")
	get_tree().quit()


func _shot_special() -> void:
	await _start_level(0)
	await get_tree().create_timer(0.3).timeout
	_make_special(Vector2i(1, 1), SP_STRIPE_H, 0)
	_make_special(Vector2i(3, 1), SP_STRIPE_V, 1)
	_make_special(Vector2i(5, 1), SP_WRAPPED, 2)
	_make_special(Vector2i(7, 1), SP_BOMB, 3)
	_make_special(Vector2i(2, 3), SP_STRIPE_V, 4)
	_make_special(Vector2i(5, 3), SP_WRAPPED, 5)
	score = 1240
	_update_score()
	_show_combo(4, 880)
	await get_tree().create_timer(0.45).timeout
	await _save_shot("user://shot_special.png")
	get_tree().quit()


func _shot_shape() -> void:
	# dev: every shaped level, one shot each (shot_shape_<n>.png)
	for i in level_table.size():
		if (level_table[i].get("shape", []) as Array).is_empty():
			continue
		await _start_level(i)
		await get_tree().create_timer(0.4).timeout
		await _save_shot("user://shot_shape_%d.png" % (i + 1))
	music.stop()
	get_tree().quit()


func _shot_jelly() -> void:
	await _start_level(3)
	score = 930
	_update_score()
	_show_combo(4, 880)
	await get_tree().create_timer(0.4).timeout
	await _save_shot("user://shot_jelly.png")
	music.stop()
	get_tree().quit()


func _shot_menu() -> void:
	await get_tree().create_timer(0.5).timeout
	await _save_shot("user://shot_menu.png")
	music.stop()
	get_tree().quit()


func _shot_select() -> void:
	best[0] = 3
	best[1] = 2
	best[2] = 1
	_goto(ST_SELECT)
	await get_tree().create_timer(0.4).timeout
	await _save_shot("user://shot_select.png")
	music.stop()
	get_tree().quit()


func _shot_play() -> void:
	# dev: PLAY from the menu lands on the map at the level you are up to
	for i in 12:
		best[i] = 2
	_goto(ST_MENU)
	await get_tree().create_timer(0.3).timeout
	menu_play.pressed.emit()
	await get_tree().create_timer(0.4).timeout
	await _save_shot("user://shot_play.png")
	music.stop()
	get_tree().quit()


func _shot_hud() -> void:
	# dev: the play HUD with the free reshuffle ready, then spent
	await _start_level(0)
	await _settle()
	_update_score()
	await get_tree().create_timer(0.3).timeout
	await _save_shot("user://shot_hud.png")
	await _use_shuffle()
	await get_tree().create_timer(0.3).timeout
	await _save_shot("user://shot_hud_used.png")
	music.stop()
	get_tree().quit()


func _shot_map() -> void:
	# dev: the map far along - every level up to `at=N` (default 75) cleared
	var at := 75
	for a in OS.get_cmdline_user_args():
		if a.begins_with("at="):
			at = int(a.substr(3))
	for i in at - 1:
		best[i] = 2
	await get_tree().create_timer(0.3).timeout
	_goto_select_at(_focus_level())
	await get_tree().create_timer(0.6).timeout
	await _save_shot("user://shot_map.png")
	music.stop()
	get_tree().quit()


func _shot_seal() -> void:
	# dev: the seal crossing the first gate as it opens. 9 stars before level
	# 10, then a 3-star clear brings the total to the toll of 13. Frames go to
	# shot_seal_NN.png for stitching into a GIF.
	best = {}
	for i in 9:
		best[i] = 1
	best[0] = 2
	await get_tree().create_timer(0.3).timeout     # let the map lay out first
	_goto_select_at(_focus_level())
	await get_tree().create_timer(0.5).timeout
	await _save_shot("user://shot_seal_before.png")
	best[9] = 3
	_goto(ST_MENU)
	_goto_select_at(10)
	for f in 60:
		await get_tree().create_timer(0.04).timeout
		await _save_shot("user://shot_seal_%02d.png" % f)
	while token_hopping:
		await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	await _save_shot("user://shot_seal_after.png")
	music.stop()
	get_tree().quit()


func _shot_gate() -> void:
	# dev: the first star gate, half paid, with the chapter boundary in frame
	for i in CHAPTER:
		best[i] = 1
	_goto(ST_SELECT)
	await get_tree().create_timer(0.4).timeout
	map_scroll.scroll_vertical = int(gate_marks[0]["cap"].position.y - 190.0)
	await get_tree().create_timer(0.3).timeout
	await _save_shot("user://shot_gate.png")
	for i in CHAPTER:
		best[i] = 2                                  # and again with it paid
	_refresh_select()
	await get_tree().create_timer(0.3).timeout
	await _save_shot("user://shot_gate_open.png")
	music.stop()
	get_tree().quit()


func _shot_win() -> void:
	await _start_level(0)
	await get_tree().create_timer(0.4).timeout
	score = 1340
	moves_left = 3
	_update_score()
	_finish(true)
	await get_tree().create_timer(0.35).timeout
	await _save_shot("user://shot_win.png")
	music.stop()
	get_tree().quit()


func _print_levels() -> void:
	# dev: see the whole generated curve at a glance, for tuning
	print("  n  sp  mv  star  holes  goal")
	for i in level_table.size():
		var cfg: Dictionary = level_table[i]
		var holes := 0
		for line in cfg.get("shape", []):
			holes += line.count("#")
		var note := "   (classic)"
		if cfg.has("cal"):
			note = "   want %.2f  bot %.2f  stars %.2f" % [float(cfg["cal"]["want"]),
					float(cfg["cal"]["bot"]), float(cfg["cal"]["stars"])]
		print("%3d  %2d  %2d  %5d  %5s  %-10s%s" % [i + 1, int(cfg.get("species", SPECIES)),
				int(cfg["moves"]), int(cfg["star_base"]),
				"-" if holes == 0 else str(holes), _level_summary(i), note])
	get_tree().quit()


func _level_to_data(cfg: Dictionary) -> Dictionary:
	# a level as it is stored: plain ints and strings, nothing derived
	var g: Dictionary = cfg["goal"]
	var goal_out := {"kind": ["score", "collect", "jelly"][int(g["kind"])]}
	match int(g["kind"]):
		GOAL_SCORE:
			goal_out["score"] = int(g["score"])
		GOAL_COLLECT:
			goal_out["species"] = SPECIES_SHORT[int(g["species"])]
			goal_out["count"] = int(g["count"])
		GOAL_JELLY:
			goal_out["layout"] = (g["layout"] as Array).duplicate()
	var out := {"species": int(cfg.get("species", SPECIES)), "moves": int(cfg["moves"]),
			"star_base": int(cfg["star_base"]), "goal": goal_out}
	if not (cfg.get("shape", []) as Array).is_empty():
		out["shape"] = (cfg["shape"] as Array).duplicate()
	for k in ["stars", "source", "cal"]:
		if cfg.has(k):
			out[k] = cfg[k]
	return out


func _level_from_data(d: Dictionary) -> Dictionary:
	var g: Dictionary = d["goal"]
	var kind: int = ["score", "collect", "jelly"].find(String(g["kind"]))
	var goal_in := {"kind": kind}
	match kind:
		GOAL_SCORE:
			goal_in["score"] = int(g["score"])
		GOAL_COLLECT:
			goal_in["species"] = SPECIES_SHORT.find(String(g["species"]))
			goal_in["count"] = int(g["count"])
		GOAL_JELLY:
			goal_in["layout"] = Array(g["layout"])
	var cfg := {"species": int(d.get("species", SPECIES)), "moves": int(d["moves"]),
			"star_base": int(d["star_base"]), "goal": goal_in}
	if d.has("shape"):
		cfg["shape"] = Array(d["shape"])
	if d.has("stars"):
		cfg["stars"] = [int(d["stars"][0]), int(d["stars"][1])]
	for k in ["source", "cal"]:
		if d.has(k):
			cfg[k] = d[k]
	return cfg


func _read_level_file(path: String) -> Array:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return []
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary) or not parsed.has("levels"):
		push_error("level file %s did not parse" % path)
		return []
	var out: Array = []
	for d in parsed["levels"]:
		out.append(_level_from_data(d))
	return out


func _write_level_file(table: Array, path: String) -> void:
	var levels: Array = []
	for cfg in table:
		levels.append(_level_to_data(cfg))
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "levels": levels}, "\t", false) + "\n")
	f.close()
	print("[levels] wrote %d levels to %s" % [levels.size(), path])


func _bake() -> void:
	"""Extends the level file to `count=N` levels (default 100). Only levels
	not already in the file are made, so a level never changes once baked;
	`from=N` re-bakes from level N on, for when the curve itself changes.
	The file is rewritten after every level, so an interrupted bake resumes
	where it stopped."""
	var count := 100
	var trials := BAKE_TRIALS
	var from := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("count="):
			count = int(a.substr(6))
		elif a.begins_with("trials="):
			trials = int(a.substr(7))
		elif a.begins_with("from="):
			from = int(a.substr(5))
	if from > 0:
		level_table.resize(mini(level_table.size(), from - 1))
	await _start_level(0)
	fast = true
	no_finish = true
	var cal = preload("res://scripts/calibrate.gd").new(self)
	var t0: int = Time.get_ticks_msec()
	print("  n  kind     goal        mv  want  bot  stars  mag")
	var kinds := {GOAL_SCORE: "score", GOAL_COLLECT: "collect", GOAL_JELLY: "jelly"}
	for n in range(level_table.size() + 1, count + 1):
		var spec: Dictionary = await cal.calibrate(n, trials)
		var c: Dictionary = spec["cal"]
		print("%3d  %-8s %-10s  %2d  %.2f  %.2f  %.2f  %.2f" % [n,
				kinds[int(spec["goal"]["kind"])], _level_summary(n - 1),
				int(spec["moves"]), c["want"], c["bot"], c["stars"], c["mag"]])
		_write_level_file(level_table, LEVELS_PATH)
	print("[bake] %d levels in the file, %.0fs" % [level_table.size(),
			(Time.get_ticks_msec() - t0) / 1000.0])
	fast = false
	no_finish = false
	music.stop()
	get_tree().quit()


func _bot_check() -> void:
	"""How the greedy bot does on every level as it stands: clear rate on the
	level's own budget, and the median move on which it met the goal."""
	await _start_level(0)
	fast = true
	no_finish = true
	var cal = preload("res://scripts/calibrate.gd").new(self)
	var trials := 30
	for a in OS.get_cmdline_user_args():
		if a.begins_with("trials="):
			trials = int(a.substr(7))
	var t0: int = Time.get_ticks_msec()
	print("  n  kind     mv  goal        bot clear  med reach  stars")
	var star_sum := 0.0
	var kinds := {GOAL_SCORE: "score", GOAL_COLLECT: "collect", GOAL_JELLY: "jelly"}
	for i in level_table.size():
		var games: Array = []
		for t in trials:
			games.append(await cal.play(i))
		var reach: Array = []
		for g in games:
			reach.append(int(g["reached"]) if int(g["reached"]) > 0 else 999)
		reach.sort()
		var budget: int = int(level_table[i]["moves"])
		var st: float = cal.stars(games, budget, int(level_table[i]["goal"]["kind"]),
				level_table[i].get("stars", []))
		star_sum += st
		print("%3d  %-8s %2d  %-10s  %5.0f%%     %3d     %.2f" % [i + 1,
				kinds[int(level_table[i]["goal"]["kind"])], budget, _level_summary(i),
				100.0 * cal.clear_rate(games, budget), reach[reach.size() / 2], st])
		if (i + 1) % CHAPTER == 0:
			print("     chapter %d: %.2f stars a level (the next gate asks %.1f)"
					% [(i + 1) / CHAPTER, star_sum / CHAPTER, CHAPTER_GATE])
			star_sum = 0.0
	print("[botcheck] %d levels x %d games in %.1fs" % [level_table.size(), trials,
			(Time.get_ticks_msec() - t0) / 1000.0])
	fast = false
	no_finish = false
	music.stop()
	get_tree().quit()


func _balance() -> void:
	"""Samples the generated curve: plays random legal moves with animation
	skipped and reports, per level, the median score, the median goal progress
	and - the figure that actually matters - how often random play clears it.

	Random play is a weak proxy for a human, much weaker on jelly than on
	score, so a clear rate near zero means the level is unreachable and a rate
	near one means it is trivial. Somewhere in between is the target."""
	await _start_level(0)
	fast = true
	no_finish = true
	var trials := 20
	var stride: int = maxi(level_table.size() / 8, 1)
	if OS.get_cmdline_user_args().has("all"):
		stride = 1
	print("  n  kind     mv  goal     score med  goal med  cleared")
	for i in range(0, level_table.size(), stride):
		var cfg: Dictionary = level_table[i]
		var budget: int = int(cfg["moves"])
		var scores: Array = []
		var goals: Array = []
		var cleared := 0
		for trial in trials:
			_load_level(i)
			await _settle()
			for m in budget:
				var opts := _all_moves()
				if opts.is_empty():
					break
				var mv: Array = opts[randi() % opts.size()]
				await _try_swap(mv[0], mv[1])
			scores.append(score)
			goals.append(collected if int(goal["kind"]) == GOAL_COLLECT
					else _goal_done())
			if _goal_met():
				cleared += 1
			await get_tree().process_frame
		scores.sort()
		goals.sort()
		var kinds := {GOAL_SCORE: "score", GOAL_COLLECT: "collect", GOAL_JELLY: "jelly"}
		print("%3d  %-8s %2d  %-7s  %6d     %4d      %2d/%d"
				% [i + 1, kinds[int(level_table[i]["goal"]["kind"])], budget,
				_level_summary(i), scores[scores.size() / 2],
				goals[goals.size() / 2], cleared, trials])
	fast = false
	no_finish = false
	music.stop()
	get_tree().quit()


func _shot_combo() -> void:
	await _start_level(0)
	await get_tree().create_timer(0.35).timeout
	var A := Vector2i(3, 4)
	var B := Vector2i(4, 4)
	_make_special(A, SP_STRIPE_H, grid[A.y][A.x])
	_make_special(B, SP_BOMB, grid[B.y][B.x])
	await get_tree().create_timer(0.3).timeout
	var cells := _combo_blast(A, B, SP_STRIPE_H, SP_BOMB)
	special[A.y][A.x] = SP_NONE
	special[B.y][B.x] = SP_NONE
	_show_notice(_combo_name(SP_STRIPE_H, SP_BOMB))
	_resolve(cells, -1)
	await get_tree().create_timer(0.2).timeout
	await _save_shot("user://shot_combo.png")
	get_tree().quit()


func _shot_shuffle() -> void:
	await _start_level(0)
	await get_tree().create_timer(0.3).timeout
	for r in ROWS:
		for c in COLS:
			grid[r][c] = (r + c) % 3
			special[r][c] = SP_NONE
			pieces[r][c].sprite_frames = frames[grid[r][c]]
	_settle()
	await get_tree().create_timer(0.12).timeout
	await _save_shot("user://shot_shuffle.png")
	get_tree().quit()


func _force_triple() -> int:
	var s: int = grid[0][0]
	for c in 3:
		grid[0][c] = s
		pieces[0][c].sprite_frames = frames[s]
	return s


# diagonal fill: no two neighbours share a species, so nothing matches
func _reset_flat() -> void:
	_build_jelly()
	for r in ROWS:
		for c in COLS:
			grid[r][c] = (r + c) % SPECIES
			special[r][c] = SP_NONE


func _plant(r: int, c: int, n: int, s: int, horizontal: bool) -> void:
	for k in n:
		if horizontal:
			grid[r][c + k] = s
		else:
			grid[r + k][c] = s


func _group_at(cell: Vector2i) -> Dictionary:
	for g in _groups():
		if g["cells"].has(cell):
			return g
	return {}


func _count_special(kind: int) -> int:
	var n := 0
	for r in ROWS:
		for c in COLS:
			if special[r][c] == kind:
				n += 1
	return n


func _check(name: String, got, want) -> bool:
	var ok: bool = got == want
	print("[%s] %-22s got=%s want=%s" % ["PASS" if ok else "FAIL", name, str(got), str(want)])
	return ok


func _token_settled() -> void:
	# waits out a hop (and the gate sinks it triggers), up to a few seconds
	var t: int = Time.get_ticks_msec()
	while token_hopping and Time.get_ticks_msec() - t < 5000:
		await get_tree().process_frame
	await get_tree().create_timer(GATE_SINK_SECS + 0.3).timeout


func _selftest() -> void:
	await _start_level(0)
	await get_tree().process_frame
	var ok := true

	# classification
	_reset_flat()
	_plant(3, 2, 4, 0, true)
	ok = _check("classify_4h", _classify(_group_at(Vector2i(2, 3))), SP_STRIPE_H) and ok

	_reset_flat()
	_plant(1, 3, 4, 0, false)
	ok = _check("classify_4v", _classify(_group_at(Vector2i(3, 1))), SP_STRIPE_V) and ok

	_reset_flat()
	_plant(3, 1, 5, 0, true)
	ok = _check("classify_5h", _classify(_group_at(Vector2i(1, 3))), SP_BOMB) and ok

	# L shape: a horizontal run and a vertical run sharing a corner
	_reset_flat()
	_plant(3, 2, 3, 0, true)
	_plant(3, 2, 3, 0, false)
	ok = _check("classify_L", _classify(_group_at(Vector2i(2, 3))), SP_WRAPPED) and ok

	# blast shapes
	_reset_flat()
	special[4][4] = SP_STRIPE_H
	ok = _check("blast_stripe_h", _expand([Vector2i(4, 4)], -1).size(), COLS) and ok

	_reset_flat()
	special[4][4] = SP_STRIPE_V
	ok = _check("blast_stripe_v", _expand([Vector2i(4, 4)], -1).size(), ROWS) and ok

	_reset_flat()
	special[4][4] = SP_WRAPPED
	ok = _check("blast_wrapped", _expand([Vector2i(4, 4)], -1).size(), 9) and ok

	_reset_flat()
	var want_bomb := 1
	for r in ROWS:
		for c in COLS:
			if grid[r][c] == 3:
				want_bomb += 1
	grid[4][4] = 0
	special[4][4] = SP_BOMB
	ok = _check("blast_bomb", _expand([Vector2i(4, 4)], 3).size(), want_bomb) and ok

	# chained specials: a stripe in the blast radius of another stripe
	_reset_flat()
	special[4][4] = SP_STRIPE_H
	special[4][6] = SP_STRIPE_V
	ok = _check("blast_chained", _expand([Vector2i(4, 4)], -1).size(), COLS + ROWS - 1) and ok

	# full cascade from a real match
	_reset_flat()
	for r in ROWS:
		for c in COLS:
			pieces[r][c].sprite_frames = frames[grid[r][c]]
	_plant(3, 2, 4, 0, true)
	last_swap = [Vector2i(3, 3)]
	await _resolve()
	last_swap = []
	var empty := 0
	for r in ROWS:
		for c in COLS:
			if grid[r][c] < 0:
				empty += 1
	var sprites := 0
	for ch in board_layer.get_children():
		if ch is AnimatedSprite2D:
			sprites += 1
	ok = _check("cascade_empty", empty, 0) and ok
	ok = _check("cascade_matches", _find_matches().size(), 0) and ok
	ok = _check("cascade_sprites", sprites, ROWS * COLS) and ok
	ok = _check("stripe_created", _count_special(SP_STRIPE_H) >= 1, true) and ok

	# deadlock detection: the 3-species diagonal has no legal swap at all
	for r in ROWS:
		for c in COLS:
			grid[r][c] = (r + c) % 3
			special[r][c] = SP_NONE
	ok = _check("deadlock_no_match", _find_matches().size(), 0) and ok
	ok = _check("deadlock_no_move", _has_legal_move(), false) and ok

	# a board with a reachable match must report a move
	_reset_flat()
	grid[0][0] = 0
	grid[0][1] = 0
	grid[1][2] = 0
	ok = _check("move_exists", _has_legal_move(), true) and ok

	# a special on the board always counts as a move
	for r in ROWS:
		for c in COLS:
			grid[r][c] = (r + c) % 3
			special[r][c] = SP_NONE
	special[4][4] = SP_BOMB
	ok = _check("special_is_move", _has_legal_move(), true) and ok

	# reshuffle rescues a deadlocked board
	for r in ROWS:
		for c in COLS:
			grid[r][c] = (r + c) % 3
			special[r][c] = SP_NONE
			pieces[r][c].sprite_frames = frames[grid[r][c]]
	var shuffled: bool = await _reshuffle()
	ok = _check("reshuffle_ok", shuffled, true) and ok
	ok = _check("reshuffle_no_match", _find_matches().size(), 0) and ok
	ok = _check("reshuffle_has_move", _has_legal_move(), true) and ok


	# --- special pair combos
	_reset_flat()
	var A := Vector2i(4, 4)
	var B := Vector2i(5, 4)
	ok = _check("combo_stripe_stripe",
		_combo_blast(A, B, SP_STRIPE_H, SP_STRIPE_V).size(), COLS + ROWS - 1) and ok
	ok = _check("combo_wrapped_pair",
		_combo_blast(A, B, SP_WRAPPED, SP_WRAPPED).size(), 25) and ok
	ok = _check("combo_stripe_wrapped",
		_combo_blast(A, B, SP_STRIPE_H, SP_WRAPPED).size(), 3 * COLS + 3 * ROWS - 9) and ok
	ok = _check("combo_bomb_bomb",
		_combo_blast(A, B, SP_BOMB, SP_BOMB).size(), ROWS * COLS) and ok

	# bomb pairings must catch every piece of the partner species and reach
	# further than those pieces alone
	for pair in [[SP_STRIPE_H, "stripe"], [SP_WRAPPED, "wrapped"]]:
		var hit := {}
		for cell in _combo_blast(A, B, SP_BOMB, pair[0]):
			hit[cell] = true
		var tgt: int = grid[B.y][B.x]
		var tgt_n := 0
		var covered := true
		for r in ROWS:
			for c in COLS:
				if grid[r][c] == tgt:
					tgt_n += 1
					if not hit.has(Vector2i(c, r)):
						covered = false
		ok = _check("combo_bomb_%s_covers" % pair[1], covered, true) and ok
		ok = _check("combo_bomb_%s_wider" % pair[1], hit.size() > tgt_n, true) and ok

	# a combo must leave a stable, full board
	_reset_flat()
	for r in ROWS:
		for c in COLS:
			pieces[r][c].sprite_frames = frames[grid[r][c]]
	special[B.y][B.x] = SP_STRIPE_V
	special[A.y][A.x] = SP_STRIPE_H
	var ccells := _combo_blast(A, B, SP_STRIPE_H, SP_STRIPE_V)
	special[A.y][A.x] = SP_NONE
	special[B.y][B.x] = SP_NONE
	await _resolve(ccells, -1)
	var empty2 := 0
	for r in ROWS:
		for c in COLS:
			if grid[r][c] < 0:
				empty2 += 1
	var sprites2 := 0
	for ch in board_layer.get_children():
		if ch is AnimatedSprite2D:
			sprites2 += 1
	ok = _check("combo_settles_empty", empty2, 0) and ok
	ok = _check("combo_settles_sprites", sprites2, ROWS * COLS) and ok


	# --- audio
	var audio_ok: bool = music != null and music.stream != null
	for key in SFX:
		var pl = sfx.get(key)
		if pl == null or pl.stream == null:
			audio_ok = false
	ok = _check("audio_loaded", audio_ok, true) and ok
	ok = _check("audio_sfx_count", sfx.size(), SFX.size()) and ok
	var loops: bool = music.stream is AudioStreamWAV \
		and music.stream.loop_mode != AudioStreamWAV.LOOP_DISABLED
	ok = _check("audio_music_loops", loops, true) and ok

	ok = _check("audio_loop_end", music.stream.loop_end > 0, true) and ok
	var voices_ok: bool = voices.size() == SPECIES
	for v in voices:
		if v == null:
			voices_ok = false
	ok = _check("audio_voices", voices_ok, true) and ok
	ok = _check("star_texture", star_full != null and star_full.atlas != null, true) and ok
	ok = _check("bg_texture", bg_back != null and bg_back.texture != null, true) and ok
	ok = _check("bg_three_scenes",
			bg_menu_tex != null and bg_play_tex != null and bg_map_tex != null, true) and ok
	ok = _check("font_loaded", ui_font != null, true) and ok
	# the font is caps-only by design; without the a-z aliases every lowercase
	# string in the UI rendered as tofu boxes
	var missing := ""
	for code in range(97, 123):
		if not ui_font.has_char(code):
			missing += char(code)
	ok = _check("font_lowercase", missing, "") and ok
	ok = _check("font_digits", ui_font.has_char(48) and ui_font.has_char(57), true) and ok
	# the two soft vignettes replacing the old scrim rectangle
	var fades := 0
	for ch in hud_layer.get_children():
		if ch is Sprite2D and ch.texture != null:
			fades += 1
	ok = _check("ui_fades", fades, 2) and ok

	# The combo readout used to sit at a fixed x and ran straight over the goal
	# text. Measure the worst case - longest goal string, widest combo - and
	# assert they cannot touch.
	_load_level(4)                      # collect walruses: the longest goal text
	collected = 15
	_update_score()
	_show_combo(9, 4320)
	var goal_w: float = ui_font.get_string_size(
			target_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var combo_w: float = ui_font.get_string_size(
			combo_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	var goal_right: float = target_label.position.x + goal_w
	var combo_left: float = combo_label.position.x + combo_label.size.x - combo_w
	ok = _check("hud_no_overlap", goal_right < combo_left, true) and ok
	_load_level(0)

	# The map generates its path, so it holds any level count - but only if the
	# scroll content grows with it. Measured from the real nodes so the check
	# cannot drift from the layout.
	var last_node: Button = select_buttons[select_buttons.size() - 1]
	var node_bottom: float = last_node.position.y + last_node.size.y + 60.0  # stars + info
	ok = _check("map_holds_every_level",
			node_bottom <= map_content.custom_minimum_size.y, true) and ok
	ok = _check("map_node_count", select_buttons.size(), level_table.size()) and ok
	ok = _check("map_scrolls", map_content.custom_minimum_size.y > 0.0, true) and ok
	# the top slice must line up with the board origin or the seam shows
	var slice: AtlasTexture = bg_front.texture
	ok = _check("bg_front_slice", slice.region.size.y * 2.0, ORIGIN.y) and ok
	# nothing belonging to a screen may hang off the root, or it shows everywhere
	var strays := 0
	for ch in get_children():
		if ch is Label or ch is ColorRect or ch is Button or ch is TextureRect \
				or ch is AnimatedSprite2D:
			strays += 1
	ok = _check("no_stray_widgets", strays, 0) and ok

	# the jelly overlay sits over the board, so it must not be input-grabbing
	_load_level(3)
	var controls := 0
	for ch in jelly_layer.get_children():
		if ch is Control:
			controls += 1
	ok = _check("jelly_view_count", jelly_layer.get_child_count() > 0, true) and ok
	ok = _check("jelly_view_no_controls", controls, 0) and ok
	_load_level(0)

	# board queries must be safe before any level is loaded
	var kept_grid := grid
	var kept_special := special
	grid = []
	special = []
	ok = _check("empty_board_matches", _find_matches().size(), 0) and ok
	ok = _check("empty_board_move", _has_legal_move(), true) and ok
	await _settle()
	grid = kept_grid
	special = kept_special

	# selecting a piece must cue that species' own voice
	_reset_flat()
	var mapped := true
	for i in SPECIES:
		grid[2][2] = i
		_select(Vector2i(2, 2))
		if voice_player.stream != voices[i]:
			mapped = false
	selected = Vector2i(-1, -1)
	ok = _check("voice_per_species", mapped, true) and ok


	# --- level: a swap that does nothing must be free
	_reset_flat()
	for r in ROWS:
		for c in COLS:
			pieces[r][c].sprite_frames = frames[grid[r][c]]
	score = 0
	game_over = false
	moves_left = 10
	await _try_swap(Vector2i(0, 0), Vector2i(1, 0))
	ok = _check("move_free_on_revert", moves_left, 10) and ok

	# a swap that matches must cost exactly one
	_reset_flat()
	for r in ROWS:
		for c in COLS:
			pieces[r][c].sprite_frames = frames[grid[r][c]]
	grid[3][2] = 0
	grid[3][3] = 0
	grid[4][4] = 0
	score = 0
	game_over = false
	moves_left = 10
	await _try_swap(Vector2i(4, 4), Vector2i(4, 3))
	ok = _check("move_spent_on_match", moves_left, 9) and ok

	# --- level: outcomes (level 0 is a score goal)
	_load_level(0)
	game_over = false
	won = false
	score = target
	moves_left = 5
	_check_outcome()
	ok = _check("score_goal_runs_on", game_over, false) and ok
	moves_left = 0
	_check_outcome()
	ok = _check("score_goal_wins_at_end", game_over and won, true) and ok

	# a collect goal still ends the moment it is met
	_load_level(1)
	collected = int(level_table[1]["goal"]["count"])
	moves_left = 5
	_check_outcome()
	ok = _check("collect_goal_ends_early", game_over and won, true) and ok
	_load_level(0)
	game_over = false
	won = false

	game_over = false
	won = false
	score = 0
	moves_left = 0
	_check_outcome()
	ok = _check("level_lose", game_over and not won, true) and ok

	game_over = false
	won = false
	score = 10
	moves_left = 3
	_check_outcome()
	ok = _check("level_runs_on", game_over, false) and ok

	# restart must reload the current level
	game_over = true
	score = 999
	moves_left = 0
	await _restart()
	ok = _check("restart_moves", moves_left, level_table[level]["moves"]) and ok
	ok = _check("restart_live", game_over, false) and ok

	# --- levels and stars
	_load_level(2)
	ok = _check("level_load_moves", moves_left, level_table[2]["moves"]) and ok
	ok = _check("level_load_target", target, int(level_table[2]["goal"]["score"])) and ok
	ok = _check("level_load_score", score, 0) and ok

	star_base = 1000
	ok = _check("stars_none", _stars_for(999), 0) and ok
	ok = _check("stars_one", _stars_for(1000), 1) and ok
	ok = _check("stars_two", _stars_for(int(1000 * STAR_2)), 2) and ok
	ok = _check("stars_three", _stars_for(int(1000 * STAR_3)), 3) and ok

	# clearing a level banks the best star count and persists it
	_load_level(1)                                   # collect level: moves rate it
	collected = int(level_table[1]["goal"]["count"])
	moves_left = 7                                   # 7/22 = 0.32 -> two stars
	_check_outcome()
	ok = _check("win_banks_stars", int(best.get(1, 0)), 2) and ok
	best[1] = 0
	_load_progress()
	ok = _check("progress_persisted", int(best.get(1, 0)), 2) and ok

	# a lower score must not lower the banked stars
	_load_level(1)
	collected = int(level_table[1]["goal"]["count"])
	moves_left = 1                                   # 1/22 -> one star only
	_check_outcome()
	ok = _check("best_not_lowered", int(best.get(1, 0)), 2) and ok

	# --- PLAY and the end of a level both land on the map, never in a level
	var saved_best2: Dictionary = best.duplicate()
	best = {}
	for i in 12:
		best[i] = 2                             # 24 stars: chapter 2 is open
	_goto(ST_MENU)
	menu_play.pressed.emit()
	ok = _check("play_opens_map", state, ST_SELECT) and ok
	ok = _check("play_focuses_next", _focus_level(), 12) and ok
	await get_tree().process_frame
	ok = _check("map_scrolled_to_focus", map_scroll.scroll_vertical,
			int(maxf(_node_pos(12).y - 260.0, 0.0))) and ok
	for i in level_table.size():
		best[i] = 3                             # all cleared: park at the end
	ok = _check("focus_is_last_when_cleared", _focus_level(),
			level_table.size() - 1) and ok

	await _start_level(5)
	_finish(true)
	ok = _check("result_offers_a_way_out", result_go.visible, true) and ok
	ok = _check("result_offers_replay", result_retry.visible, true) and ok
	result_go.pressed.emit()                    # the button, not the keyboard
	ok = _check("finish_returns_to_map", state, ST_SELECT) and ok
	ok = _check("result_hidden_on_leaving", result_go.visible, false) and ok
	await _token_settled()

	# --- the seal on the map
	best = {}
	token_at = -1
	gates_shown = {}
	_goto_select_at(_focus_level())
	ok = _check("seal_placed_on_first_visit", token_at, 0) and ok
	ok = _check("seal_placed_without_hopping", token_hopping, false) and ok
	ok = _check("seal_on_its_floe", map_token.position, _token_spot(0)) and ok
	ok = _check("seal_visible", map_token.visible, true) and ok

	best[0] = 2                                 # win level 1, back to the map
	_goto(ST_PLAY)
	_goto_select_at(1)
	ok = _check("seal_hops_after_win", token_hopping, true) and ok
	await _token_settled()
	ok = _check("seal_reaches_next_floe", token_at, 1) and ok
	ok = _check("seal_lands_on_its_floe", map_token.position, _token_spot(1)) and ok

	best[0] = 3                                 # a replay moves nothing
	_goto(ST_PLAY)
	_goto_select_at(1)
	ok = _check("seal_stays_on_replay", token_hopping, false) and ok

	# far behind, it skips ahead and hops only the last stretch
	for i in 7:
		best[i] = 2
	_goto(ST_PLAY)
	_goto_select_at(7)
	ok = _check("seal_long_walk_skips_ahead", token_at, 6) and ok
	await _token_settled()
	ok = _check("seal_long_walk_arrives", token_at, 7) and ok

	# The gate: 9 stars before level 10, then a 3-star clear pays the 13.
	best = {}
	for i in 9:
		best[i] = 1
	best[0] = 2
	token_at = -1
	_goto_select_at(_focus_level())
	ok = _check("seal_waits_at_gate", token_at, CHAPTER - 1) and ok
	ok = _check("gate_drawn_shut", bool(gates_shown.get(1, true)), false) and ok
	best[CHAPTER - 1] = 3
	_goto(ST_PLAY)
	_goto_select_at(CHAPTER)
	# paid, but it stands until the seal gets there - that is the moment
	ok = _check("gate_stands_until_seal_arrives",
			bool(gates_shown.get(1, true)), false) and ok
	ok = _check("gate_sinking_on_screen", gate_marks[0]["floes"][0][0].position.y,
			float(gate_marks[0]["y"])) and ok
	await _token_settled()
	ok = _check("seal_crosses_gate", token_at, CHAPTER) and ok
	ok = _check("gate_sunk_after_crossing", bool(gates_shown.get(1, false)), true) and ok
	ok = _check("gate_ridge_lowered", gate_marks[0]["floes"][0][0].position.y,
			float(gate_marks[0]["y"]) + GATE_SINK) and ok

	# going backwards (progress reset) just places it, and a plain refresh
	# never leaves a paid gate standing
	best = {}
	_goto_select_at(0)
	ok = _check("seal_snaps_back", token_at, 0) and ok
	ok = _check("seal_no_hop_back", token_hopping, false) and ok
	for i in CHAPTER:
		best[i] = 2
	_refresh_select()
	ok = _check("refresh_never_leaves_gate_pending",
			bool(gates_shown.get(1, false)), true) and ok

	best = saved_best2
	_refresh_select()
	_goto(ST_PLAY)
	_load_level(0)

	# --- the level file
	var from_file: Array = _read_level_file(LEVELS_PATH)
	ok = _check("levels_from_file", from_file.size(), level_table.size()) and ok
	ok = _check("levels_past_thirty", level_table.size() > 30, true) and ok
	# the first 30 are frozen exactly as they were played
	ok = _check("classic_level_1", [int(level_table[0]["moves"]),
			int(level_table[0]["goal"]["score"])], [22, 1250]) and ok
	ok = _check("classic_level_6_shaped", (level_table[5].get("shape", []) as Array).size(), ROWS) and ok
	ok = _check("classic_level_30", [int(level_table[29]["moves"]),
			_level_summary(29)], [16, "16x BEAR"]) and ok
	_write_level_file(level_table, "user://levels_roundtrip.json")
	var back: Array = _read_level_file("user://levels_roundtrip.json")
	var same_back: bool = back.size() == level_table.size()
	for i in mini(back.size(), level_table.size()):
		if var_to_str(back[i]) != var_to_str(level_table[i]):
			same_back = false
	ok = _check("level_file_round_trip", same_back, true) and ok

	# every generated level was measured, and landed where it was aimed
	var uncal := 0
	var out_of_range := 0
	var off_target := 0
	var chapter_stars: Dictionary = {}
	for i in range(30, level_table.size()):
		var cfg: Dictionary = level_table[i]
		if not cfg.has("cal"):
			uncal += 1
			continue
		var m: int = int(cfg["moves"])
		if m < MOVES_MIN or m > MOVES_MAX:
			out_of_range += 1
		# the budget is the fewest moves that reach the target, so the bot sits
		# at or a little above it - one move can be worth 10-15 points
		var c: Dictionary = cfg["cal"]
		var over: float = float(c["bot"]) - _want_clear(i + 1)
		if over > 0.18 or (over < -0.001 and m < MOVES_MAX):
			off_target += 1
		var ch: int = i / CHAPTER
		chapter_stars[ch] = float(chapter_stars.get(ch, 0.0)) + float(c["stars"])
	ok = _check("generated_all_calibrated", uncal, 0) and ok
	ok = _check("generated_budgets_in_range", out_of_range, 0) and ok
	ok = _check("generated_on_target", off_target, 0) and ok
	# Gates ask CHAPTER_GATE stars a level, so a chapter that pays the bot
	# less than that would be a wall. Partial chapters at the end are skipped.
	var thin_chapters: Array = []
	for ch in chapter_stars:
		if (ch + 1) * CHAPTER <= level_table.size() \
				and float(chapter_stars[ch]) / CHAPTER < CHAPTER_GATE:
			thin_chapters.append(ch + 1)
	ok = _check("chapters_pay_their_gate", thin_chapters, []) and ok

	# generated levels earn stars by their own measured thresholds
	var star_rules_ok := true
	for i in range(30, mini(level_table.size(), 34)):
		var cut: Array = level_table[i].get("stars", [])
		if cut.size() != 2:
			star_rules_ok = false
			continue
		_load_level(i)
		if int(goal["kind"]) == GOAL_SCORE:
			for pair in [[int(cut[1]), 3], [int(cut[0]), 2], [star_base, 1], [star_base - 1, 0]]:
				if _stars_for(int(pair[0])) != int(pair[1]):
					star_rules_ok = false
		else:
			for pair in [[int(cut[1]), 3], [int(cut[0]), 2], [int(cut[0]) - 1, 1]]:
				moves_left = int(pair[0])
				if _stars_earned() != int(pair[1]):
					star_rules_ok = false
	ok = _check("generated_star_thresholds", star_rules_ok, true) and ok

	ok = _check("design_is_deterministic",
			var_to_str(_design_spec(57)) == var_to_str(_design_spec(57)), true) and ok
	var curve_ok := true
	for ch in 12:
		var opener: float = _want_clear(ch * CHAPTER + 1)
		var finale: float = _want_clear(ch * CHAPTER + CHAPTER)
		if opener <= finale or finale < 0.45:
			curve_ok = false
	ok = _check("chapters_open_easy_end_hard", curve_ok, true) and ok
	ok = _check("curve_levels_off",
			_want_clear(150) == _want_clear(250), true) and ok

	# --- holey boards
	_load_level(8)                      # a generated level with a board shape
	await _settle()
	var holes := 0
	var hole := Vector2i(-1, -1)
	for r in ROWS:
		for c in COLS:
			if not _is_open(r, c):
				holes += 1
				if hole.x < 0:
					hole = Vector2i(c, r)
	ok = _check("shape_has_holes", holes > 0, true) and ok

	var bad_fill := 0
	for r in ROWS:
		for c in COLS:
			if _is_open(r, c):
				if grid[r][c] < 0 or pieces[r][c] == null:
					bad_fill += 1
			elif grid[r][c] >= 0 or pieces[r][c] != null:
				bad_fill += 1
	ok = _check("shape_fill_respects_holes", bad_fill, 0) and ok

	# Clear the bottom of every column and let gravity run. Every open cell
	# must refill and nothing may ever come to rest in a hole - this is the
	# check that would catch collapse walking outside a column's open span.
	var victims: Array = []
	for c in COLS:
		if col_bot[c] >= 0:
			victims.append(Vector2i(c, col_bot[c]))
	await _pop(victims)
	await _collapse()
	var bad_after := 0
	for r in ROWS:
		for c in COLS:
			if _is_open(r, c):
				if grid[r][c] < 0 or pieces[r][c] == null:
					bad_after += 1
			elif grid[r][c] >= 0 or pieces[r][c] != null:
				bad_after += 1
	ok = _check("shape_collapse_refills", bad_after, 0) and ok

	var move_in_hole := false
	for mv in _all_moves():
		for cell in mv:
			if not _is_open(cell.y, cell.x):
				move_in_hole = true
	ok = _check("shape_moves_skip_holes", move_in_hole, false) and ok
	ok = _check("shape_click_ignores_hole",
			_cell_at(_cell_pos(hole.y, hole.x)).x, -1) and ok

	# A ring splits every column it touches, so it must be rejected outright
	# rather than silently producing regions that can never refill.
	board_shape = ["########", "#......#", "#.####.#", "#.#..#.#",
			"#.#..#.#", "#.####.#", "#......#", "########"]
	_build_blocked()
	var still_blocked := 0
	for r in ROWS:
		for c in COLS:
			if not _is_open(r, c):
				still_blocked += 1
	ok = _check("shape_rejects_split_column", still_blocked, 0) and ok
	board_shape = []

	# Every shaped level must survive _build_blocked() as written - its
	# fallback would quietly turn a bad shape into a plain board - and must
	# cut enough to be seen (7 is the shallowest random edge). Level 9 once
	# cut four corner cells and nobody noticed it was a shape at all.
	var shapes_intact := true
	var shapes_visible := true
	var jelly_on_hole := 0
	var shaped_unplayable := 0
	var first_shape := -1
	var first_drift := -1
	for i in level_table.size():
		var cfg: Dictionary = level_table[i]
		var mask: Array = cfg.get("shape", [])
		if mask.is_empty():
			continue
		if first_shape < 0:
			first_shape = i
		var want_holes: int = ROWS * COLS - _mask_open(mask)
		board_shape = mask
		_build_blocked()
		var got_holes := 0
		for r in ROWS:
			for c in COLS:
				if not _is_open(r, c):
					got_holes += 1
		if got_holes != want_holes:
			shapes_intact = false
		if want_holes < 7:
			shapes_visible = false
		var g: Dictionary = cfg["goal"]
		if int(g["kind"]) == GOAL_JELLY:
			for r in ROWS:
				for c in COLS:
					if String(g["layout"][r])[c] != "." and not _is_open(r, c):
						jelly_on_hole += 1
		_load_level(i)
		await _settle()
		if not _has_legal_move():
			shaped_unplayable += 1
		if i % CHAPTER % 3 == 1 and first_drift < 0:
			first_drift = i
	board_shape = []
	ok = _check("shapes_survive_contiguity", shapes_intact, true) and ok
	ok = _check("shapes_cut_enough_to_see", shapes_visible, true) and ok
	ok = _check("shapes_no_jelly_on_holes", jelly_on_hole, 0) and ok
	ok = _check("shapes_all_playable", shaped_unplayable, 0) and ok
	# the first shape arrives inside chapter 1, on a hand-tuned level
	ok = _check("shape_first_on_level_6", first_shape + 1, 6) and ok
	# chapter 1 teaches the named shapes; random edges wait for chapter 2
	ok = _check("drift_not_in_chapter_one", first_drift >= CHAPTER, true) and ok
	ok = _check("drift_is_stable", _drift_mask(17) == _drift_mask(17), true) and ok
	ok = _check("drift_varies", _drift_mask(17) != _drift_mask(18), true) and ok
	var drift_ok := true
	for n in range(1, 200):
		var m: Array = _drift_mask(n)
		var cut: int = ROWS * COLS - _mask_open(m)
		if m.is_empty() or cut < 7 or cut > 12:
			drift_ok = false
	ok = _check("drift_always_in_range", drift_ok, true) and ok
	_load_level(0)

	# --- stars on goal levels come from moves left, not score
	_load_level(1)
	collected = int(level_table[1]["goal"]["count"])
	moves_left = int(level_table[1]["moves"])
	ok = _check("goal_stars_full_budget", _stars_earned(), 3) and ok
	moves_left = 7
	ok = _check("goal_stars_mid_budget", _stars_earned(), 2) and ok
	moves_left = 1
	ok = _check("goal_stars_last_move", _stars_earned(), 1) and ok
	score = 999999
	ok = _check("goal_stars_ignore_score", _stars_earned(), 1) and ok
	_load_level(0)                                   # score level still scores
	score = int(star_base * STAR_3)
	moves_left = 1
	ok = _check("score_stars_still_score", _stars_earned(), 3) and ok

	# --- the free reshuffle costs no move and keeps score
	_load_level(3)
	await _settle()
	var before_score: int = score
	var before_moves: int = moves_left
	ok = _check("shuffle_starts_at_one", shuffles_left, 1) and ok
	await _use_shuffle()
	ok = _check("shuffle_spent", shuffles_left, 0) and ok
	ok = _check("shuffle_keeps_score", score, before_score) and ok
	ok = _check("shuffle_keeps_moves", moves_left, before_moves) and ok
	ok = _check("shuffle_board_playable", _has_legal_move(), true) and ok
	ok = _check("shuffle_no_free_matches", _find_matches().size(), 0) and ok
	await _use_shuffle()
	ok = _check("shuffle_not_reusable", shuffles_left, 0) and ok

	# --- star gates: chapters open on the running star total
	var saved_best: Dictionary = best.duplicate()
	best = {}
	ok = _check("gate_chapter_one_free", _is_unlocked(0), true) and ok
	for i in CHAPTER:
		best[i] = 1                                  # cleared, barely: 10 stars
	ok = _check("gate_prev_level_still_counts", _is_unlocked(CHAPTER - 1), true) and ok
	ok = _check("gate_blocks_chapter_two", _is_unlocked(CHAPTER), false) and ok
	ok = _check("gate_skips_gated_level",
			_next_unplayed() < CHAPTER, true) and ok
	_refresh_select()
	var cap: Label = gate_marks[0]["cap"].get_child(0)
	ok = _check("gate_shows_toll", cap.text.contains("OF"), true) and ok
	for i in CHAPTER:
		best[i] = 2                                  # 20 stars clears the toll
	ok = _check("gate_opens_on_stars", _is_unlocked(CHAPTER), true) and ok
	_refresh_select()
	cap = gate_marks[0]["cap"].get_child(0)
	ok = _check("gate_hides_toll_when_open", cap.text.contains("OF"), false) and ok
	best = {0: 3}                                    # stars do not skip levels
	ok = _check("gate_needs_the_level_before", _is_unlocked(2), false) and ok
	# A gate nobody can pay would end the game. Measure, do not assume.
	var reachable := true
	for g in gate_marks:
		var ch: int = int(g["chapter"])
		if _chapter_gate(ch) > ch * CHAPTER * 3:
			reachable = false
	ok = _check("gate_always_payable", reachable, true) and ok
	ok = _check("gate_marks_every_boundary", gate_marks.size(),
			(level_table.size() - 1) / CHAPTER) and ok
	best = saved_best
	_refresh_select()

	# --- the shuffle button: free, once per level, and stars are never spent
	best = {}
	for i in CHAPTER:
		best[i] = 2
	var stars_before: int = _total_stars()
	await _start_level(0)
	await _settle()
	_update_score()
	ok = _check("shuffle_button_ready", shuffle_button.disabled, false) and ok
	var moves_before: int = moves_left
	shuffle_button.pressed.emit()
	while busy:
		await get_tree().process_frame
	ok = _check("shuffle_button_spends_it", shuffles_left, 0) and ok
	ok = _check("shuffle_button_costs_no_move", moves_left, moves_before) and ok
	ok = _check("shuffle_costs_no_stars", _total_stars(), stars_before) and ok
	ok = _check("shuffle_button_greys_out", shuffle_button.disabled, true) and ok
	ok = _check("shuffle_button_says_used", shuffle_button.text, "SHUFFLE USED") and ok
	await _start_level(1)
	await _settle()
	_update_score()
	ok = _check("shuffle_back_next_level", shuffles_left, SHUFFLES_PER_LEVEL) and ok
	ok = _check("shuffle_button_back", shuffle_button.disabled, false) and ok
	var cf_wallet := ConfigFile.new()
	_save_progress()
	cf_wallet.load(SAVE_PATH)
	ok = _check("save_has_no_wallet", cf_wallet.has_section("wallet"), false) and ok

	# the button sits between the goal legend and the key line, with its
	# longest label inside it - the HUD has collided twice before
	var b: Button = shuffle_button
	var label_w: float = ui_font.get_string_size(
			"SHUFFLE USED", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	ok = _check("shuffle_button_fits", b.position.y >= 708.0
			and b.position.y + b.size.y <= keys_label.position.y
			and label_w <= b.size.x - 10.0, true) and ok
	var screen_h: float = get_viewport_rect().size.y
	var ink: float = keys_label.position.y + ui_font.get_string_size(
			keys_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).y
	ok = _check("hud_inside_viewport",
			maxf(ink, b.position.y + b.size.y) <= screen_h, true) and ok

	best = saved_best
	_save_progress()
	_refresh_select()

	# --- goals
	_load_level(1)                                   # collect level
	ok = _check("goal_collect_total", _goal_total(), int(level_table[1]["goal"]["count"])) and ok
	ok = _check("goal_collect_start", _goal_done(), 0) and ok
	collected = int(level_table[1]["goal"]["count"])
	ok = _check("goal_collect_met", _goal_met(), true) and ok

	_load_level(3)                                   # jelly level
	var jelly_expected := 0
	for line in level_table[3]["goal"]["layout"]:
		for ch in line:
			if ch == "1" or ch == "2":
				jelly_expected += int(ch)
	ok = _check("goal_jelly_total", jelly_left, jelly_expected) and ok
	ok = _check("goal_jelly_unmet", _goal_met(), false) and ok
	jelly_left = 0
	ok = _check("goal_jelly_met", _goal_met(), true) and ok

	# a double jelly cell takes two clears
	_load_level(3)
	jelly[5][2] = 2
	jelly_left = 2
	await _pop([Vector2i(2, 5)])
	ok = _check("jelly_one_layer_left", jelly[5][2], 1) and ok
	ok = _check("jelly_count_down", jelly_left, 1) and ok

	# jelly belongs to the cell, not the piece: a collapse must not drag it
	_load_level(3)
	for r in ROWS:
		for c in COLS:
			jelly[r][c] = 0
	jelly[7][3] = 1
	jelly_left = 1
	await _pop([Vector2i(3, 3)])
	await _collapse()
	ok = _check("jelly_stays_put", jelly[7][3], 1) and ok
	ok = _check("jelly_not_dragged", jelly[3][3], 0) and ok
	ok = _check("jelly_count_intact", jelly_left, 1) and ok

	# winning always banks at least one star, even on the very last move with
	# nothing scored - the floor, not the full-budget case
	_load_level(1)
	collected = int(level_table[1]["goal"]["count"])
	moves_left = 0
	score = 10
	best[1] = 0
	_check_outcome()
	ok = _check("win_min_one_star", stars, 1) and ok
	ok = _check("win_on_collect", won, true) and ok

	# running out of moves with the goal unmet still loses
	_load_level(1)
	moves_left = 0
	score = 99999
	_check_outcome()
	ok = _check("lose_on_unmet_goal", won, false) and ok
	for i in level_table.size():
		best[i] = 0
	_save_progress()
	_load_level(0)

	# --- screens
	_goto(ST_MENU)
	ok = _check("menu_hides_board", board_layer.visible, false) and ok
	ok = _check("menu_shows_menu", menu_layer.visible, true) and ok
	await _start_level(1)
	ok = _check("play_shows_board", board_layer.visible and state == ST_PLAY, true) and ok
	ok = _check("play_level", level, 1) and ok

	# unlock gating: a level opens once the one before it has a star
	for i in level_table.size():
		best[i] = 0
	_refresh_select()
	ok = _check("lock_first_open", select_buttons[0].disabled, false) and ok
	ok = _check("lock_second_shut", select_buttons[1].disabled, true) and ok
	best[0] = 1
	_refresh_select()
	ok = _check("lock_second_open", select_buttons[1].disabled, false) and ok
	ok = _check("lock_third_shut", select_buttons[2].disabled, true) and ok

	ok = _check("next_unplayed_first", _next_unplayed(), 1) and ok
	best[1] = 3
	ok = _check("next_unplayed_skips", _next_unplayed(), 2) and ok
	for i in level_table.size():
		best[i] = 0
	_save_progress()
	_goto(ST_MENU)

	print("[selftest] %s   score=%d" % ["ALL PASS" if ok else "FAILURES", score])
	music.stop()
	get_tree().quit(0 if ok else 1)   # non-zero so CI fails on a bad assertion
