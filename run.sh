#!/usr/bin/env bash
# Run the mech-wreckers demo. No dependencies beyond Godot (already in tools/).
#
#   ./run.sh                 run the default scene (mech gym)
#   ./run.sh <scene.tscn>    run a specific scene
#   ./run.sh --editor        open the Godot editor
#   ./run.sh --headless ...  run headless (tests / CI)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_DIR="$SCRIPT_DIR/game"

# Locate the Godot binary: $GODOT env var wins, then known relative paths.
find_godot() {
	if [[ -n "${GODOT:-}" && -x "$GODOT" ]]; then
		echo "$GODOT"
		return
	fi
	local candidates=(
		"$SCRIPT_DIR/../tools/Godot_v4.7.1-stable_linux.x86_64"
		"$SCRIPT_DIR/../../tools/Godot_v4.7.1-stable_linux.x86_64"
		"$SCRIPT_DIR/tools/Godot_v4.7.1-stable_linux.x86_64"
	)
	local c
	for c in "${candidates[@]}"; do
		if [[ -x "$c" ]]; then
			echo "$c"
			return
		fi
	done
	echo "" >&2
}

GODOT_BIN="$(find_godot)"
if [[ -z "$GODOT_BIN" ]]; then
	echo "Godot binary not found. Set GODOT=/path/to/godot or place it under tools/." >&2
	exit 1
fi

echo "Godot: $GODOT_BIN"
echo "Game:  $GAME_DIR"

MODE="run"
SCENE=""
ARGS=()
for a in "$@"; do
	case "$a" in
		--editor) MODE="editor" ;;
		--headless) MODE="headless" ;;
		-*) ARGS+=("$a") ;;
		*) SCENE="$a" ;;
	esac
done

case "$MODE" in
	editor)
		exec "$GODOT_BIN" --editor --path "$GAME_DIR" "${ARGS[@]}"
		;;
	headless)
		exec "$GODOT_BIN" --headless --path "$GAME_DIR" "${ARGS[@]}" $SCENE
		;;
	run)
		exec "$GODOT_BIN" --path "$GAME_DIR" "${ARGS[@]}" $SCENE
		;;
esac