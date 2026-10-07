"""CastleRPG 효과음(2026-10-07) — 무료 CC0 효과음 묶음에서 골라 다듬어 assets/audio/sfx/<id>_<n>.ogg 로 만든다.
실행: python3 dev/sfx/build_sfx.py <묶음 폴더>  (ffmpeg·numpy 필요)

<묶음 폴더> 안에 아래 압축을 풀어 둔다(폴더 이름 = 압축 이름에서 .zip 뺀 것, 주소·라이선스는 docs/sfx.md):
  kenney_interface-sounds, kenney_impact-sounds, kenney_casino-audio, kenney_music-jingles, kenney_digital-audio  (kenney.nl)
  oga_80-CC0-RPG-SFX_0, oga_100-CC0-SFX_0, oga_25-CC0-bang-sfx, oga_rpg_sound_pack  (opengameart.org)
  oga_magic/ ← freeze.wav, flame.ogg, curemagic/, swishes/  (opengameart.org)

다듬기: 모노 32 kHz, 앞뒤 무음 자르기, 정점 −1 dBFS로 맞춤, 끝 10 ms 페이드, Vorbis q4. 두 소리를 겹친 것(mix)도 여기서 만든다.
천둥(thunder)만 노이즈로 직접 합성한다. 소리 이름·개수는 scripts/sfx.gd SOUNDS와 같아야 한다(tests/run_tests.gd test_sfx).
"""
import os
import subprocess
import sys

import numpy as np

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio", "sfx")

KI = "kenney_interface-sounds/Audio/"
KM = "kenney_impact-sounds/Audio/"
KC = "kenney_casino-audio/Audio/"
KJ = "kenney_music-jingles/Audio/"
RD = "oga_80-CC0-RPG-SFX_0/"
DK = "oga_100-CC0-SFX_0/"
BG = "oga_25-CC0-bang-sfx/"
RP = "oga_rpg_sound_pack/RPG Sound Pack/"
MG = "oga_magic/"


def mix(*layers):
    """겹치기: (경로, 크기 배율, 늦춤 초) 여럿 — 경로만 주면 (경로, 1, 0)."""
    return ("mix", [l if isinstance(l, tuple) else (l, 1.0, 0.0) for l in layers])


def cut(path, start, length):
    return ("cut", path, start, length)


SW = MG + "swishes/swishes/swish-%d.wav"
CURE = MG + "curemagic/Cure%d.wav"

# 소리 이름 → 변형 목록(재생할 때 하나를 고른다). 경로는 <묶음 폴더> 기준.
RECIPES = {
    # 화면
    "click": [KI + "select_001.ogg", KI + "select_002.ogg"],
    "tab": [KI + "toggle_001.ogg", KI + "toggle_002.ogg"],
    "error": [KI + "error_004.ogg", KI + "error_007.ogg"],
    "confirm": [KI + "confirmation_003.ogg"],
    # 보상·성장
    "coin": [RD + "item_coins_01.ogg", RD + "item_coins_02.ogg", RD + "item_coins_03.ogg"],
    "gem": [RD + "item_gem_01.ogg", RD + "item_gem_03.ogg"],
    "reward": [mix(RD + "item_coins_02.ogg", (RD + "item_gem_04.ogg", 0.8, 0.05))],
    "level_up": [KJ + "Pizzicato jingles/jingles_PIZZI15.ogg"],
    "promote": [KJ + "Steel jingles/jingles_STEEL00.ogg"],
    "upgrade_done": [KJ + "Pizzicato jingles/jingles_PIZZI10.ogg"],
    "victory": [KJ + "Pizzicato jingles/jingles_PIZZI02.ogg"],
    "defeat": [KJ + "Pizzicato jingles/jingles_PIZZI01.ogg"],
    # 모집
    "card": [KC + "card-slide-1.ogg", KC + "card-place-1.ogg", KC + "card-slide-5.ogg"],
    "gacha_sr": [RD + "item_gem_04.ogg"],
    "gacha_ssr": [mix(KJ + "Steel jingles/jingles_STEEL02.ogg", (CURE % 1, 0.7, 0.0))],
    # 전투 — 평타·피격
    "hit": [KM + "impactPunch_medium_00%d.ogg" % i for i in range(5)],
    "crit": [mix(KM + "impactPunch_heavy_00%d.ogg" % i, (RD + "blade_0%d.ogg" % (i + 1), 0.7, 0.0)) for i in range(3)],
    "skill_hit": [KM + "impactSoft_medium_00%d.ogg" % i for i in range(3)],
    "hurt": [KM + "impactPlate_light_00%d.ogg" % i for i in range(3)],
    "dodge": [SW % 2, SW % 5],
    "heal": [CURE % 2, CURE % 4],
    "swing": [RP + "battle/swing.wav", RP + "battle/swing2.wav", RP + "battle/swing3.wav"],
    "arrow": [SW % 11, SW % 12, SW % 13],
    "bolt": [RD + "spell_02.ogg"],
    "throw": [SW % 3, SW % 8],
    "death": [RD + "creature_hurt_01.ogg", RD + "creature_misc_05.ogg", RD + "creature_misc_01.ogg"],
    "boss_roar": [RD + "creature_roar_01.ogg", RD + "creature_roar_03.ogg"],
    "gate_break": [mix(KM + "impactWood_heavy_002.ogg", (BG + "bang_03.ogg", 0.8, 0.0))],
    # 스킬(scripts/sfx.gd SKILL이 스킬 → 무리를 고른다)
    "sk_fire": [RD + "spell_fire_06.ogg", RD + "spell_fire_07.ogg", MG + "flame.ogg"],
    "sk_boom": [BG + "bang_03.ogg", BG + "bang_07.ogg", BG + "bang_09.ogg"],
    "sk_ice": [cut(MG + "freeze.wav", 0.0, 1.3)],
    "sk_thunder": ["synth:thunder:1", "synth:thunder:2"],
    "sk_holy": [mix(CURE % 5, (DK + "bell_02.ogg", 0.5, 0.0)), CURE % 1],
    "sk_heal": [CURE % 3, CURE % 6],
    "sk_earth": [mix(KM + "impactSoft_heavy_00%d.ogg" % i, (BG + "cannon_0%d.ogg" % (i + 1), 0.6, 0.0)) for i in range(2)],
    "sk_wind": [mix(SW % 7, (SW % 9, 0.9, 0.09), (SW % 4, 0.8, 0.18))],
    "sk_poison": [RD + "creature_slime_01.ogg", RD + "creature_slime_03.ogg"],
    "sk_dark": [RD + "spell_01.ogg", RP + "battle/magic1.wav"],
    "sk_shout": [DK + "gong_02.ogg"],
    "sk_roar": [RD + "creature_roar_02.ogg"],
    "sk_shield": [RD + "metal_02.ogg", KM + "impactMetal_light_001.ogg"],
    "sk_summon": [mix(RP + "battle/magic1.wav", (CURE % 7, 0.6, 0.1))],
    "sk_slash": [mix(RD + "blade_0%d.ogg" % i, (RP + "battle/swing%s.wav" % ("" if i == 1 else i), 0.8, 0.0)) for i in (1, 2, 3)],
    "sk_arrows": [mix(SW % 11, (SW % 12, 0.9, 0.07), (SW % 13, 0.85, 0.13), (SW % 11, 0.7, 0.21))],
    "sk_shot": [mix(SW % 12, (RP + "battle/swing2.wav", 0.6, 0.0))],
    "sk_repair": [KM + "impactWood_heavy_000.ogg", KM + "impactWood_heavy_003.ogg"],
}


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32).astype(np.float64)
    if x.size == 0:
        raise SystemExit("빈 소리: " + path)
    return x


