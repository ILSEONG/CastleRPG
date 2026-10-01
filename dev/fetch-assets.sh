#!/usr/bin/env bash
# KayKit(CC0) 캐릭터·무기·화살 에셋을 고정 커밋에서 받아 assets/models/ 아래에 둔다. 다시 실행해도 같은 결과.
# 건물·성·자연물·산은 코드로 만든 메시(scripts/town_kit.gd)라 받지 않는다.
# 출처: https://github.com/KayKit-Game-Assets (Kay Lousberg, CC0 — 표기 의무 없음)
set -euo pipefail
cd "$(dirname "$0")/.."
RAW=https://raw.githubusercontent.com/KayKit-Game-Assets
ADV_REPO="KayKit-Character-Pack-Adventures-1.0/672074b73ba276876a19e8816ecdc5241817ab47"
SKE_REPO="KayKit-Character-Pack-Skeletons-1.0/15b62b9bad122f72926c10fb14d622c73819fa54"
ADV="$RAW/$ADV_REPO/addons/kaykit_character_pack_adventures"
SKE="$RAW/$SKE_REPO/addons/kaykit_character_pack_skeletons"
C=assets/models/characters
P=assets/models/props

get() { mkdir -p "$(dirname "$2")"; curl -sfL -o "$2" "$1" || { echo "download failed: $1" >&2; exit 1; }; }

for f in Knight Rogue_Hooded Rogue Barbarian Mage; do get "$ADV/Characters/gltf/$f.glb" "$C/$f.glb"; done
for f in Skeleton_Minion Skeleton_Warrior; do get "$SKE/Characters/gltf/$f.glb" "$C/$f.glb"; done
for f in arrow.gltf arrow.bin rogue_texture.png; do get "$ADV/Assets/gltf/$f" "$P/$f"; done
for f in Skeleton_Blade.gltf Skeleton_Blade.bin Skeleton_Axe.gltf Skeleton_Axe.bin skeleton_texture.png; do
	get "$SKE/Assets/gltf/$f" "$P/$f"
done

{
	for repo in "$ADV_REPO" "$SKE_REPO"; do
		echo "===== https://github.com/KayKit-Game-Assets/${repo%%/*} @ ${repo##*/}"
		curl -sfL "$RAW/$repo/LICENSE.txt"
		echo
	done
} > assets/models/LICENSE-KayKit.txt
echo "ok: $(find assets/models -type f | wc -l) files"
