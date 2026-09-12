extends "res://lib/models/units/parts/mech_part.gd"

## Chibi Tank head part for the modular mech. Exposes the two weapon muzzle
## markers (main gun + reclaim laser), found under the tank's turrent_container.
## The head root is the aiming pivot: mech_body.gd rotates the whole head
## around the body's mount point.

## World muzzle of the main gun (cannon / plasma).
func gun_tip() -> Node3D:
	return _find_descendant(self, "GunTip") as Node3D


## World muzzle of the reclaim laser.
func reclaim_tip() -> Node3D:
	return _find_descendant(self, "ReclaimTip") as Node3D