# Setup Instructions: Fork & Run Box3D_Demo

**Purpose:** Get `SifuInTheShell/Box3D_Demo` (Godot 4.7 + Box3D destruction demo)
forked, running, and verified locally as the base for the mech combat POC.
Follow steps in order. Each step has a verification check — do not proceed to
the next step until the check passes.

## 0. Prerequisites

- `git` installed and on PATH.
- `gh` (GitHub CLI) installed and authenticated, OR a GitHub account you can
  fork through manually in the browser.
- ~2 GB free disk space.
- Platform-specific, checked in Step 3.

## 1. Fork the repository

If `gh` is available:

```bash
gh repo fork SifuInTheShell/Box3D_Demo --clone=false
```

This creates `<your-username>/Box3D_Demo` on GitHub without cloning yet.
If `gh` isn't available, fork manually at
`https://github.com/SifuInTheShell/Box3D_Demo` (click "Fork") before continuing.

**Verify:** confirm the fork exists at
`https://github.com/<your-username>/Box3D_Demo`.

## 2. Clone your fork

```bash
git clone https://github.com/<your-username>/Box3D_Demo.git
cd Box3D_Demo
git remote add upstream https://github.com/SifuInTheShell/Box3D_Demo.git
git remote -v
```

**Verify:** `git remote -v` lists both `origin` (your fork) and `upstream`
(the original repo).

## 3. Get the correct Godot version

Requires **Godot 4.7.1** (standalone binary, no installer needed). Download
from `https://godotengine.org/download` for your platform. Confirm the exact
version:

```bash
godot --version
```

**Verify:** output starts with `4.7.1`. If a different Godot is already on
PATH, download 4.7.1 separately and invoke it by full path in later steps
rather than replacing the system default.

## 4. Platform-specific setup

### Windows or Linux (no build required)

Prebuilt Box3D GDExtension libraries are already committed to `game/bin/`.
Skip to Step 5.

### macOS (build required)

The repo does not ship prebuilt macOS libraries. Build the extension first:

```bash
cd extern/box3d-godot/godot
pip install scons
# Requires Xcode command line tools (clang) for the C/C++ toolchain
scons platform=macos
```

Then deploy and register the library:

```bash
cp demo/bin/libbox3d_godot.macos.* ../../../game/bin/
```

Edit `game/bin/box3d.gdextension` and add the macOS library entry — copy the
macOS lines from the reference manifest at
`extern/box3d-godot/godot/demo/bin/box3d.gdextension` if present, or add an
entry following the existing Windows/Linux pattern in that file.

**Verify:** `game/bin/` contains a `libbox3d_godot.macos.*` file, and
`game/bin/box3d.gdextension` references it.

## 5. Headless verification (no window required)

Run the settle test — proves the demo city loads and stabilizes under Box3D
without crashing:

```bash
godot --headless --path game res://scenes/test/settle_test.tscn
echo "Exit code: $?"
```

**Verify:** exit code is `0`. A non-zero exit code means the build/deploy step
failed — recheck Step 4 before continuing.

Run the sim-core unit tests:

```bash
godot --headless --path game -s systems/fire/fire_sim_test.gd
godot --headless --path game -s systems/glass/glass_sim_test.gd
godot --headless --path game -s systems/wind/wind_sim_test.gd
godot --headless --path game -s systems/ambient/ambient_sim_test.gd
godot --headless --path game -s systems/demolition/demo_math_test.gd
```

**Verify:** each command exits `0`.

## 6. Windowed verification (visual check)

Open the project in the editor and run it:

```bash
godot --path game
```

Or open `game/project.godot` in the Godot editor and press F5.

In the running game, press:
- `1` — block tower scene (baseline sanity check: knock it down with LMB)
- `3` — destructible city scene (this is the reference environment for the
  mech POC; press `3` again to toggle medium/large city size)

**Verify:** both scenes load, LMB fires a cannonball that visibly fractures
structures into debris, and the city scene runs without stutter at
medium size.

## 7. Optional: performance baseline

```bash
godot --headless --path game res://scenes/test/bench_stress.tscn
```

This reports the CPU-solver ceiling on your machine (2k→96k bodies). Record
the result now — useful later for judging whether a destructible city block
sized for the mech POC is within budget on your target hardware.

## 8. Set up your working branch

```bash
git checkout -b mech-poc
git push -u origin mech-poc
```

Do all POC development on this branch, not `main`, so you can pull upstream
fixes to the Box3D binding later without conflict.

**Verify:** `git status` shows branch `mech-poc`, and it exists on `origin`
(check `https://github.com/<your-username>/Box3D_Demo/branches`).

## Done

At this point you have a running, verified local copy of the destruction demo
on its own branch, ready for the mech POC work described in the game design
document. Do not modify anything under `extern/box3d-godot/` directly — new
gameplay code belongs in `game/scenes/`, `game/lib/`, and new files under
`game/` following the existing layout (`systems/` for engine-free sim logic,
`lib/` for the shared engine layer).