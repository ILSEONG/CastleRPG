#!/usr/bin/env python3
"""스킬 아이콘판 자르기(개발용, 2026-10-25 사용자 "스킬 아이콘이 너무 허접해").

사용자가 ChatGPT로 만든 아이콘판(3×3 칸, 9장)을 칸마다 잘라 assets/ui/skills/<kind>.jpg(192 px)로 저장한다.
판 순서와 칸 순서는 아래 SHEETS가 정한다(지시문.md도 여기서 만든다 — 둘이 어긋나지 않게).

  python3 dev/skill_icon_slice.py --prompts /mnt/project-files/design/skill_icons/chatgpt_pack/지시문.md
  python3 dev/skill_icon_slice.py --prompts /mnt/project-files/design/skill_icons/chatgpt_pack_ur/지시문.md --only 10,11  (UR)
  python3 dev/skill_icon_slice.py --sheet 1 판1.png [--sheet 2 판2.png ...] [--preview out.png]

칸 경계는 판 1/3·2/3 근처에서 가장 어두운 세로·가로 줄(칸 사이 검은 선)을 찾고, 없으면 똑같이 3등분한다.
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageOps

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "ui", "skills")
SIZE = 128  # 저장 크기(px). 전투 칸 최대 지름 60 px(1080 폭 폰에서 90 px). 첫 로딩이 assets 전부를 메모리에 올리니 크게 잡지 않는다
INSET = 0.035  # 칸 가장자리에서 깎아 낼 몫(검은 선 찌꺼기)
# 새 그림은 손실 압축 + 밉맵(작게 그려도 거칠지 않게). Godot가 가져올 때 나머지(uid·경로)를 채운다
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=1
compress/lossy_quality=0.85
mipmaps/generate=true
"""

