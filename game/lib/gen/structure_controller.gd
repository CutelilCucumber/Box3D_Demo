extends Node3D

## Structure controller for the drone city's destructible buildings.
##
## A structure is a group of destructible bodies (WallPanels, BreakableBlocks,
## GlassPanes) that are INVISIBLE (emit_visual = false) and stand in for one
## style of building mesh. The original imported mesh is reparented here as the
## `skin`; its own materials stay, and a slightly-inflated damage overlay twin
## shows char + holes wherever the structural pieces are hit or break (the
## structure_damage.gdshader + a painted 512x512 damage mask).
##
## When enough of the structure is gone the skin + overlay hide, leaving the
## pile of debris the pieces shattered into.
##
## Construction (see drone_city_mech.gd): instantiate a structure scene, call
## setup(skin_mesh) once the structural bodies are children. The controller
## fits the damage mask to the skin's local AABB automatically.

const StructureDamage := preload("res://lib/fx/structure_damage.gdshader")
const StructureBuilder := preload("res://lib/gen/structure_builder.gd")
const FractureFX := preload("res://lib/fx/fracture_fx.gd")

const MASK_SIZE := 512
const DAMAGE_CUTOFF := 0.35
const HOLE_CUTOFF := 0.8
const COLLAPSE_RATIO := 0.9  # fraction of pieces gone before the skin hides

## The original building mesh this structure stands in for. Reparented under
## the controller at bake time; keeps its own materials.
var skin: MeshInstance3D = null
var _overlay: MeshInstance3D = null
var _mask_img: Image = null
var _mask_tex: ImageTexture = null
var _mat: ShaderMaterial = null
var _pieces: Array[Node] = []
var _alive := 0
var _total := 0


func setup(skin_mesh: MeshInstance3D, xf: Transform3D, world_aabb: AABB) -> void:
	if skin_mesh == null:
		return
	skin = skin_mesh
	# The controller sits at the world origin; its children (the skeleton
	# pieces and the skin) are placed in world coordinates. The bake tree is
	# not live, so the skin's transform comes from the caller's hand-computed
	# `xf`, not from global_transform.
	skin.get_parent().remove_child(skin)
	add_child(skin)
	skin.transform = xf
	# The overlay is the same mesh, slightly inflated, running the damage
	# shader. It only draws where the mask is damaged, so the skin shows
	# through untouched elsewhere.
	var aabb := skin.get_aabb()
	_overlay = MeshInstance3D.new()
	_overlay.mesh = skin.mesh
	_overlay.transform = skin.transform  # same placement as the skin
	_overlay.scale = Vector3.ONE * 1.001
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_overlay)
	_mat = ShaderMaterial.new()
	_mat.shader = StructureDamage
	_overlay.material_override = _mat

	# Damage mask spanning the skin's local AABB.
	var span := aabb.size.max(Vector3.ONE * 0.001)
	_mask_img = Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RF)
	_mask_img.fill(Color(0.0, 0.0, 0.0, 1.0))
	_mask_tex = ImageTexture.create_from_image(_mask_img)
	_mat.set_shader_parameter("damage_mask", _mask_tex)
	_mat.set_shader_parameter("mask_origin", aabb.position)
	_mat.set_shader_parameter("mask_scale", 1.0 / _span_max(span))

	# The skeleton: a per-style recipe of panels/blocks/glass sized to this
	# skin's world AABB (matches the instance's own scale/rotation).
	StructureBuilder.build_structure(self, skin.name, world_aabb)

	# Track the structural bodies.
	_collect_pieces()
	_alive = _pieces.size()
	_total = _alive


func _collect_pieces() -> void:
	_pieces.clear()
	for c in get_children():
		_collect(c)


func _collect(n: Node) -> void:
	if n is Box3DBody and n != skin and n != _overlay:
		if n.is_in_group("panel") or n.is_in_group("block") or n.is_in_group("glass"):
			_pieces.append(n)
	for c in n.get_children():
		_collect(c)


