# Mech Destruction POC — Game Design Document

## Pitch

Start as a small (man sized) mech in a destructible city. Destroy vehicles, turrets, and
other mechs. Defeated enemies leave physical wreckage. The player mech
absorbs nearby wreckage and grows in size and capability, letting it take on
tougher enemies and level larger structures. Loosely: mech combat +
Katamari-style growth-through-consumption + Red Faction–style destruction.

## Scope of this document

This document covers the **core loop and phased build plan for a proof of
concept only**. Resource economy (metal/energy), upgrade trees, and weapon
purchasing are explicitly **out of scope here** and will be designed in a
follow-up pass once the core loop is validated. Where the POC needs a stand-in
for those systems (e.g. "the mech gets bigger somehow"), it uses the simplest
possible placeholder, noted explicitly per phase.

## Technical foundation

- **Engine:** Godot 4.7.1, forked from `SifuInTheShell/Box3D_Demo` (see
  `agent-setup-instructions.md`).
- **Physics:** Box3D via the `box3d-godot` GDExtension, inherited from the
  fork — fracture, debris budgeting, GPU-instanced rendering, and structural
  building panels are already implemented and should be reused, not rebuilt.
- **Assets:** original low-poly mech and vehicle models built from scratch.
- **Out of scope for the POC entirely:** multiplayer/networking, save
  systems, menus beyond a bare restart, sound design, narrative/campaign
  content, art polish beyond "readable at a glance."

## Core loop (POC version, no economy)

