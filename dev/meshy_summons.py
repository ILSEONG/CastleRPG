"""소환수 Meshy 생성(docs/meshy-assets.md "소환수"). 부품 나누기는 dev/meshy_summon_fit.py.

  python3 dev/meshy_summons.py concept <kind>...   컨셉(image-to-image, 참조 = dev/meshy/arteon_concept.png) 시작
  python3 dev/meshy_summons.py model <kind>...     끝난 컨셉으로 3D(image-to-3d meshy-t2, 텍스처) 시작 — 컨셉을 눈으로 본 뒤에
  python3 dev/meshy_summons.py poll                상태 갱신, 끝난 것 내려받기(dev/meshy/out/summons/<kind>/)

키·프록시는 dev/meshy_heroes.py와 같다. 상태는 dev/meshy/out/summons/state.json.
크레딧(2026-10): 컨셉 nano-banana-2 6 + 3D meshy-t2 smart-topology + 텍스처 15 = 소환수 하나 21.
팔·날개가 따로 움직이는 소환수는 그 부위가 몸에서 떨어진(틈이 있는) 모양으로 그려 부품으로 나눌 수 있게 한다.
"""
import base64, json, os, sys, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshy_heroes import REF, req  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "meshy", "out", "summons")
STATE = os.path.join(OUT, "state.json")

STYLE = ("Same art style, front camera and plain light gray background as the reference image: stylized low-poly faceted 3D game "
         "creature, flat-shaded crisp facets, chunky cute proportions. New character: ")
TAIL = " Full body, front view, symmetric, nothing held."

# 소환수 생김새(summon.gd 주석을 영어로).
DESC = {
    "golem": ("stone golem, wide boulder torso of gray stone blocks with brown ore veins, small head sunk between the shoulders "
              "with glowing yellow eyes, glowing cyan crystals on the back, two short stubby legs. Arms are separate floating rock "
              "chunks with huge boulder fists, hanging beside the torso with a clear gap at the shoulder, not attached."),
}


def load():
    return json.load(open(STATE)) if os.path.exists(STATE) else {}


def save(s):
    os.makedirs(OUT, exist_ok=True)
    json.dump(s, open(STATE, "w"), indent=1, ensure_ascii=False)


def concept(kinds):
    ref = "data:image/png;base64," + base64.b64encode(open(REF, "rb").read()).decode()
    for k in kinds:
        prompt = STYLE + DESC[k] + TAIL
        assert len(prompt) <= 600, (k, len(prompt))
        t = req("POST", "/image-to-image", {"ai_model": "nano-banana-2", "prompt": prompt, "reference_image_urls": [ref]})
        s = load()
        s.setdefault(k, {})["concept"] = {"id": t["result"], "status": "PENDING"}
        save(s)
        print(k, "concept", t["result"])


def model(kinds):
    for k in kinds:
        s = load()
        body = {"input_task_id": s[k]["concept"]["id"], "model_type": "smart-topology", "ai_model": "meshy-t2",
                "should_texture": True, "target_formats": ["glb"]}
        t = req("POST", "/image-to-3d", body)
        s[k]["model"] = {"id": t["result"], "status": "PENDING", "ai_model": body["ai_model"]}
        save(s)
        print(k, "model", t["result"])


def poll():
    s = load()
    for k, e in s.items():
        for kind, path in (("concept", "/image-to-image/"), ("model", "/image-to-3d/")):
            t = e.get(kind)
            if not t or t.get("saved") or t["status"] in ("FAILED", "CANCELED"):
                continue
            r = req("GET", path + t["id"])
            t["status"] = r["status"]
            if r["status"] == "SUCCEEDED":
                os.makedirs(os.path.join(OUT, k), exist_ok=True)
                url = r["image_urls"][0] if kind == "concept" else r["model_urls"]["glb"]
                urllib.request.urlretrieve(url, os.path.join(OUT, k, "concept.png" if kind == "concept" else k + "_meshy.glb"))
                t["saved"] = True
            print(k, kind, t["status"], r.get("progress"))
    save(s)


if __name__ == "__main__":
    {"concept": lambda: concept(sys.argv[2:]), "model": lambda: model(sys.argv[2:]), "poll": poll}[sys.argv[1]]()
