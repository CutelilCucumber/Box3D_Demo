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