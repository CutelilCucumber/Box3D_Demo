extends RefCounted

## Builds the destructible skeleton for one drone-city building style.
##
## Each style is a recipe: a set of structural members (invisible WallPanels /
## BreakableBlocks / GlassPanes) sized to fill an AABB. The recipe is authored
## per style here (not procedural from the mesh), matching how the imported
## buildings read — walls, floors, windows with glass, metal columns for the
## tough ones — so the mech chews a building apart member by member.
##
##   build_structure(parent, style, aabb) -> int  (# bodies spawned)
##
## The AABB is the skin mesh's WORLD AABB; members are placed in world space
## with the AABB's min corner as the local origin.

const WallPanel := preload("res://lib/bodies/wall_panel.gd")
const BreakableBlock := preload("res://lib/bodies/breakable_block.gd")
const GlassPane := preload("res://lib/glass/glass_pane.gd")

const T := 0.25         # wall thickness
const STORY_H := 2.8    # one storey
const WIN_H := 1.4      # window opening height
const SILL_H := 0.8     # sill under a window
const WIN_W := 1.2      # window width
const DENSITY := 1.2
const FRICTION := 0.8

## Styles are matched by the mesh instance name prefix (see drone_city_mech.gd).
const STYLE_EDIFICIO := "orto-edificio22"
const STYLE_CUBE := "Cube"
const STYLE_KIOSK := "kiosko"
const STYLE_OXXO := "techolocalcomercialoxxo"
const STYLE_HOSPITAL := "hospitaltechopiezita"
const STYLE_ROJO := "ortoedificiocontechorojo"


## Returns the number of bodies spawned into `parent` (the Box3DWorld or a
## group node under it) to form the style's skeleton over `aabb` (world space).
static func build_structure(parent: Node, style: String, aabb: AABB) -> int:
	if style.begins_with(STYLE_EDIFICIO) or style.begins_with(STYLE_CUBE):
		return _build_tower(parent, aabb)
	if style.begins_with(STYLE_KIOSK):
		return _build_kiosk(parent, aabb)
	if style.begins_with(STYLE_OXXO) or style.begins_with(STYLE_ROJO) \
			or style.begins_with(STYLE_HOSPITAL):
		return _build_box(parent, aabb)
	return 0


## A multi-storey tower: floor slabs every storey, load-bearing corner
## columns and a wall on each face with window glass. Metal columns stand at
## the corners so the tower keeps its skeleton longer (durable members).
static func _build_tower(parent: Node, aabb: AABB) -> int:
	var w := aabb.size.x
	var d := aabb.size.z
	var h := aabb.size.y
	var count := 0
	var cx := aabb.get_center().x
	var cz := aabb.get_center().z
	var base := aabb.position.y
	var stories := maxi(int(h / STORY_H), 1)
	var story_h := h / stories

	for s in stories:
		var y0 := base + s * story_h
		# Floor slab.
		count += _panel(parent, Vector3(cx, y0, cz), Vector3(w, 0.18, d), "masonry")
		# Front and back walls.
		count += _wall(parent, cx, y0, w, story_h, cz + d * 0.5 - T * 0.5, true)
		count += _wall(parent, cx, y0, w, story_h, cz - d * 0.5 + T * 0.5, true)
		# Side walls (no windows).
		count += _panel(parent, Vector3(cx - w * 0.5 + T * 0.5, y0 + story_h * 0.5, cz),
				Vector3(T, story_h, d - 2.0 * T), "masonry")
		count += _panel(parent, Vector3(cx + w * 0.5 - T * 0.5, y0 + story_h * 0.5, cz),
				Vector3(T, story_h, d - 2.0 * T), "masonry")
		# Four metal corner columns.
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				count += _panel(parent,
						Vector3(cx + sx * (w * 0.5 - 0.15), y0 + story_h * 0.5,
								cz + sz * (d * 0.5 - 0.15)),
						Vector3(0.3, story_h, 0.3), "metal")
	# Roof slab (metal, holds a bit longer).
	count += _panel(parent, Vector3(cx, base + h, cz), Vector3(w + 0.4, 0.22, d + 0.4), "metal")
	return count