## Paint a damage blob on the skin at a world point, with a radius in metres.
## Paints all three face projections so the triplanar sample reads it on the
## correct wall.
func paint_damage(world_point: Vector3, radius: float) -> void:
	if _mask_img == null or skin == null:
		return
	var local: Vector3 = skin.global_transform.affine_inverse() * world_point
	var aabb := skin.get_aabb()
	var span := aabb.size.max(Vector3.ONE * 0.001)
	var scale := 1.0 / _span_max(span)
	var u := (local.x - aabb.position.x) * scale
	var v := (local.y - aabb.position.y) * scale
	var w := (local.z - aabb.position.z) * scale
	# XY face (normal +Z), ZY face (normal +X), XZ face (normal +Y).
	_paint(u, v)
	_paint(w, v)
	_paint(u, w)


static func _span_max(v: Vector3) -> float:
	return maxf(maxf(v.x, v.y), v.z)


## The skin mesh's world AABB, used to size the skeleton so it matches the
## instance's own transform (rotation + non-uniform scale).
static func _world_aabb(mi: MeshInstance3D) -> AABB:
	var aabb := mi.get_aabb()
	var xf := mi.global_transform
	var corners := [
		aabb.position, aabb.end,
		Vector3(aabb.position.x, aabb.position.y, aabb.end.z),
		Vector3(aabb.position.x, aabb.end.y, aabb.position.z),
		Vector3(aabb.end.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.end.x, aabb.end.y, aabb.position.z),
		Vector3(aabb.end.x, aabb.position.y, aabb.end.z),
		Vector3(aabb.position.x, aabb.end.y, aabb.end.z),
	]
	var out := AABB(xf * corners[0], Vector3.ZERO)
	for i in range(1, corners.size()):
		out = out.expand(xf * corners[i])
	return out


func _paint(u: float, v: float) -> void:
	var px := clampf(int(u * MASK_SIZE), 0, MASK_SIZE - 1)
	var py := clampf(int(v * MASK_SIZE), 0, MASK_SIZE - 1)
	var r := 6
	for y in range(maxi(py - r, 0), mini(py + r + 1, MASK_SIZE)):
		for x in range(maxi(px - r, 0), mini(px + r + 1, MASK_SIZE)):
			var d := Vector2(x - px, y - py).length() / float(r)
			if d > 1.0:
				continue
			var cur := _mask_img.get_pixel(x, y).r
			_mask_img.set_pixel(x, y, Color(maxf(cur, 1.0 - d * d), 0.0, 0.0, 1.0))
	_mask_tex.update(_mask_img)


## Route laser/cannon damage to the structural piece nearest the impact so the
## skin shows damage even while the pieces grind down individually.
func take_damage(amount: float, at: Vector3) -> void:
	paint_damage(at, 0.4)
	if _pieces.is_empty():
		return
	var best: Box3DBody = null
	var best_d := INF
	for p in _pieces:
		if p == null or not is_instance_valid(p) or not p.is_inside_tree():
			continue
		var d: float = (p.global_position - at).length()
		if d < best_d:
			best_d = d
			best = p
	if best != null and best.has_method("take_damage"):
		best.take_damage(amount, at)


func _process(_delta: float) -> void:
	if _total == 0 or skin == null or not is_instance_valid(skin):
		return
	var alive := 0
	for p in _pieces:
		if p != null and is_instance_valid(p) and p.is_inside_tree():
			alive += 1
	if alive == _alive:
		return
	_alive = alive
	FractureFX.burst(get_parent(), skin.global_position, 1.2,
			Color(0.55, 0.5, 0.45))
	if alive <= 1:
		_collapse()


## The building's structure is gone: hide the skin and overlay, leaving the
## debris pile.
func _collapse() -> void:
	FractureFX.burst(get_parent(), skin.global_position, 2.5,
			Color(0.55, 0.5, 0.45))
	skin.visible = false
	if _overlay != null:
		_overlay.visible = false