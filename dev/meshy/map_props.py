"""맵 소품 3D(2026-11-06 사용자 "맵 퀄리티 확연하게, 새롭게 하이 퀄리티로"): 컨셉(text-to-image nano-banana-2, 6크레딧) →
3D(image-to-3d meshy-t2 smart-topology + 텍스처, 약 15크레딧) → dev/meshy/out/props/<이름>/<이름>.glb.
참고: Rise of Kingdoms·Lords Mobile 맵 소품(손그림 질감, 굵고 읽기 쉬운 모양).

  python3 dev/meshy/map_props.py concept [이름...]
  python3 dev/meshy/map_props.py model [이름...]
  python3 dev/meshy/map_props.py poll
"""
import json, os, sys, urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from meshy_heroes import req  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "props")
STATE = os.path.join(OUT, "state.json")

STYLE = ("A single stylized 3D game prop for a premium fantasy mobile strategy RPG like Rise of Kingdoms and Lords Mobile: "
         "hand-painted textures, soft painterly colors, chunky readable silhouette, clean shapes. Seen from a high three-quarter "
         "view. The whole object is visible and centered, nothing else in the picture, no ground plane, plain light gray background. Object: ")
DESC = {
    "pine": "a tall evergreen pine tree with layered dark green needle tiers and a short brown trunk.",
    "snow_pine": "a tall evergreen pine tree with layered dark green tiers covered with thick white snow on top of each tier.",
    "oak": "a round leafy oak tree with a lush bright green canopy made of puffy leaf clusters and a sturdy brown trunk.",
    "autumn_oak": "a round leafy oak tree with a lush orange and red autumn canopy made of puffy leaf clusters and a brown trunk.",
    "blossom": "a cherry blossom tree with a lush pink flowering canopy made of puffy blossom clusters and a dark brown trunk.",
    "bare_tree": "a leafless winter tree with bare twisting brown branches dusted with snow.",
    "bush": "a dense round green shrub made of puffy leaf clusters.",
    "flower_bush": "a low green bush with small white, yellow and pink wildflowers.",
    "rock_big": "a cluster of three large gray boulders with soft moss on top.",
    "rock_small": "two small flat gray stones with a little moss.",
    "cliff": "a tall jagged ochre and orange sandstone canyon rock pillar with layered strata and a few gold veins.",
    "gold_ore": "a rock cluster with shiny gold ore nuggets and gold veins sticking out.",
    "mine_cart": "an old wooden mine cart with iron bands and wheels, full of gold ore nuggets.",
    "crystal": "a cluster of tall glowing pale blue crystals growing from dark rock.",
    "ruin_column": "a broken ancient sandstone column with a carved capital lying beside it, cracks and green moss.",
    "lion_statue": "a weathered stone guardian lion statue sitting on a square pedestal, mossy gray-green stone.",
    "stone_lantern": "an old stone shrine lantern with a small roof, mossy gray stone.",
    "broken_pillar": "a broken dark gray gothic stone pillar with a jagged top, scorched with soot.",
    "brazier": "a heavy black iron brazier bowl on three legs, filled with glowing red coals, no flames.",
    "rubble": "a pile of broken dark stone blocks and charred wooden beams.",
    "obsidian": "a tall jagged black obsidian rock spire with thin glowing orange lava cracks.",
    "treasure": "a big pile of gold coins with an open wooden treasure chest, jewels and a sword stuck in it.",
    "tombstone": "an old cracked gothic tombstone with a stone cross, dark blue-gray stone with moss.",
    "web_tree": "a dead twisted dark tree stump with thick white cobwebs between the branches.",
    "egg_sacs": "a cluster of pale white spider egg sacs wrapped in silk on dark rocks.",
}


def load():
    return json.load(open(STATE)) if os.path.exists(STATE) else {}


def save(s):
    os.makedirs(OUT, exist_ok=True)
    json.dump(s, open(STATE, "w"), indent=1)


def concept(names):
    s = load()
    for n in names or DESC:
        t = req("POST", "/text-to-image", {"ai_model": "nano-banana-2", "prompt": STYLE + DESC[n], "aspect_ratio": "1:1"})
        s.setdefault(n, {})["concept"] = {"id": t["result"], "status": "PENDING"}
        save(s)
        print(n, "concept", t["result"])


def model(names):
    s = load()
    for n in names or [k for k in s if s[k].get("concept", {}).get("saved") and "model" not in s[k]]:
        body = {"input_task_id": s[n]["concept"]["id"], "model_type": "smart-topology", "ai_model": "meshy-t2",
                "should_texture": True, "target_formats": ["glb"]}
        t = req("POST", "/image-to-3d", body)
        s[n]["model"] = {"id": t["result"], "status": "PENDING"}
        save(s)
        print(n, "model", t["result"])


def poll():
    s = load()
    for n, e in s.items():
        for kind, path in (("concept", "/text-to-image/"), ("model", "/image-to-3d/")):
            t = e.get(kind)
            if not t or t.get("saved") or t["status"] in ("FAILED", "CANCELED"):
                continue
            r = req("GET", path + t["id"])
            t["status"] = r["status"]
            if r["status"] == "SUCCEEDED":
                os.makedirs(os.path.join(OUT, n), exist_ok=True)
                url = r["image_urls"][0] if kind == "concept" else r["model_urls"]["glb"]
                urllib.request.urlretrieve(url, os.path.join(OUT, n, "concept.png" if kind == "concept" else n + ".glb"))
                t["saved"] = True
            print(n, kind, t["status"], r.get("progress", ""))
    save(s)


if __name__ == "__main__":
    {"concept": concept, "model": model, "poll": lambda a: poll()}[sys.argv[1]](sys.argv[2:])
