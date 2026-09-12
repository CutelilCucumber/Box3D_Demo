extends "res://lib/models/units/parts/mech_parts.gd"

## Warbot (War Robot) body part for the modular mech. Exposes the head-mount
## marker (where the head attaches and aims around) and the two leg joints the
## mech's walk cycle drives. Per-part layout facts live here so mech_body.gd
## can compose any body generically. The walk animation and torso-lean live in
## mech_parts.gd (this is a walker).

## How far the body root sits above its feet; applied to stand it on the ground.
@export var visual_y_offset := -0.96

## The marker where the head part connects and rotates around.
func mount_marker() -> Node3D:
	return _find_descendant(self, "HeadMount") as Node3D


## The node the head part (and its aiming pivot) hangs from. The exported
## model's "Body" node carries a baked rotation, so the head must inherit it
## to aim in the right frame.
func mount_parent() -> Node3D:
	return _find_descendant(self, "Body") as Node3D


## The left or right leg joint node, or null if this body has no legs.
func leg(left: bool) -> Node3D:
	return _find_descendant(self, "Leg_L" if left else "Leg_R") as Node3D
