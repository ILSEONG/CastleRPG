"""영웅 Meshy 생성(docs/meshy-assets.md "영웅 파이프라인" 1~2단계). 몸 만들기는 dev/meshy_fit.py.

  python3 dev/meshy_heroes.py concept <id>...   컨셉(image-to-image, 참조 = dev/meshy/arteon_concept.png) 시작
  python3 dev/meshy_heroes.py model <id>...     끝난 컨셉으로 3D(image-to-3d) 시작 — 컨셉을 눈으로 본 뒤에
  python3 dev/meshy_heroes.py lowpoly <id>...   컨셉으로 3D 로우폴리 모드(image-to-3d model_type lowpoly, 텍스처) 시작
  python3 dev/meshy_heroes.py poll              상태 갱신, 끝난 것 내려받기(dev/meshy/out/<id>/)

키: 환경 변수 MESHY_API_KEY(없으면 프록시가 넣는다고 가정). 상태는 dev/meshy/out/state.json.
크레딧(2026-10): 컨셉 nano-banana-2 6, 3D meshy-7 + 텍스처 30(SSR) · meshy-t2 smart-topology + 텍스처 15(SR·R) · 로우폴리 + 텍스처 30.
"""
import base64, csv, json, os, sys, urllib.request

API = "https://api.meshy.ai/openapi/v1"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "meshy", "out")
STATE = os.path.join(OUT, "state.json")
REF = os.path.join(HERE, "meshy", "arteon_concept.png")
GRADE = {r["id"]: r["grade"] for r in csv.DictReader(open(os.path.join(HERE, "..", "data", "heroes.csv")))}

STYLE = ("Same art style, chibi proportions, T-pose, front camera and plain light gray background as the reference image: "
         "stylized low-poly faceted 3D game hero, flat-shaded crisp facets, big head, sturdy short body. New character: ")
TAIL = " Arms straight out horizontally, empty open hands, no weapon, no shield, nothing held. Full body, front view."

# 영웅 생김새(Art.HERO_LOOKS 주석을 영어로). 아르테온은 text-to-image(nano-banana-pro)로 만든 참조 그 자체.
DESC = {
    "ignis": "fire archmage man, tall crimson wizard hat with a small flame at the tip, red robe with gold trim, black cape, gold belt, short dark red beard, fierce eyes.",
    "sylvana": "wind sharpshooter elf woman, leaf-green hood with a long white feather, cream tunic, green leather bracers, small quiver on the back, calm sharp eyes.",
    "grom": "earth berserker man, huge muscular barbarian, horned iron helmet, ochre tunic and fur belt, bare strong arms, rusty red braided beard, wild grin.",
    "seraphine": "frost witch woman, white hair with an ice crown, pale ice-blue robe, dark blue cape, silver trim, cold elegant look.",
    "kyle": "shadow assassin man, black tight outfit, purple cape, silver hair, black face mask with a glowing purple line, leather straps.",
    "baldur": "iron gatekeeper knight man, the biggest knight, dark iron plate armor, navy cape, spiked pauldrons, helmet with three iron spikes, stern.",
    "lumina": "holy saint woman, blonde hair with a glowing golden halo, white robe with gold trim, gold cape, small white angel wings on the back, gentle smile.",
    "harald": "dragon hunter man, red dragon-hide hood and cape, steel-gray tunic, golden beard, dragon skull on the left shoulder, scars.",
    "nev": "thunder archer young man, navy hood with two lightning-bolt horns, bright yellow tunic, dark gray pants, confident grin.",
    "bron": "shield captain knight man, bronze plate armor, green cape, roman centurion helmet with a red horizontal crest, short beard.",
    "mira": "poison-arrow huntress woman, olive hood, purple tunic, black face mask, bandolier of small green poison vials across the chest.",
    "torvin": "battle priest man, tall white bishop mitre with gold cross, silver plate armor with gold trim, purple cape, kind bearded face.",
    "rian": "twin-blade swordsman young man, teal outfit, white cape, black hair with a red headband and ribbon tails, light leather armor.",
    "echo": "apprentice fire mage girl, small and young, brown leather wizard hat, orange robe, red scarf, freckles, eager smile.",
    "gork": "axe-throwing barbarian man, orange mohawk and orange beard, teal tunic, fur belt, two crossed hand axes strapped on the back.",
    "felix": "order lancer knight young man, blue-steel armor, blue cape, helmet with a tall blue feather plume, proud look.",
    "hans": "militia swordsman man, small, iron kettle-hat helmet, brown quilted leather armor, dark red cape, mustache.",
    "ella": "village archer girl, small, red hood with a daisy, light green tunic, brown boots, freckles, cheerful.",
    "dorik": "woodcutter warrior man, mustard knit beanie, green tunic, brown leather vest, dark brown full beard, sturdy.",
    "nina": "apprentice healer girl, small, chestnut hair with a flower wreath, mint-green robe, white cape, pink flowers.",
    "jack": "wandering thief man, small, ash-brown clothes, no cape, gray bandana and an eyepatch, sly grin.",
    "valen": "flame lord man, dark red hair with a burning golden crown, charcoal robe, orange cape, flames rising from the shoulders, gold trim.",
    "frieda": "glacier queen woman, silver hair with a tall ice crown, clear friendly face with big blue eyes and rosy cheeks, white robe, pale sky-blue cape, ice-crystal collar behind the neck.",
    "morgana": "queen of the dead woman, ash-gray hair, black horns and a bone headband, black robe, purple cape, small skulls on the shoulders.",
    "thorgar": "earth giant barbarian man, the biggest hero, stone crown, earthen brown tunic, gray beard, small mossy boulders on the shoulders, both arms raised straight out sideways at shoulder height.",
    "raven": "shadow marksman man, ash-navy hood with a raven-feather crest, black outfit, feathered shoulder mantle, cool eyes.",
    "gaia": "forest sage woman, white hair with a leaf crown and small wooden antlers, green robe, brown cape, vines, wise smile.",
    "dante": "dragon knight man, crimson plate armor with gold trim, black cape, helmet with dragon horns and a red crest, bat wings on the back.",
    "kaz": "wandering mechanic young man, mustard outfit, no cape, ginger hair, brass goggles on the forehead, gear-and-cog backpack, tool belt.",
    "luna": "moonlight dancer woman, lavender outfit, white flowing cape, navy hair, silver crescent-moon headband, graceful.",
    "orin": "beast tamer barbarian man, wolf-head hood, brown tunic, gray fur mantle, black beard, rugged.",
    "selene": "star prophet woman, deep navy wizard hat with a big gold star at the tip, navy robe with star pattern, night-sky cape, gold belt, silver hair.",
    "pip": "apprentice spirit mage boy, the smallest hero, orange hair with a small tilted pointed hat, sky-blue robe, a tiny water spirit on the shoulder.",
    "grit": "mine blacksmith man, small and stout, yellow miner helmet with a headlamp, soot-gray shirt, brown leather apron, black beard.",
    "tia": "swamp witch woman, droopy mossy hat with mushrooms, olive robe, mud-brown cape, purple sash, dark hair."
}


