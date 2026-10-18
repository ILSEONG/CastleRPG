"""병사 단계별 Meshy 몸(2026-10-18, 사용자 "병사 레벨에 따라 외형이 달라졌으면, 모델링 작업이 들어갔으면"). 영웅·적과 같은 파이프라인.

  python3 dev/meshy_soldiers.py concept <id>...   T자세 컨셉(image-to-image, 참조 = dev/meshy/arteon_concept.png) 시작
  python3 dev/meshy_soldiers.py model <id>...     끝난 컨셉으로 3D 시작 — 컨셉을 눈으로 본 뒤에
  python3 dev/meshy_soldiers.py redo <id>...      팔이 내려온 결과를 meshy-7로 다시(30 크레딧)
  python3 dev/meshy_soldiers.py poll              상태 갱신, 끝난 것 내려받기(dev/meshy/out/soldiers/<id>/)
  몸 만들기: python3 dev/meshy_fit.py <뼈대> dev/meshy/out/soldiers/<id>/<id>_meshy.glb assets/models/meshy/soldiers/<id>.glb
            (뼈대 = 보병·기병 assets/models/characters/Knight.glb, 궁병 Rogue_Hooded.glb — soldiers.csv model)

id = <병종>_t<단계>(infantry_t1 … cavalry_t5). 게임은 Art.soldier_spec(type, model, tier)가 그 파일이 있으면 입힌다.
단계 말(라이즈 오브 킹덤즈·로드 모바일처럼 단계마다 다른 병사): 1 천·가죽 → 2 가죽 갑옷 → 3 사슬 → 4 판금 + 망토 → 5 은빛 판금 정예.
천은 모든 단계 같은 왕청색(TEAM)으로 그린다 — 파티·대전에서 성주 색으로 바꾸는 칸. 금색은 쓰지 않는다(사용자 2026-10-14).
무기·방패는 KayKit 손 슬롯 그대로라 빈손으로 그린다. 크레딧: 컨셉 6 + meshy-t2 텍스처 15 = 21/종(삼각형 4천 안팎 — KayKit 기사 몸과 비슷).
"""
import base64, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy_summons as ms  # noqa: E402
from meshy_heroes import REF, req  # noqa: E402

ms.OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "meshy", "out", "soldiers")
ms.STATE = os.path.join(ms.OUT, "state.json")

STYLE = ("Same art style, chibi proportions, T-pose, front camera and plain light gray background as the reference image: "
         "stylized low-poly faceted 3D game soldier, flat-shaded crisp facets, big head, sturdy short body. New character: ")
TAIL = " Only steel, silver, white, brown and royal blue colors. Arms straight out horizontally, empty open hands, nothing held. Full body, front view."
DESC = {
    "infantry_t1": "militia recruit footman, young peasant, simple brown cloth tunic with a royal blue sash, brown leather cap, rope belt, cloth leg wraps, plain boots.",
    "infantry_t2": "footman soldier, brown boiled-leather armor over a royal blue tunic, round iron cap helmet, leather bracers, brown boots.",
    "infantry_t3": "man-at-arms, chainmail shirt under a royal blue tabard, iron kettle-hat helmet with a nose guard, leather gloves, iron shin guards.",
    "infantry_t4": "heavy infantry knight, steel plate armor, royal blue tabard and short blue cape, closed steel great helm with a narrow visor slit, steel pauldrons.",
    "infantry_t5": "elite royal guard knight, ornate silver-white full plate armor with engraved edges, closed helm with a tall royal blue feather plume, long royal blue cape, blue and white tabard with a white lion crest, big rounded pauldrons.",
    "archer_t1": "village hunter, brown hooded cloak, simple tunic with a royal blue scarf, leather belt pouch, cloth trousers, soft boots.",
    "archer_t2": "scout crossbowman, royal blue hood, padded brown leather jerkin, leather bracers, small bolt quiver on the hip.",
    "archer_t3": "crossbowman, chainmail coif under a royal blue hood, leather armor with a short blue tabard, bolt quiver on the hip, leather boots.",
    "archer_t4": "veteran marksman, open-face steel helmet, steel breastplate over a royal blue tunic, blue half-cape on one shoulder, steel bracers, bolt quiver.",
    "archer_t5": "elite ranger marksman, engraved silver-white half plate armor, royal blue hooded cape with white trim, white feather crest on the hood, ornate steel bracers.",
    "cavalry_t1": "light rider, brown leather jerkin over a royal blue shirt, simple open iron helmet, tall riding boots.",
    "cavalry_t2": "outrider, studded brown leather armor, short royal blue cape, iron helmet with cheek guards, tall riding boots.",
    "cavalry_t3": "cavalry man-at-arms, chainmail with a royal blue surcoat, conical iron helmet with a nose guard, royal blue cape, riding boots.",
    "cavalry_t4": "lancer knight, steel plate armor, royal blue surcoat and cape, visored steel helmet with a short blue plume, steel riding boots.",
    "cavalry_t5": "elite paladin cavalry knight, ornate silver-white plate armor, helmet with small white wings, long royal blue cape, white and blue surcoat with a white eagle crest.",
}


def concept(ids):
    ref = "data:image/png;base64," + base64.b64encode(open(REF, "rb").read()).decode()
    for k in ids:
        prompt = STYLE + DESC[k] + TAIL
        assert len(prompt) <= 600, (k, len(prompt))
        t = req("POST", "/image-to-image", {"ai_model": "nano-banana-2", "prompt": prompt, "reference_image_urls": [ref]})
        s = ms.load()
        s.setdefault(k, {})["concept"] = {"id": t["result"], "status": "PENDING"}
        ms.save(s)
        print(k, "concept", t["result"])


def model(ids, redo=False):
    for k in ids:
        s = ms.load()
        body = {"input_task_id": s[k]["concept"]["id"], "should_texture": True, "target_formats": ["glb"], "pose_mode": "t-pose"}
        if redo:  # t2가 팔을 내린 A자세로 냈을 때(infantry_t5): meshy-7 + 리메시 4,500(30 크레딧) — 영웅 토르빈과 같은 처방
            body.update({"ai_model": "meshy-7", "should_remesh": True, "topology": "triangle", "target_polycount": 4500})
        else:
            body.update({"model_type": "smart-topology", "ai_model": "meshy-t2"})
        t = req("POST", "/image-to-3d", body)
        s[k]["model"] = {"id": t["result"], "status": "PENDING", "ai_model": body["ai_model"]}
        ms.save(s)
        print(k, "model", body["ai_model"], t["result"])


if __name__ == "__main__":
    {"concept": lambda: concept(sys.argv[2:]), "model": lambda: model(sys.argv[2:]), "redo": lambda: model(sys.argv[2:], True),
     "poll": ms.poll}[sys.argv[1]]()