1. Player mech spawns in a destructible city district.
2. Player fires a weapon at enemies (turrets, vehicles) and/or buildings.
3. Enemies have HP; at 0 HP they are destroyed and spawn physical wreckage
   (reusing the fork's fracture system).
4. Player mech moves near wreckage; wreckage is absorbed (removed from the
   world) once in range.
5. After absorbing enough wreckage (placeholder counter, no UI polish), the
   mech's tier increases: swap to a larger mesh/collider/mass, unlock a
   stronger placeholder weapon.
6. Loop repeats against tougher enemies until the POC's fixed enemy roster
   is cleared or the player is destroyed.

No metal/energy currency, no purchasable upgrades, and no branching tech
tree in this version — tiering is automatic and linear, purely to prove the
loop is fun before designing the economy on top of it.

---

## Phase 0 — Foundation Verified

**Goal:** Confirm the inherited tech actually does what we're relying on it
for, before writing any game-specific code.

**Work:**
- Complete `agent-setup-instructions.md` end to end.
- Manually trigger destruction in the city scene (scene `3`) and confirm
  buildings fracture, debris is capped, and performance holds at medium city
  size on target hardware.
- Read `game/systems/demolition/`, `game/lib/` to understand the existing
  fracture, panel-graph, and body-spawning APIs before extending them.

**Exit criteria:** Demo runs from a clean clone per the setup doc, settle
test and unit tests pass, and you can point to the specific functions you'll
call to spawn fractures and query nearby debris.

**Deferred:** nothing gameplay-related yet — this phase is pure verification.

---

## Phase 1 — Player Mech Shell

**Goal:** A controllable mech that exists in the destructible city, with no
combat yet.

**Work:**
- Placeholder mech mesh (a boxy low-poly capsule-on-legs is fine — visual
  quality is not a Phase 1 concern).
- `Box3DBody` (or `Box3DCharacterBody`) locomotion: forward/back/strafe,
  turning, basic gravity/ground contact in the city scene.
- Third-person camera with mouse-look.
- Mech can walk through the city scene from Phase 0 without falling through
  geometry or getting stuck on debris.

**Exit criteria:** You can walk the mech across the medium-size city scene,
bump into a building, and nothing breaks (physically or in the engine sense).

**Deferred:** any weapon, any HP/damage system, any enemy.

---

## Phase 2 — Combat Basics

**Goal:** The mech can damage and destroy something.

**Work:**
- One placeholder weapon (hitscan or simple projectile — pick whichever is
  less code; hitscan is usually faster to prototype).
- Damage application: weapon hits apply damage to a target's HP.
- Wire weapon damage into the fork's existing fracture trigger so hits above
  a threshold fracture the target (buildings) or destroy it outright
  (enemies, once added below).
- One stationary enemy type: a turret with fixed position, simple
  line-of-sight detection, and a basic attack (no pathfinding needed).
- Player mech has its own HP and a basic "destroyed" state (scene reload is
  an acceptable placeholder for death/respawn).

**Exit criteria:** Player can walk up to a turret, shoot it, watch it take
damage and eventually fracture/destroy, while also being able to damage a
building with the same weapon and see it locally fracture per the fork's
existing panel system.

**Deferred:** enemy variety beyond one turret type, any notion of "weapon
tiers," resource cost for firing.

---

## Phase 3 — Wreckage & Absorption (Placeholder Growth Trigger)

**Goal:** Prove the "destroy → wreckage → absorb → grow" loop is mechanically
satisfying, using the simplest possible stand-in for resources.

**Work:**
- On enemy destruction, tag spawned debris chunks (from the fork's fracture
  system) as "absorbable."
- Overlap-sphere query around the player mech each tick (or on a timer) to
  find absorbable debris in range.
- On contact: despawn the debris chunk, increment a simple integer counter
  (`absorbedCount`) — no UI beyond a debug label for now.
- No metal/energy naming or economy logic yet — this is literally just a
  counter that will later be replaced by the real resource system.

**Exit criteria:** Destroying a turret leaves debris; walking the mech near
that debris makes it disappear and increments the counter, visible in a
debug overlay.

**Deferred:** any resource UI, spending logic, multiple resource types
(metal vs. energy) — all explicitly part of the later economy design pass.

---

## Phase 4 — Growth Prototype

**Goal:** Prove that "the mech gets physically bigger and stronger" is fun
and technically sound, using a hardcoded threshold instead of a real economy.

**Work:**
- Define 2–3 discrete mech tiers (small/medium/large), each a separate
  pre-built mesh + compound collider + mass + weapon mount point. Avoid
  continuous scaling — discrete swaps are simpler and avoid joint/collider
  rescaling issues.
- When `absorbedCount` crosses a hardcoded threshold, swap the active mech
  body to the next tier (despawn small body, spawn medium body at the same
  position/orientation, carry over camera state).
- Larger tiers get a visibly stronger placeholder weapon (bigger
  damage number, bigger projectile/hitscan visual — no real balancing yet).

**Exit criteria:** Playing through Phase 2's combat loop repeatedly against
turrets causes a visible, working tier-up at least once in a single play
session, and the larger mech can damage something the small mech couldn't
(e.g. a reinforced wall section).

**Deferred:** tuning of thresholds, branching upgrade choices, energy costs
for tiering — all part of the later economy/upgrade design.

---

## Phase 5 — Enemy Variety & Building Destruction Tuning

**Goal:** Make the loop feel like a game rather than a tech test, by giving
the player more than one thing to fight and tying weapon power to building
destructibility.

**Work:**
- Add one mobile enemy type: a simple patrol/pursue vehicle using Godot's
  navigation (`NavigationAgent3D`) or a basic waypoint state machine — no
  need for sophisticated AI.
- Tune the fork's fracture thresholds so that the small mech's weapon can
  damage light structures (fences, glass, thin walls) but not reinforced
  buildings, while the medium/large mech tiers can.
- Confirm turret + vehicle + player-mech combat all interact correctly with
  the shared HP/damage/fracture pipeline from Phase 2.

**Exit criteria:** A single play session can involve destroying a turret,
being chased by a vehicle, tiering up, and then successfully damaging a
building tier that was previously immune to the small mech's weapon.

**Deferred:** more than one vehicle/turret variant, boss-scale enemies,
mission structure.

---

## Phase 6 — POC Vertical Slice

**Goal:** A single playable session, start to finish, that demonstrates the
whole intended loop in one coherent space.

**Work:**
- One fixed city district (reuse/trim the fork's existing city scene rather
  than building new content).
- Fixed enemy roster: several turrets, a couple of patrol vehicles, placed
  by hand for a reasonable difficulty curve as the mech tiers up.
- Player can start as the small mech and, through the existing loop, reach
  the large tier and clear the district.
- Minimal HUD: HP, absorbed-count/tier indicator, nothing else.

**Exit criteria:** A new player can be handed the build with zero
explanation, complete the loop (start small → destroy enemies → absorb
wreckage → grow → destroy tougher stuff → clear the district), and describe
back what the game is about without being told.

**Deferred (explicitly, for the next design pass):** metal/energy resource
system, upgrade trees, weapon purchasing/switching, multiple districts,
narrative framing, art pass, audio, multiplayer.

---

## What happens after this POC

Once Phase 6 is playable and the loop holds up, the next design document
should cover: the metal/energy resource system (rates, costs, sinks),
upgrade trees and weapon unlocks, how absorption interacts with resource
type (some wreckage = metal, some = energy?), and whether growth becomes
player-chosen (spend resources to tier up) rather than automatic.