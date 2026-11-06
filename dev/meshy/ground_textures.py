"""맵 바닥 손그림 질감(2026-11-06 사용자 "맵 퀄리티 확연하게, 새롭게 하이 퀄리티로"): Meshy 그림(nano-banana-pro, 1:1)으로
맵마다 위에서 내려다본 바닥 질감을 만들고, 이어 붙여도 이음매가 안 보이게(seamless) 다듬어 assets/textures/ground/<이름>.png(1024)로 둔다.
참고: Rise of Kingdoms·Lords Mobile 성 밖 풀밭, 메이플 키우기 필드 — 부드러운 손그림 질감.

  python3 dev/meshy/ground_textures.py gen [이름...]   그림 요청(이름 없으면 전부)
  python3 dev/meshy/ground_textures.py poll            끝난 것 내려받아 seamless로 다듬기
"""
import json, os, sys, urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from meshy_heroes import req  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "ground")
DEST = os.path.join(ROOT, "assets", "textures", "ground")
STATE = os.path.join(OUT, "state.json")

BASE = ("Seamless tileable square texture, viewed straight from above (orthographic top-down, no perspective, no horizon), "
        "stylized hand-painted ground for a premium fantasy mobile strategy RPG like Rise of Kingdoms and Lords Mobile. "
        "Soft painterly brush strokes, rich but natural colors, even soft lighting, no cast shadows, no objects, "
        "no characters, no text, no border, edges continue seamlessly. ")
TEX = {
    "meadow": "Lush green meadow grass: many small painted grass blade clumps in several greens with a few tiny yellow and white wildflowers and small bare soil spots.",
    "dirt_road": "Worn brown dirt road: packed earth with small pebbles, faint wheel ruts and a few tufts of grass.",
    "cobble": "Castle courtyard paving: irregular light gray-beige cobblestones with thin dark mortar lines and subtle moss in the cracks.",
    "mine_dirt": "Ochre gold-mine canyon floor: sandy orange-brown packed dirt with small rocks, gravel and a few glinting gold specks.",
    "crystal_floor": "Cold blue-gray cave floor: slate stone with gravel, small cracks and a few tiny glowing cyan crystal shards.",
    "hall_floor": "Ruined castle hall floor: large dark gray stone slabs, cracked and scorched with soot, ember-glow in a few cracks.",
    "temple_grass": "Forest temple courtyard grass: deep green grass with moss patches, clover and a few small fallen leaves.",
    "temple_stone": "Old sandstone temple paving: large warm beige square slabs, weathered, mossy cracks between them.",
    "sand": "Arena sand: warm golden-beige raked sand with faint footprints, small pebbles and scuffs.",
    "basalt": "Volcanic lair floor: dark brown-black basalt rock with thin glowing orange lava cracks and ash.",
    "crypt_floor": "Haunted crypt floor: dark blue-gray old stone tiles with moss, cracks and scattered bone fragments.",
    "nest_floor": "Spider nest cave floor: dark brown earth with roots, small rocks and thin white cobweb strands.",
}


def load():
    return json.load(open(STATE)) if os.path.exists(STATE) else {}


def save(s):
    os.makedirs(OUT, exist_ok=True)
    json.dump(s, open(STATE, "w"), indent=1)


def gen(names):
    s = load()
    for n in names or TEX:
        t = req("POST", "/text-to-image", {"ai_model": "nano-banana-pro", "prompt": BASE + TEX[n], "aspect_ratio": "1:1"})
        s[n] = {"id": t["result"], "status": "PENDING"}
        save(s)
        print(n, t["result"])


def seamless(src, dst, size=1024):
    from PIL import Image
    import numpy as np  # noqa
    im = Image.open(src).convert("RGB")
    g = np.asarray(im).astype(np.float32)
    rows, cols = g.std(axis=(1, 2)), g.std(axis=(0, 2))  # 그림 둘레의 민무늬 테두리(가끔 회색 액자)를 잘라 낸다
    r0 = int(np.argmax(rows > 12)); r1 = len(rows) - int(np.argmax(rows[::-1] > 12))
    c0 = int(np.argmax(cols > 12)); c1 = len(cols) - int(np.argmax(cols[::-1] > 12))
    pad = 6 if (r0, c0) != (0, 0) or r1 != len(rows) else 0
    im = im.crop((c0 + pad, r0 + pad, c1 - pad, r1 - pad)).resize((size, size), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32)
    b = np.roll(np.roll(a, size // 2, 0), size // 2, 1)  # 가운데로 옮긴 사본: 이음매가 가운데 +자
    t = np.abs(np.linspace(-1, 1, size))  # 0 = 가운데, 1 = 가장자리
    w1 = np.clip((t - 0.55) / 0.4, 0, 1)
    w = np.maximum(w1[None, :], w1[:, None])[..., None]  # 가장자리 가까이는 사본(가장자리가 이어진다), 가운데는 원본
    out = a * (1 - w) + b * w
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    Image.fromarray(out.clip(0, 255).astype(np.uint8)).save(dst)


def poll():
    s = load()
    for n, t in s.items():
        if t.get("saved") or t["status"] in ("FAILED", "CANCELED"):
            continue
        r = req("GET", "/text-to-image/" + t["id"])
        t["status"] = r["status"]
        if r["status"] == "SUCCEEDED":
            raw = os.path.join(OUT, n + "_raw.png")
            urllib.request.urlretrieve(r["image_urls"][0], raw)
            seamless(raw, os.path.join(DEST, n + ".png"))
            t["saved"] = True
        print(n, t["status"])
    save(s)


if __name__ == "__main__":
    if sys.argv[1] == "gen":
        gen(sys.argv[2:])
    else:
        poll()