# 판마다 (제목, 바탕 설명, [(kind, 이름, 그림 설명), ... 9개]). kind는 scripts/skill_icons.gd KIND의 키.
SHEETS = [
    ("불", "주황·붉은 불빛", [
        ("meteor", "메테오", "불타는 커다란 바위 운석이 오른쪽 위에서 왼쪽 아래로 떨어진다, 긴 불꼬리"),
        ("dragon_breath", "용의 숨결", "옆을 본 용 머리가 입에서 부채꼴 불길을 내뿜는다"),
        ("fire_bolt", "화염탄", "앞으로 날아가는 둥근 화염구와 짧은 불꼬리"),
        ("ignite", "점화", "타오르는 불꽃 하나와 튀어 오르는 불씨들"),
        ("firespread", "들불 번지기", "땅 위로 낮고 넓게 번지는 불길 띠"),
        ("aoe_blast", "폭발", "가운데서 둥글게 터지는 폭발과 사방으로 튀는 파편"),
        ("summon_phoenix", "불사조", "날개를 활짝 편 불꽃 새"),
        ("scorch", "불바다", "바닥에 둥글게 깔린 불의 원과 그 안에서 솟는 불길"),
        ("magma", "끓는 늪", "갈라진 검은 바위 틈에서 솟구치는 용암 분수, 배경은 짙은 붉은색"),
    ]),
    ("얼음과 별", "하늘색·파란 얼음빛 (8·9번은 짙은 남색 밤하늘)", [
        ("blizzard", "눈보라", "소용돌이치는 눈바람과 날리는 눈송이"),
        ("frost_nova", "서리 폭발", "가운데서 둥글게 터져 나가는 얼음 결정 고리"),
        ("frost_chain", "서리 사슬", "지그재그로 튕기며 이어지는 하늘색 얼음 번개"),
        ("deep_freeze", "급속 냉동", "커다란 각진 얼음 덩어리 속에 꽁꽁 갇힌 어두운 그림자"),
        ("freeze_hit", "빙결", "칼날 끝에서 퍼져 나가는 서리와 얼음 결정"),
        ("frost_shatter", "얼음 파편", "산산이 부서져 사방으로 튀는 얼음 조각"),
        ("frost_spike", "서리 가시", "땅에서 일렬로 솟아오르는 뾰족한 얼음 가시들"),
        ("starfall", "별똥별", "밤하늘에서 쏟아지는 빛나는 별똥별 세 개"),
        ("comet", "혜성", "긴 꼬리를 끌며 떨어지는 커다란 푸른 혜성"),
    ]),
    ("번개·바람·달", "보랏빛 남색 폭풍 (4·8번은 청록 하늘)", [
        ("thunder_storm", "뇌우", "먹구름에서 여러 갈래로 내리치는 번개"),
        ("sky_bolt", "낙뢰", "하늘에서 곧게 내리꽂히는 굵은 번개 한 줄기"),
        ("shock_hit", "감전", "칼날을 휘감는 노란 전기 불꽃"),
        ("gale", "돌개바람", "청록빛 회오리바람 기둥"),
        ("crescent", "초승달 베기", "초승달 모양으로 날아가는 은빛 참격"),
        ("lunar_veil", "달빛 장막", "커다란 보름달에서 커튼처럼 쏟아지는 은은한 달빛, 배경은 짙은 보라"),
        ("howl", "야성의 포효", "하늘을 향해 울부짖는 늑대 실루엣과 둥글게 퍼지는 연두빛 고리"),
        ("summon_hawk", "매 부르기", "발톱을 세우고 내리꽂히는 매"),
        ("summon_spirit", "정령 소환", "빛나는 보라색 마력 구슬 정령과 그 둘레를 도는 작은 빛들"),
    ]),
    ("대지와 무거운 무기", "흙빛 갈색·황토", [
        ("earthquake", "지진", "쩍 갈라진 땅과 튀어 오르는 바위 조각"),
        ("ground_slam", "대지 강타", "땅을 내리친 큰 망치와 둥글게 퍼지는 충격 고리"),
        ("shockwave", "충격파", "땅을 따라 앞으로 밀려가는 흙먼지 파도"),
        ("crushing_blow", "분쇄 일격", "위에서 내리찍는 거대한 전쟁 망치와 부서지는 돌"),
        ("heavy_blow", "강타", "크게 휘둘러지는 묵직한 철퇴와 굵은 궤적, 부딪치는 곳의 충격 별"),
        ("summon_golem", "골렘 소환", "주먹을 쥔 이끼 낀 바위 골렘의 상반신, 얼굴 대신 빛나는 두 눈"),
        ("wide_swing", "크게 휘두르기", "큰 양날 도끼가 반원으로 크게 휘둘러지는 궤적"),
        ("axe_volley", "도끼 세례", "빙글빙글 돌며 날아가는 손도끼 여러 개"),
        ("boomerang", "회전 도끼", "부메랑처럼 회전하며 날아가는 큰 도끼 하나와 둥근 궤적"),
    ]),
    ("그림자와 피", "짙은 보라 (5·7·8번은 검붉은색)", [
        ("shadow_strike", "그림자 습격", "검은 그림자 속에서 튀어나오는 보랏빛 단검"),
        ("void_rift", "공허 균열", "공중에 찢어진 보랏빛 균열, 안쪽은 검은 소용돌이"),
        ("abyss_hand", "심연의 손", "땅에서 솟아나 움켜쥐는 거대한 검은 그림자 손"),
        ("hex", "역병의 저주", "초록 독기가 피어오르는 불길한 저주 문양 원"),
        ("blood_rage", "피의 격노", "핏빛 기운에 휩싸여 꽉 쥔 주먹"),
        ("drain_slash", "흡혈 베기", "핏방울을 흩뿌리며 지나가는 검의 참격"),
        ("rend", "난도질", "날카로운 발톱 자국 세 줄과 튀는 피"),
        ("execute", "마무리 일격", "금이 간 해골 위로 내리꽂히는 검"),
        ("summon_skeleton", "해골 병사", "녹슨 칼과 방패를 든 해골 병사의 상반신"),
    ]),
    ("빛과 치유", "흰빛·연한 노란빛 (3·4·7번은 연두빛, 9번은 따뜻한 주황)", [
        ("holy_smite", "심판의 빛", "하늘에서 내리꽂히는 굵은 흰 빛기둥"),
        ("sanctuary", "성역", "바닥에 빛나는 둥근 문양과 그 위로 솟는 반투명 빛의 돔"),
        ("mass_heal", "대치유", "크게 빛나는 초록 십자가와 사방으로 퍼지는 치유의 빛"),
        ("heal_aura", "치유의 기도", "모은 두 손 위로 피어오르는 초록 치유의 빛"),
        ("resurrection", "부활의 기도", "빛기둥 속에 떠오르는 흰 깃털 하나와 둥근 빛"),
        ("solar_spark", "햇빛 파편", "눈부시게 터지는 작은 태양 섬광과 흩어지는 빛 조각"),
        ("second_wind", "재기", "금이 갔다가 다시 이어지며 빛나는 초록 하트"),
        ("revive", "불굴", "땅에 꽂힌 검이 흰 불꽃에 휩싸여 다시 빛난다"),
        ("battle_hymn", "전투 찬가", "빛나는 음표들과 펄럭이는 깃발"),
    ]),
    ("방어", "강철빛 파랑 (3번은 흙빛, 7번은 붉은빛 남색)", [
        ("shield", "보호막", "둥근 파란 마법 방어막 구체"),
        ("shield_ally", "수호 축복", "하트 문양이 새겨진 빛나는 방패와 그것을 감싸는 빛"),
        ("bulwark", "방벽", "땅에 박아 세운 커다란 탑 방패와 앞으로 펼쳐진 빛의 벽"),
        ("parry", "받아치기", "서로 부딪쳐 불꽃이 튀는 두 자루 검"),
        ("counter", "반격", "작은 방패 뒤에서 앞으로 찔러 나오는 검과 되돌아오는 곡선 궤적"),
        ("invincible", "금강불괴", "다이아몬드처럼 빛나는 단단한 결정 방패"),
        ("taunt", "도발", "방패를 두드리는 칼자루와 사방으로 퍼지는 붉은 고리"),
        ("gate_repair", "성문 수리", "나무 성문과 그 앞의 망치, 새로 덧댄 판자"),
        ("shield_bash", "방패 밀치기", "앞으로 밀쳐 나가는 방패와 충격 별"),
    ]),
    ("사냥과 자연", "숲 초록·적갈색 (6번은 보랏빛 회색, 7번은 보랏빛 남색, 9번은 탁한 녹황색)", [
        ("arrow_rain", "화살비", "하늘에서 비처럼 쏟아지는 수많은 화살"),
        ("volley", "연발 사격", "나란히 연달아 날아가는 화살 세 발"),
        ("piercing_shot", "관통 사격", "빛나는 꼬리를 남기며 일직선으로 꿰뚫고 나가는 화살 한 발"),
        ("spear_throw", "창 투척", "앞으로 힘차게 날아가는 창 한 자루와 바람 궤적"),
        ("spear_sweep", "창 휩쓸기", "부채꼴로 크게 휘둘러지는 긴 창의 궤적"),
        ("summon_turret", "포탑 설치", "나무 받침 위의 커다란 쇠뇌(석궁) 포탑"),
        ("summon_wolf", "늑대 소환", "으르렁거리는 늑대 두 마리의 머리"),
        ("snare", "덫", "땅에서 휘감아 오르는 초록 덩굴 덫"),
        ("poison_cloud", "독구름", "해골 무늬가 어렴풋이 보이는 초록 독구름"),
    ]),
    ("검술과 전투", "붉은 갈색·핏빛 (7번은 노란빛, 9번은 숲 초록)", [
        ("whirlwind", "회오리 베기", "검이 원을 그리며 도는 은빛 회오리 궤적"),
        ("sunder", "갑옷 가르기", "대각선 참격에 쩍 갈라지는 철 흉갑"),
        ("blade_flurry", "칼날 난무", "여러 방향으로 교차하는 빛나는 참격 선들"),
        ("cheap_shot", "급소 찌르기", "과녁 한가운데를 찌르는 단검"),
        ("echo_strike", "메아리 베기", "검 끝에서 둥글게 퍼지는 충격파 고리 세 겹"),
        ("crit", "치명타", "붉은 빛이 번쩍이는 날카로운 칼날과 별 모양 섬광"),
        ("stun", "기절", "빙글빙글 도는 별 세 개와 소용돌이 궤적"),
        ("war_cry", "전투 함성", "치켜든 뿔나팔에서 앞으로 퍼지는 붉은 소리 파동"),
        ("summon_treant", "나무 정령", "이끼와 잎이 달린 나무 정령, 굵은 가지 팔"),
    ]),
    # UR 영웅 전용(2026-10-29, 능력치 스레드가 정한 id — 영웅마다 발동 / 상시 / 궁극기 순서). 최고 등급이라 지시문에 UR_EXTRA를 붙인다.
    ("UR 현무·백호·연화", "1~3번은 짙은 남청·청록 물빛, 4~6번은 차가운 하늘색과 흰 번개빛, 7~9번은 분홍·진홍빛", [
        ("turtle_ward", "현무 결계", "청록 육각형 무늬가 빛나는 반구 모양 거북 등껍질 결계(돔)"),
        ("black_shell", "흑귀갑", "검은 거북 등껍질 방패에 부딪혀 사방으로 튀는 청록 물보라"),
        ("north_tide", "북해 해일", "둥글게 줄지어 솟구치는 거대한 물기둥들과 하얀 물보라, 가운데 소용돌이"),
        ("tiger_claw", "백호 참격", "대각선으로 크게 할퀸 흰 발톱 자국 세 줄과 하늘색 빛 번짐"),
        ("tiger_fury", "산군의 기세", "흰 번개를 두르고 내리찍는 흰 호랑이 앞발과 날카로운 발톱"),
        ("tiger_avatar", "백호 현신", "정면을 보고 포효하는 흰 호랑이 머리, 털 위로 흐르는 하늘색 번개"),
        ("fox_fire", "여우불", "원을 그리며 떠 있는 분홍 여우불 아홉 개"),
        ("fox_charm", "매혹", "흰 여우 꼬리 하나가 휘감은 빛나는 분홍 하트"),
        ("nine_tails", "구미호 해방", "부채처럼 활짝 펼친 흰 여우 꼬리 아홉 개, 꼬리 끝마다 분홍 불꽃"),
    ]),
    ("UR 청룡·크로노스·주작", "1~3번은 비취·옥빛 청록, 4~6번은 짙은 남색과 하늘색 시간 빛, 7~9번은 주홍·붉은 불빛", [
        ("dragon_arrow", "청룡시", "앞으로 날아가며 나선을 그리는 청록 동양 용으로 변하는 화살"),
        ("azure_tide", "용궁의 물살", "발목 높이에서 감아 도는 옥빛 물결 소용돌이와 물방울"),
        ("azure_dragon", "청룡 강림", "원을 그리며 몸을 휘감는 거대한 청록 동양 용, 가운데 빛나는 흰 여의주"),
        ("time_stop", "시간 정지", "바닥에 누운 빛나는 하늘색 시계판(숫자 없이 눈금만)과 거꾸로 도는 시곗바늘, 공중에 멈춘 빛 조각들"),
        ("time_haste", "시간 가속", "모래가 빠르게 쏟아지는 은빛 모래시계와 옆으로 휘는 하늘색 속도선"),
        ("time_collapse", "시간 붕괴", "가운데 검푸른 균열로 빨려 들어가며 깨지는 시계판 조각들, 균열에서 터지는 하늘색 빛"),
        ("phoenix_wing", "불새의 날개", "활짝 편 주홍 불꽃 날개 한 쌍과 그 사이로 쏟아지는 연둣빛 치유 빛"),
        ("phoenix_blessing", "주작의 가호", "주홍 불꽃 깃털 세 개가 둘러싼 위로 선 은빛 검, 검에서 솟는 붉은 빛"),
        ("rebirth_flame", "환생의 불꽃", "하늘로 솟는 거대한 불기둥과 그 양옆으로 펼쳐진 불새 날개"),
    ]),
]