def req(method, path, body=None):
    key = os.environ.get("MESHY_API_KEY", "injected-by-proxy")
    r = urllib.request.Request(API + path, data=json.dumps(body).encode() if body is not None else None, method=method,
                               headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    with urllib.request.urlopen(r, timeout=120) as f:
        return json.load(f)


def load():
    return json.load(open(STATE)) if os.path.exists(STATE) else {}


def save(s):
    os.makedirs(OUT, exist_ok=True)
    json.dump(s, open(STATE, "w"), indent=1, ensure_ascii=False)


def concept(ids):
    ref = "data:image/png;base64," + base64.b64encode(open(REF, "rb").read()).decode()
    for i in ids:
        prompt = STYLE + DESC[i] + TAIL
        t = req("POST", "/image-to-image", {"ai_model": "nano-banana-2", "prompt": prompt, "reference_image_urls": [ref]})
        s = load()
        s.setdefault(i, {})["concept"] = {"id": t["result"], "status": "PENDING"}
        save(s)
        print(i, "concept", t["result"])


def model(ids):
    for i in ids:
        s = load()
        body = {"input_task_id": s[i]["concept"]["id"], "pose_mode": "t-pose", "should_texture": True, "target_formats": ["glb"]}
        if GRADE[i] == "SSR":
            body.update({"ai_model": "meshy-7", "should_remesh": True, "topology": "triangle", "target_polycount": 4500})
        else:
            body.update({"model_type": "smart-topology", "ai_model": "meshy-t2"})
        t = req("POST", "/image-to-3d", body)
        s[i]["model"] = {"id": t["result"], "status": "PENDING", "ai_model": body["ai_model"]}
        save(s)
        print(i, "model", body["ai_model"], t["result"])


def lowpoly(ids):
    """로우폴리 모드는 컨셉 그림을 직접 넣는다(아르테온 = REF, 나머지 = poll이 내려받은 out/<id>/concept.png)."""
    for i in ids:
        path = REF if i == "arteon" else os.path.join(OUT, i, "concept.png")
        img = "data:image/png;base64," + base64.b64encode(open(path, "rb").read()).decode()
        t = req("POST", "/image-to-3d", {"image_url": img, "model_type": "lowpoly", "pose_mode": "t-pose", "should_texture": True,
                                         "target_formats": ["glb"]})
        s = load()
        s.setdefault(i, {})["lowpoly"] = {"id": t["result"], "status": "PENDING"}
        save(s)
        print(i, "lowpoly", t["result"])


def poll():
    s = load()
    for i, e in s.items():
        for kind, path in (("concept", "/image-to-image/"), ("model", "/image-to-3d/"), ("lowpoly", "/image-to-3d/")):
            t = e.get(kind)
            if not t or t.get("saved") or t["status"] in ("FAILED", "CANCELED"):
                continue
            r = req("GET", path + t["id"])
            t["status"] = r["status"]
            if r["status"] == "SUCCEEDED":
                os.makedirs(os.path.join(OUT, i), exist_ok=True)
                url = r["image_urls"][0] if kind == "concept" else r["model_urls"]["glb"]
                name = {"concept": "concept.png", "model": i + "_meshy.glb", "lowpoly": i + "_lowpoly.glb"}[kind]
                urllib.request.urlretrieve(url, os.path.join(OUT, i, name))
                t["saved"] = True
            print(i, kind, t["status"], r.get("progress"))
    save(s)


if __name__ == "__main__":
    {"concept": lambda: concept(sys.argv[2:]), "model": lambda: model(sys.argv[2:]), "lowpoly": lambda: lowpoly(sys.argv[2:]),
     "poll": poll}[sys.argv[1]]()
