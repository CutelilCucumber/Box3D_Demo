extends "res://lib/models/units/parts/mech_part.gd"

## Base for TANK-STYLE body parts (tracked hulls). A tank never leans its hull
## into the aim pitch — the turret pitches on its own pivot while the body
## stays level — and it has no legs to animate. Parts that extend this only
## need to expose their mount markers (see chibitank_body.gd).

## The hull stays level: no torso lean.
func torso_lean() -> float:
	return 0.0


## Tanks carry the reclaim laser too — the right trigger is the same beam that
## grinds structures and melts debris as on the walkers.
func uses_laser() -> bool:
	return true


## Tank main guns fire physics-free cannonballs (cannon_ball.gd), not the
## walker mech's plasma bolt.
func uses_cannonball() -> bool:
	return true


## No legs to swing; the tracks are static in this demo.
func animate_parts(_delta: float, _move_speed: float, _torso_lean: float) -> void:
	pass


## A tank has no legs.
func leg(_left: bool) -> Node3D:
	return null