PROMPT_HEAD = (
    "이 대화에 처음 붙인 그림과 똑같은 화풍(밝은 판타지 게임 일러스트, 각진 면으로 나뉜 로우폴리 채색, 강한 빛, "
    "빛나는 에너지 조각과 파편)으로 모바일 RPG 스킬 아이콘 9개를 정사각형 그림 한 장에 그려줘.\n"
    "- 그림을 가로 3칸 × 세로 3칸, 똑같은 크기의 정사각형 칸으로 나누고 칸 사이는 얇은 검은 선으로 구분해줘.\n"
    "- 칸마다 아이콘 하나: 가운데에 크고 굵은 그림 하나만, 칸 가운데 70% 안에 들어오게. "
    "아주 작게(48픽셀) 줄여도 무엇인지 알아볼 수 있게 단순하고 명암 대비가 강하게.\n"
    "- 배경은 칸마다 적힌 색의 빛과 그라데이션으로 칸을 꽉 채우고, 테두리·액자·금색 장식은 넣지 마.\n"
    "- 글자, 숫자, 로고, 사람 얼굴은 넣지 마.\n"
)
UR_EXTRA = "- 최고 등급(UR) 영웅의 스킬이라 다른 아이콘보다 빛, 에너지 조각, 파편을 훨씬 화려하게. 금색은 쓰지 말고 은색·흰색과 칸마다 적힌 색으로만.\n"