## One windowed wall face along the X axis at world (cx, y0, cz), spanning w
## metres wide and story_h tall. Windows get glass panes.
static func _wall(parent: Node, cx: float, y0: float, w: float, story_h: float,
		cz: float, along_x: bool) -> int:
	var count := 0
	var n_win := maxi(int(w / 3.5), 1)
	n_win = mini(n_win, 4)
	var pier_w := (w - n_win * WIN_W) / (n_win + 1.0)
	var cursor := -w * 0.5
	for i in n_win * 2 + 1:
		var is_pier := i % 2 == 0
		var cw := pier_w if is_pier else WIN_W
		var cx2 := cursor + cw * 0.5
		cursor += cw
		var mid_h := y0 + SILL_H + WIN_H * 0.5 if not is_pier else y0 + story_h * 0.5
		var face := Vector2(cw, story_h) if is_pier else Vector2(cw, WIN_H)
		if along_x:
			count += _panel(parent, Vector3(cx + cx2, mid_h, cz), Vector3(face.x, face.y, T), "masonry")
		else:
			count += _panel(parent, Vector3(cx, mid_h, cz + cx2), Vector3(T, face.y, face.x), "masonry")
		if not is_pier:
			# Glass in the opening between sill and band.
			var pane := GlassPane.new()
			var gh := story_h - SILL_H - 0.06
			if along_x:
				pane.box_size = Vector3(cw - 0.06, gh, 0.03)
				pane.position = Vector3(cx + cx2, y0 + SILL_H + gh * 0.5 + 0.02, cz)
			else:
				pane.box_size = Vector3(0.03, gh, cw - 0.06)
				pane.position = Vector3(cx, y0 + SILL_H + gh * 0.5 + 0.02, cz + cx2)
			parent.add_child(pane)
			count += 1
	return count


## A kiosk: four walls (two windowed), a roof, a metal frame. ~2m box.
static func _build_kiosk(parent: Node, aabb: AABB) -> int:
	var w := aabb.size.x
	var d := aabb.size.z
	var h := aabb.size.y
	var count := 0
	var cx := aabb.get_center().x
	var cz := aabb.get_center().z
	var base := aabb.position.y
	count += _wall(parent, cx, base, w, h, cz + d * 0.5 - T * 0.5, true)
	count += _wall(parent, cx, base, w, h, cz - d * 0.5 + T * 0.5, true)
	count += _panel(parent, Vector3(cx - w * 0.5 + T * 0.5, base + h * 0.5, cz),
			Vector3(T, h, d - 2.0 * T), "masonry")
	count += _panel(parent, Vector3(cx + w * 0.5 - T * 0.5, base + h * 0.5, cz),
			Vector3(T, h, d - 2.0 * T), "masonry")
	count += _panel(parent, Vector3(cx, base + h, cz), Vector3(w, 0.2, d), "metal")
	return count


## A simple box (roof structures, commercial units): four walls, roof, floor.
static func _build_box(parent: Node, aabb: AABB) -> int:
	var w := aabb.size.x
	var d := aabb.size.z
	var h := aabb.size.y
	var count := 0
	var cx := aabb.get_center().x
	var cz := aabb.get_center().z
	var base := aabb.position.y
	count += _panel(parent, Vector3(cx, base + h * 0.5, cz + d * 0.5 - T * 0.5),
			Vector3(w, h, T), "masonry")
	count += _panel(parent, Vector3(cx, base + h * 0.5, cz - d * 0.5 + T * 0.5),
			Vector3(w, h, T), "masonry")
	count += _panel(parent, Vector3(cx - w * 0.5 + T * 0.5, base + h * 0.5, cz),
			Vector3(T, h, d - 2.0 * T), "masonry")
	count += _panel(parent, Vector3(cx + w * 0.5 - T * 0.5, base + h * 0.5, cz),
			Vector3(T, h, d - 2.0 * T), "masonry")
	count += _panel(parent, Vector3(cx, base + h, cz), Vector3(w, 0.2, d), "metal")
	count += _panel(parent, Vector3(cx, base + 0.09, cz), Vector3(w, 0.18, d), "masonry")
	return count


## Spawns one invisible structural member. Material drives durability:
## masonry breaks normally, metal needs a hard hit + lots of HP.
static func _panel(parent: Node, center: Vector3, size: Vector3,
		material := "masonry") -> int:
	var p := WallPanel.new()
	p.box_size = size
	p.position = center
	p.density = DENSITY
	p.friction = FRICTION
	p.material = material
	p.emit_visual = false
	p.panel_color = Color(0.78, 0.74, 0.68)
	parent.add_child(p)
	return 1