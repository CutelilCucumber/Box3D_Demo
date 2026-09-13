extends Resource
class_name ProjectileConfig

## Runtime-adjustable projectile parameters. Initialized from const defaults
## in mech_gym/_ready(). Tweak via the in-game adjuster panel (P to toggle).

# --- Light Plasma ---
@export_range(0.5, 20.0, 0.1) var plasma_life := 6.0
@export_range(0.05, 0.5, 0.01) var plasma_sweep := 0.15
@export_range(5.0, 100.0, 1.0) var plasma_range := 20.0
@export_range(0.05, 1.0, 0.01) var plasma_fire_interval := 0.15

# --- Cannon / Tank Round ---
@export_range(1.0, 50.0, 0.5) var cannon_damage := 10.0
@export_range(10.0, 80.0, 1.0) var cannon_speed := 32.0
@export_range(1.0, 15.0, 0.5) var cannon_blast_radius := 3.0
@export_range(1.0, 15.0, 0.5) var cannon_blast_impulse := 4.0
@export_range(0.1, 2.0, 0.05) var cannon_fire_interval := 0.4
@export_range(20.0, 200.0, 5.0) var cannon_range := 90.0

# --- Physics Toy (Destruction Gym) ---
@export_range(10.0, 80.0, 1.0) var ball_speed := 32.0
@export_range(1.0, 20.0, 0.5) var blast_radius := 8.0
@export_range(1.0, 20.0, 0.5) var blast_impulse := 8.0


func reset_to_defaults() -> void:
	plasma_life = 6.0
	plasma_sweep = 0.15
	plasma_range = 20.0
	plasma_fire_interval = 0.15
	cannon_damage = 10.0
	cannon_speed = 32.0
	cannon_blast_radius = 3.0
	cannon_blast_impulse = 4.0
	cannon_fire_interval = 0.4
	cannon_range = 90.0
	ball_speed = 32.0
	blast_radius = 8.0
	blast_impulse = 8.0