def write_prompts(path: str, only: list = None) -> None:
    if only:
        return _write_ur_prompts(path, only)
    lines = [
        "# 스킬 아이콘 ChatGPT 묶음",
        "",
        "만드는 법",
        "1. ChatGPT에서 새 대화를 하나 열고 `00_화풍_참고.jpg`(이그니스 일러스트)를 붙인 뒤, 아래 1번 지시문을 그대로 붙여 넣습니다.",
        "2. 같은 대화에서 2번부터 9번까지 차례로 붙여 넣습니다. 한 대화에서 이어서 해야 9장의 화풍이 맞습니다.",
        "3. 나온 판 9장을 스레드에 올려 주세요. 번호 순서대로 올리시거나 몇 번 판인지만 적어 주시면 됩니다.",
        "",
        "마음에 안 드는 판은 \"다시\"라고 하면 됩니다. 칸이 조금 어긋나도 제가 맞춰 자릅니다.",
        "한 칸만 마음에 안 들면 \"3번 칸만 다시, 더 크고 단순하게\"처럼 말하면 됩니다.",
        "",
    ]
    for i, (title, bg, cells) in enumerate(SHEETS, 1):
        lines.append(f"## {i}. {title} ({', '.join(c[1] for c in cells)})")
        lines.append("")
        lines.append("```")
        lines.append(PROMPT_HEAD + f"- 배경 색: {bg}.")
        lines.append("칸 순서(왼쪽 위부터 오른쪽으로, 한 줄씩):")
        for j, (_kind, name, desc) in enumerate(cells, 1):
            lines.append(f"{j}. {name}: {desc}")
        lines.append("```")
        lines.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"wrote {path}")