def thunder(seed):
    """천둥: 날카로운 갈라짐(고역 노이즈, 짧게) + 낮게 굴러가는 울림(저역 노이즈, 길게)."""
    rng = np.random.default_rng(seed)
    n = int(SR * 1.4)
    t = np.arange(n) / SR
    crack = rng.standard_normal(n) * np.exp(-t / 0.05)
    crack = np.diff(crack, prepend=0.0)  # 고역 쪽으로
    rumble = rng.standard_normal(n)
    for _ in range(3):  # 한 극 저역 통과 세 번
        a = 0.03
        y = np.zeros(n)
        acc = 0.0
        for i in range(n):
            acc += a * (rumble[i] - acc)
            y[i] = acc
        rumble = y
    rumble *= np.exp(-t / 0.45) * (1.0 - np.exp(-t / 0.03))
    rumble /= np.abs(rumble).max()
    crack /= np.abs(crack).max()
    return crack * 0.8 + rumble


def source(spec, base):
    if isinstance(spec, str) and spec.startswith("synth:thunder:"):
        return thunder(int(spec.rsplit(":", 1)[1]))
    if isinstance(spec, str):
        return load(os.path.join(base, spec))
    if spec[0] == "cut":
        x = load(os.path.join(base, spec[1]))
        a = int(spec[2] * SR)
        return x[a:a + int(spec[3] * SR)]
    out = np.zeros(0)
    for path, gain, delay in spec[1]:
        x = load(os.path.join(base, path))
        x = x / max(1e-9, np.abs(x).max()) * gain
        x = np.concatenate([np.zeros(int(delay * SR)), x])
        if x.size > out.size:
            out = np.concatenate([out, np.zeros(x.size - out.size)])
        out[:x.size] += x
    return out


def polish(x):
    peak = np.abs(x).max()
    on = np.where(np.abs(x) > peak * 10 ** (-45 / 20))[0]
    x = x[max(0, on[0] - int(0.002 * SR)):]
    on = np.where(np.abs(x) > peak * 10 ** (-50 / 20))[0]
    x = x[:on[-1] + 1]
    x = x / np.abs(x).max() * 10 ** (-1 / 20)
    fade = min(int(0.01 * SR), x.size)
    x[-fade:] *= np.linspace(1.0, 0.0, fade)
    return x.astype(np.float32)


def write(x, path):
    subprocess.run(["ffmpeg", "-v", "quiet", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "4", path], input=x.tobytes(), check=True)


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    base = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".ogg"):
            os.remove(os.path.join(OUT, f))
    total = 0
    for sid, specs in RECIPES.items():
        for i, spec in enumerate(specs):
            path = os.path.join(OUT, "%s_%d.ogg" % (sid, i))
            write(polish(source(spec, base)), path)
            total += os.path.getsize(path)
        print("%-12s %d" % (sid, len(specs)))
    print("총 %.1f KB" % (total / 1024))


if __name__ == "__main__":
    main()
