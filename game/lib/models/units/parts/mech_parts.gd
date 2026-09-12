extends "res://lib/models/units/parts/mech_part.gd"

## Base for MECH-STYLE body parts (walker bots). The whole torso leans into the
## aim pitch so the mech reads as aiming with its body, and the two legs swing
## with a walk cycle driven here. Parts that extend this only need to expose
## their mount markers and leg joints (see warbot_body.gd).

const LEG_SWING := 0.55     # rad swing amplitude at full walk speed
const LEG_RATE := 5.5       # rad of phase per metre travelled
const WALK_SPEED := 4.0     # m/s used to scale the swing amount

var walk_phase := 0.0

## Fraction of the aim pitch the whole torso leans with. Mech walkers lean;
## tanks override this to 0 (their hull stays level and only the turret pitches).
func torso_lean() -> float:
	return 1.0


## Mech-style weapons: the right trigger is a reclaim/laser beam.
func uses_laser() -> bool:
	return true


## Drive the walk cycle on this body's leg joints. `torso_lean` is the current
## torso pitch, subtracted so the feet stay planted while the body leans.
func animate_parts(delta: float, move_speed: float, torso_lean: float) -> void:
	var amount := clampf(move_speed / WALK_SPEED, 0.0, 1.0)
	if move_speed > 0.05:
		walk_phase += move_speed * LEG_RATE * delta
	var swing := LEG_SWING * amount
	var leg_l := leg(true)
	var leg_r := leg(false)
	if leg_l != null:
		leg_l.rotation.x = -torso_lean + swing * sin(walk_phase)
	if leg_r != null:
		leg_r.rotation.x = -torso_lean + swing * sin(walk_phase + PI)