## UR 묶음(판 번호 only만): 이그니스 화풍 그림을 붙이고 판마다 새 대화가 아니라 한 대화에서 이어서.
def _write_ur_prompts(path: str, only: list) -> None:
    lines = [
        "# UR 스킬 아이콘 ChatGPT 묶음 (UR 영웅 6명, 18개)",
        "",
        "만드는 법",
        "1. ChatGPT에서 새 대화를 하나 열고 `00_화풍_참고.jpg`를 붙인 뒤, 아래 첫 번째 지시문을 그대로 붙여 넣습니다.",
        "2. 같은 대화에서 두 번째 지시문을 붙여 넣습니다. 한 대화에서 이어서 해야 두 장의 화풍이 맞습니다.",
        "3. 나온 판 두 장을 스레드에 올려 주세요. 순서만 맞으면 됩니다.",
        "",
        "마음에 안 드는 판은 \"다시\"라고 하면 됩니다. 칸이 조금 어긋나도 제가 맞춰 자릅니다.",
        "한 칸만 마음에 안 들면 \"3번 칸만 다시, 더 크고 단순하게\"처럼 말하면 됩니다.",
        "",
    ]
    for n in only:
        title, bg, cells = SHEETS[n - 1]
        lines.append(f"## {n}. {title} ({', '.join(c[1] for c in cells)})")
        lines.append("")
        lines.append("```")
        lines.append(PROMPT_HEAD + UR_EXTRA + f"- 배경 색: {bg}.")
        lines.append("칸 순서(왼쪽 위부터 오른쪽으로, 한 줄씩):")
        for j, (_kind, name, desc) in enumerate(cells, 1):
            lines.append(f"{j}. {name}: {desc}")
        lines.append("```")
        lines.append("")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"wrote {path}")


