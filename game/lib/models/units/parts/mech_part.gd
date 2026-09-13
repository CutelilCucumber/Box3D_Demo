extends Node3D

## Shared base for modular mech parts (bodies and heads). Each part scene gets
## a thin script in the same folder that exposes that part's layout facts --
## mount markers, weapon muzzles, joints -- so mech_body.gd can compose any
## body + head combination generically. This base only provides the recursive
## descendant lookup the part scripts use to find their named markers wherever
## the imported model puts them.

## Depth-first search for a descendant node by name.
func _find_descendant(root: Node, marker_name: String) -> Node:
	if root.name == marker_name:
		return root
	for c in root.get_children():
		var found := _find_descendant(c, marker_name)
		if found != null:
			return found
	return null


## The left or right leg joint node, or null if this part has no legs. Bodies
## with legs override this (see warbot_body.gd); heads and tracked hulls keep
## the null default.
func leg(_left: bool) -> Node3D:
	return null


## Whether this body's main gun fires physics-free cannonballs (tracked hulls)
## instead of the walker mech's plasma bolt. Defaults to plasma; HEAD parts
## override this (see warbot_head.gd, chibitank_head.gd).
func uses_cannonball() -> bool:
	return false


## Whether this platform has a reclaim laser on the right trigger. Both the
## walker mechs and the tanks carry one; anything without it gets no RMB weapon.
## HEAD parts override this (see warbot_head.gd, chibitank_head.gd).
func uses_laser() -> bool:
	return false


## Scale compensation for the head when mounted on this body.
## Bodies with non-unity root scale (e.g. chibitank at 0.111) should override
## to return the inverse so the head maintains a fixed world size.
func get_head_scale() -> float:
	return 1.0
