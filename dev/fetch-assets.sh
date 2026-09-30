#!/usr/bin/env bash
# KayKit(CC0) 에셋을 고정 커밋에서 받아 assets/models/ 아래에 둔다. 다시 실행해도 같은 결과.
# 출처: https://github.com/KayKit-Game-Assets (Kay Lousberg, CC0 — 표기 의무 없음)
set -euo pipefail
cd "$(dirname "$0")/.."
RAW=https://raw.githubusercontent.com/KayKit-Game-Assets
ADV_REPO="KayKit-Character-Pack-Adventures-1.0/672074b73ba276876a19e8816ecdc5241817ab47"
SKE_REPO="KayKit-Character-Pack-Skeletons-1.0/15b62b9bad122f72926c10fb14d622c73819fa54"
HEX_REPO="KayKit-Medieval-Hexagon-Pack-1.0/84fa4e91af6a88989be7c99e0891cede11f2ca38"
ADV="$RAW/$ADV_REPO/addons/kaykit_character_pack_adventures"
SKE="$RAW/$SKE_REPO/addons/kaykit_character_pack_skeletons"
HEX="$RAW/$HEX_REPO/addons/kaykit_medieval_hexagon_pack/Assets/gltf"
C=assets/models/characters
P=assets/models/props
H=assets/models/hex

get() { mkdir -p "$(dirname "$2")"; curl -sfL -o "$2" "$1" || { echo "download failed: $1" >&2; exit 1; }; }

for f in Knight Rogue_Hooded; do get "$ADV/Characters/gltf/$f.glb" "$C/$f.glb"; done
for f in Skeleton_Minion Skeleton_Warrior; do get "$SKE/Characters/gltf/$f.glb" "$C/$f.glb"; done
for f in arrow.gltf arrow.bin rogue_texture.png; do get "$ADV/Assets/gltf/$f" "$P/$f"; done
for f in Skeleton_Blade.gltf Skeleton_Blade.bin Skeleton_Axe.gltf Skeleton_Axe.bin skeleton_texture.png; do
	get "$SKE/Assets/gltf/$f" "$P/$f"
done
for f in castle barracks tavern blacksmith home_B lumbermill mine windmill; do
	for e in gltf bin; do get "$HEX/buildings/blue/building_${f}_blue.$e" "$H/building_${f}_blue.$e"; done
done
for f in trees_A_medium trees_B_large tree_single_A tree_single_B rock_single_A rock_single_C rock_single_E mountain_A mountain_B mountain_C; do
	for e in gltf bin; do get "$HEX/decoration/nature/$f.$e" "$H/$f.$e"; done
done
get "$HEX/buildings/blue/hexagons_medieval.png" "$H/hexagons_medieval.png"

{
	for repo in "$ADV_REPO" "$SKE_REPO" "$HEX_REPO"; do
		echo "===== https://github.com/KayKit-Game-Assets/${repo%%/*} @ ${repo##*/}"
		curl -sfL "$RAW/$repo/LICENSE.txt"
		echo
	done
} > assets/models/LICENSE-KayKit.txt
echo "ok: $(find assets/models -type f | wc -l) files"