def _dark_line(prof: list, n: int, k: int) -> int:
    """prof(줄마다 밝기 평균)에서 n*k/3 근처(±8%) 가장 어두운 줄. 둘레보다 확실히 어둡지 않으면 n*k/3."""
    want = n * k // 3
    lo, hi = max(1, want - n * 8 // 100), min(n - 2, want + n * 8 // 100)
    best = min(range(lo, hi + 1), key=lambda i: prof[i])
    around = sorted(prof[lo:hi + 1])[len(prof[lo:hi + 1]) // 2]
    if prof[best] >= around * 0.6:
        return want
    a, b = best, best  # 선 굵기(7~10 px)의 가운데
    while a > lo and prof[a - 1] <= prof[best] * 1.5 + 4:
        a -= 1
    while b < hi and prof[b + 1] <= prof[best] * 1.5 + 4:
        b += 1
    return (a + b) // 2


def cells_of(img: Image.Image) -> list:
    g = ImageOps.grayscale(img)
    w, h = g.size
    px = g.load()
    step = max(1, min(w, h) // 256)
    cols = [sum(px[x, y] for y in range(0, h, step)) / len(range(0, h, step)) for x in range(w)]
    rows = [sum(px[x, y] for x in range(0, w, step)) / len(range(0, w, step)) for y in range(h)]
    xs = [0, _dark_line(cols, w, 1), _dark_line(cols, w, 2), w]
    ys = [0, _dark_line(rows, h, 1), _dark_line(rows, h, 2), h]
    out = []
    for r in range(3):
        for c in range(3):
            x0, x1, y0, y1 = xs[c], xs[c + 1], ys[r], ys[r + 1]
            cw, ch = x1 - x0, y1 - y0
            side = min(cw, ch) * (1.0 - 2 * INSET)
            cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
            box = (round(cx - side / 2), round(cy - side / 2), round(cx + side / 2), round(cy + side / 2))
            out.append(img.crop(box).resize((SIZE, SIZE), Image.LANCZOS))
    return out


def preview(paths: list, out: str) -> None:
    """잘라 낸 아이콘을 게임처럼 동그랗게(지름 56 px) 9개씩 한 줄로 늘어놓은 확인용 그림."""
    d = 56
    pad = 8
    rows = [paths[i:i + 9] for i in range(0, len(paths), 9)]
    sheet = Image.new("RGB", (pad + 9 * (d + pad), pad + len(rows) * (d + pad)), (38, 30, 24))
    mask = Image.new("L", (d * 4, d * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, d * 4 - 1, d * 4 - 1), fill=255)
    mask = mask.resize((d, d), Image.LANCZOS)
    for r, row in enumerate(rows):
        for c, p in enumerate(row):
            im = Image.open(p).convert("RGB").resize((d, d), Image.LANCZOS)
            sheet.paste(im, (pad + c * (d + pad), pad + r * (d + pad)), mask)
    sheet.save(out)
    print(f"wrote {out}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompts", help="지시문.md를 여기에 쓴다")
    ap.add_argument("--only", help="--prompts에 이 판 번호들만(쉼표, 예: 10,11 = UR)")
    ap.add_argument("--sheet", nargs=2, action="append", metavar=("N", "IMAGE"), default=[], help="판 번호(1~11)와 그림")
    ap.add_argument("--preview", help="잘라 낸 아이콘 확인용 그림")
    ap.add_argument("--out", default=OUT_DIR, help="아이콘 저장 폴더(기본 assets/ui/skills)")
    a = ap.parse_args()
    if a.prompts:
        write_prompts(a.prompts, [int(x) for x in a.only.split(",")] if a.only else None)
    saved = []
    for n, path in a.sheet:
        cells = SHEETS[int(n) - 1][2]
        os.makedirs(a.out, exist_ok=True)
        for (kind, _name, _desc), im in zip(cells, cells_of(Image.open(path).convert("RGB"))):
            p = os.path.join(a.out, kind + ".jpg")
            im.save(p, quality=88)
            if not os.path.exists(p + ".import"):
                with open(p + ".import", "w") as f:
                    f.write(IMPORT)
            saved.append(p)
        print(f"sheet {n}: {', '.join(c[0] for c in cells)}")
    if a.preview and saved:
        preview(saved, a.preview)
    if not a.prompts and not a.sheet:
        ap.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
