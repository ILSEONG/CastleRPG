"""던전 적 Meshy 생성(docs/meshy-assets.md "던전 적"). 몸 만들기는 영웅과 같은 dev/meshy_fit.py(KayKit 뼈대 = Art.MONSTER_MODELS의 scene).

  python3 dev/meshy_enemies.py concept <kind>...   T자세 컨셉(image-to-image, 참조 = dev/meshy/arteon_concept.png) 시작
  python3 dev/meshy_enemies.py model <kind>...     끝난 컨셉으로 3D 시작 — 컨셉을 눈으로 본 뒤에
  python3 dev/meshy_enemies.py poll                상태 갱신, 끝난 것 내려받기(dev/meshy/out/enemies/<kind>/)

키·프록시는 dev/meshy_heroes.py와 같다. 상태는 dev/meshy/out/enemies/state.json.
크레딧(2026-10): 컨셉 nano-banana-2 6 + 3D 보스 meshy-7 + 텍스처 30(삼각형 4,500으로 리메시) · 졸개 meshy-t2 + 텍스처 15.
무기는 KayKit 손 슬롯(단검)·코드 부품(곤봉·대검)을 그대로 쓰므로 빈손으로 그린다.
"""
import base64, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_summons as ms  # noqa: E402
from meshy_heroes import REF, STYLE, TAIL, req  # noqa: E402

ms.OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "meshy", "out", "enemies")
ms.STATE = os.path.join(ms.OUT, "state.json")

BOSS = {"goblin_king", "death_knight"}
DESC = {
    "goblin": ("goblin raider, small green-skinned goblin with long pointed ears, big nose and a toothy grin, ragged brown "
               "leather vest and hood pushed back, dark gray pants, rope belt, bare green arms and feet wrapped in cloth."),
    "goblin_king": ("goblin king, fat and big green-skinned goblin with long pointed ears and a wide toothy grin, olive skin, "
                    "a spiky golden crown, red royal cape with white fur collar, purple tunic, gold belt with a big buckle."),
    "death_knight": ("death knight, tall undead knight in black iron plate armor with spiked pauldrons, a horned black helmet "
                     "with glowing red eyes in the visor slit, tattered dark red cape, skull emblem on the chest."),
}


def concept(kinds):
    ref = "data:image/png;base64," + base64.b64encode(open(REF, "rb").read()).decode()
    for k in kinds:
        prompt = STYLE + DESC[k] + TAIL
        assert len(prompt) <= 600, (k, len(prompt))
        t = req("POST", "/image-to-image", {"ai_model": "nano-banana-2", "prompt": prompt, "reference_image_urls": [ref]})
        s = ms.load()
        s.setdefault(k, {})["concept"] = {"id": t["result"], "status": "PENDING"}
        ms.save(s)
        print(k, "concept", t["result"])


def model(kinds):
    for k in kinds:
        s = ms.load()
        body = {"input_task_id": s[k]["concept"]["id"], "pose_mode": "t-pose", "should_texture": True, "target_formats": ["glb"]}
        if k in BOSS:
            body.update({"ai_model": "meshy-7", "should_remesh": True, "topology": "triangle", "target_polycount": 4500})
        else:
            body.update({"model_type": "smart-topology", "ai_model": "meshy-t2"})
        t = req("POST", "/image-to-3d", body)
        s[k]["model"] = {"id": t["result"], "status": "PENDING", "ai_model": body["ai_model"]}
        ms.save(s)
        print(k, "model", body["ai_model"], t["result"])


if __name__ == "__main__":
    {"concept": lambda: concept(sys.argv[2:]), "model": lambda: model(sys.argv[2:]), "poll": ms.poll}[sys.argv[1]]()
