"""길드 드래곤 최고 설정 재생성(2026-11-06 사용자 "길드 드래곤 퀄리티좀 높여줘"): 지금 드래곤 렌더를 참조로 같은 자세(네 발, 머리 위,
날개를 옆으로 넓게)의 고급 컨셉을 만들고, 고른 컨셉으로 Meshy 최신 모델·정밀(4k) 지오메트리·4K 텍스처·리메시 없음 3D를 만든다.
참고: 로드 모바일·서머너즈 워의 드래곤 레이드 보스(비늘 결, 가시, 날개 막의 핏줄).

  python3 dev/meshy_dragon_hq.py concept <ref.png> <variant>...   컨셉(image-to-image, nano-banana-2, 6크레딧씩)
  python3 dev/meshy_dragon_hq.py hq <variant>                     고른 컨셉으로 3D(35크레딧)
  python3 dev/meshy_dragon_hq.py poll                             상태 갱신, 끝난 것 내려받기(dev/meshy/out/dragon_hq/<variant>/)

그다음 게임 면 수로 줄이고(dev/meshy_decimate.py --tris N --tex 2048, 머리 따로 줄이기 없이) 부품으로 나눈다(dev/meshy_dragon_fit.py).
키·프록시는 dev/meshy_heroes.py와 같다.
"""
import base64, json, os, sys, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshy_heroes import req  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "meshy", "out", "dragon_hq")
STATE = os.path.join(OUT, "state.json")

BASE = ("Redesign this dragon as a premium mobile RPG raid boss, like the dragon bosses of Lords Mobile and Summoners War: "
        "stylized 3D game creature with rich hand-painted textures and fine sculpted detail, not low-poly. Keep the same pose: "
        "front-left three-quarter view, four legs planted, head up, two wings spread wide horizontally to the sides, long tail "
        "behind. ")
TAIL = " Full body, nothing else in the picture, plain light gray background."
VARIANTS = {
    "crimson": ("Crimson red dragon with detailed overlapping scales, a row of sharp black back spikes, ridged cream belly "
                "plates, two big curved ivory horns, glowing amber eyes, sharp teeth, black claws, spiked tail tip, veined dark "
                "red wing membranes."),
    "armored": ("Dark crimson dragon covered in heavy armored scale plates with sharp edges, black horns sweeping back, glowing "
                "orange eyes, ember-orange glow between the chest plates, black claws, bladed tail tip, torn veined wing "
                "membranes."),
    "obsidian": ("Black obsidian dragon with glowing lava-orange cracks between the scales, glowing red-orange chest and throat, "
                 "jagged black horns and spikes, fiery orange eyes, smoldering wing membranes with glowing veins, spiked tail."),
}


def load():
    return json.load(open(STATE)) if os.path.exists(STATE) else {}


def save(s):
    os.makedirs(OUT, exist_ok=True)
    json.dump(s, open(STATE, "w"), indent=1, ensure_ascii=False)


def concept(ref_path, names):
    ref = "data:image/png;base64," + base64.b64encode(open(ref_path, "rb").read()).decode()
    for n in names:
        prompt = BASE + VARIANTS[n] + TAIL
        assert len(prompt) <= 800, (n, len(prompt))
        t = req("POST", "/image-to-image", {"ai_model": "nano-banana-2", "prompt": prompt, "reference_image_urls": [ref]})
        s = load()
        s.setdefault(n, {})["concept"] = {"id": t["result"], "status": "PENDING"}
        save(s)
        print(n, "concept", t["result"])


def hq(n):
    s = load()
    body = {"input_task_id": s[n]["concept"]["id"], "should_texture": True, "target_formats": ["glb"],
            "ai_model": "latest", "geometry_resolution": "4k", "texture_resolution": "4k", "should_remesh": False}
    t = req("POST", "/image-to-3d", body)
    s[n]["hq"] = {"id": t["result"], "status": "PENDING"}
    save(s)
    print(n, "hq", t["result"])


def poll():
    s = load()
    for n, e in s.items():
        for kind, path in (("concept", "/image-to-image/"), ("hq", "/image-to-3d/")):
            t = e.get(kind)
            if not t or t.get("saved") or t["status"] in ("FAILED", "CANCELED"):
                continue
            r = req("GET", path + t["id"])
            t["status"] = r["status"]
            if r["status"] == "SUCCEEDED":
                os.makedirs(os.path.join(OUT, n), exist_ok=True)
                url = r["image_urls"][0] if kind == "concept" else r["model_urls"]["glb"]
                urllib.request.urlretrieve(url, os.path.join(OUT, n, "concept.png" if kind == "concept" else n + "_hq.glb"))
                t["saved"] = True
            print(n, kind, t["status"], r.get("progress"))
    save(s)


if __name__ == "__main__":
    {"concept": lambda: concept(sys.argv[2], sys.argv[3:]), "hq": lambda: hq(sys.argv[2]), "poll": poll}[sys.argv[1]]()
