#!/usr/bin/env python3
"""소개 영상(dev/tour)용 로컬 서버 채우기: 로컬 테스트 서버(메모리 PGlite, ALLOW_TEST_HOOKS=1)에만 쓴다.
성주 한 명(영상 주인공) + AI 성주 9명: 친구·길드·채팅·랭킹·거래소·공지·우편을 실제 서버 데이터로 만든다.
실행: python3 dev/tour/seed.py http://127.0.0.1:8790 <영상 주인공 device_id>
"""
import json
import random
import time
import sys
import urllib.request

API = sys.argv[1].rstrip("/")
MAIN_DEVICE = sys.argv[2]
assert API.startswith("http://127.0.0.1") or API.startswith("http://localhost"), "local test server only"
random.seed(7)
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def call(method, path, body=None, token=None, ok_fail=False):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("content-type", "application/json")
    if token:
        req.add_header("authorization", "Bearer " + token)
    try:
        with OPENER.open(req, timeout=30) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        msg = e.read().decode(errors="replace")[:200]
        if not ok_fail:
            print("FAIL", method, path, e.code, msg)
        return None


def login(device):
    r = call("POST", "/v1/auth/guest", {"device_id": device})
    return r["token"], r["player_id"]


def me(tok):
    return call("GET", "/v1/player", token=tok)


HEROES = [l.split(",")[0] for l in open("data/heroes.csv", encoding="utf-8").read().splitlines()[1:] if l.strip()]
BUILD = {"keep": 22, "gate": 22, "barracks": 20, "tavern": 1, "lab": 18, "houses": 20, "lumber": 20, "quarry": 20, "farm": 20,
         "archery": 18, "stable": 18, "warehouse": 18, "goldmine": 16, "forge": 15, "guild_hall": 12, "watchtower": 12, "dispatch": 10}

for kv in [("tutorial_new_players", "0")]:
    call("POST", "/v1/test/config", {"key": kv[0], "value": kv[1]})

# ---- 주인공
mt, mid = login(MAIN_DEVICE)
call("POST", "/v1/nickname", {"name": "일성성주"}, mt)
call("POST", "/v1/test/stage", {"stage": 52}, mt)
call("POST", "/v1/test/levels", {"levels": BUILD, "res": {"wood": 8_500_000, "stone": 6_200_000, "food": 9_100_000}, "gold": 48_000_000}, mt)
call("POST", "/v1/test/grant_diamonds", {"amount": 120_000}, mt)


def place_all(tok):
    """테스트 훅으로 레벨만 정한 건물은 자리가 없다(기본 자리가 없는 자유 건설 건물) — 성주가 [건설]로 고르듯 빈 자리에 하나씩 놓는다."""
    cells = [(x, y) for y in range(-11, 12, 3) for x in range(-11, 12, 3)]
    random.Random(3).shuffle(cells)
    for bid in ("farm", "watchtower", "guild_hall", "forge", "warehouse", "dispatch", "goldmine"):
        for cxy in list(cells):
            if call("POST", "/v1/building/move", {"building": bid, "cell": list(cxy)}, tok, ok_fail=True):
                cells.remove(cxy)
                break
        else:
            print("no cell for", bid)


place_all(mt)
for h in HEROES:
    if h not in ("chronos", "jujak", "cheongryong", "hyeonmu"):  # UR 몇은 아직 없음(모집 화면에서 보이게)
        call("POST", "/v1/test/grant_hero", {"hero_id": h}, mt)
for h in HEROES[:12]:
    call("POST", "/v1/test/shards", {"hero_id": h, "shards": random.choice([3, 8, 15, 30])}, mt)
call("POST", "/v1/test/grant_items", {"grades": ["N", "R", "R", "SR", "SR", "SSR", "SSR", "UR", "LR", "R", "SR", "N"]}, mt)
call("POST", "/v1/test/speedups", {"items": {"any_5": 30, "any_60": 12, "build_480": 4, "research_180": 6}}, mt)
for n in [1] * 14:  # 훈련은 한 번에 1마리(train_batch_base 1) → 시간 앞당겨 수령, 여러 번
    for bld in ("barracks", "archery", "stable"):
        call("POST", "/v1/soldiers/train", {"building": bld, "count": n}, mt, ok_fail=True)
    call("POST", "/v1/test/age", {"minutes": 20000}, mt)
    for bld in ("barracks", "archery", "stable"):
        call("POST", "/v1/soldiers/collect", {"building": bld}, mt, ok_fail=True)
call("POST", "/v1/test/admin", {}, mt)
call("POST", "/v1/test/attendance", {"n": 3}, mt)
call("POST", "/v1/test/dispatch", {"level": 10}, mt)
call("POST", "/v1/test/events", {"events": {"kill": 3000, "stage_clear": 40, "gacha": 30, "login": 1}}, mt, ok_fail=True)
for mode, pts in (("duel", 1830), ("total", 1540)):
    call("POST", "/v1/test/pvp_points", {"mode": mode, "points": pts}, mt, ok_fail=True)
for h in HEROES:
    call("POST", "/v1/hero/levelup", {"hero_id": h, "count": 49}, mt, ok_fail=True)
# 출전: 보유한 UR·SSR 영웅부터 성채 영웅 칸 수만큼(전투 클립에서 지지 않게)
GRADE = {l.split(",")[0]: l.split(",")[3] for l in open("data/heroes.csv", encoding="utf-8").read().splitlines()[1:] if l.strip()}
owned = [h for h in HEROES if h not in ("chronos", "jujak", "cheongryong", "hyeonmu")]
best = sorted(owned, key=lambda h: {"UR": 0, "SSR": 1, "SR": 2}.get(GRADE[h], 3))
for n in range(1, 21):
    if call("POST", "/v1/deploy", {"deploy": best[:n]}, mt, ok_fail=True):
        print("deploy", best[:n])
        break
my_code = call("GET", "/v1/friends", token=mt)["code"]
print("main", mid, "code", my_code)

# ---- AI 성주
NAMES = ["용맹한검객", "푸른마법사", "날쌘궁수", "철벽수문장", "달빛무희", "불꽃군주", "숲의현자", "그림자명궁", "서리마녀"]
bots = []
for i, n in enumerate(NAMES):
    t, pid = login("tourbot-%02d-device-0000" % i)
    call("POST", "/v1/nickname", {"name": n}, t)
    call("POST", "/v1/test/stage", {"stage": 84 - i * 6}, t)
    call("POST", "/v1/test/levels", {"levels": {k: max(1, v - i) for k, v in BUILD.items()}, "gold": 30_000_000}, t)
    call("POST", "/v1/test/grant_diamonds", {"amount": 20_000}, t)
    for h in random.sample(HEROES, 14):
        call("POST", "/v1/test/grant_hero", {"hero_id": h}, t)
    for mode, pts in (("duel", 2400 - i * 110), ("total", 2100 - i * 95)):
        call("POST", "/v1/test/pvp_points", {"mode": mode, "points": pts}, t, ok_fail=True)
    for h in HEROES:
        call("POST", "/v1/hero/levelup", {"hero_id": h, "count": 40 - i * 2}, t, ok_fail=True)
    bots.append((t, pid, n))

# 친구: 앞 5명은 친구(서로 수락), 6~7번은 받은 요청으로 남긴다
for i, (t, pid, n) in enumerate(bots[:7]):
    call("POST", "/v1/friends/request", {"id": mid}, t)
    if i < 5:
        call("POST", "/v1/friends/accept", {"id": pid}, mt)
for t, pid, n in bots[:4]:
    call("POST", "/v1/friends/gift", {"id": mid}, t, ok_fail=True)

# 길드: 0번이 만들고 1~5번 + 주인공 가입, 6번은 다른 길드
call("POST", "/v1/guild/create", {"name": "은빛기사단", "emblem": 3}, bots[0][0])
g = call("GET", "/v1/guild", token=bots[0][0]) or {}
gid = g["guild"]["guild"]["id"]
print("guild", gid)
for t, pid, n in bots[1:6]:
    call("POST", "/v1/guild/join", {"guild_id": gid}, t)
call("POST", "/v1/guild/join", {"guild_id": gid}, mt)
call("POST", "/v1/guild/create", {"name": "붉은용", "emblem": 7}, bots[6][0])
call("POST", "/v1/guild/create", {"name": "북방수호대", "emblem": 11}, bots[7][0])
for t, pid, n in bots[:6]:
    call("POST", "/v1/guild/attend", {}, t, ok_fail=True)
    call("POST", "/v1/guild/donate", {"kind": "gold"}, t, ok_fail=True)

# 채팅(메시지 사이 간격 제한이 있어 사람마다 한 줄씩)
ALL = ["안녕하세요! 오늘 길드 보스 같이 잡아요", "리치의 무덤 파티 구합니다 (전투력 30만 이상)", "다이아 모집 10회 SSR 2장 떴어요 ㅎㅎ",
       "총력전 시즌 언제 끝나요?", "골드 던전 40단계 깼습니다", "발렌 영웅 진짜 세네요", "거래소에 LR 무기 올렸어요", "새로 시작했어요 잘 부탁드립니다"]
for (t, pid, n), text in zip(bots, ALL):
    call("POST", "/v1/chat", {"channel": "all", "text": text}, t, ok_fail=True)
time.sleep(2.5)  # 채팅은 한 사람이 2초에 한 번
GUILD = ["오늘 출석 다들 하셨나요?", "길드 기부 골드로 했어요", "토요일 9시 길드전 수비 영웅 정해 주세요", "보스 2판 남았어요 화이팅"]
for (t, pid, n), text in zip(bots[:4], GUILD):
    call("POST", "/v1/chat", {"channel": "guild", "text": text}, t, ok_fail=True)

# 거래소: AI 성주들이 장비를 올린다
for i, (t, pid, n) in enumerate(bots[:6]):
    call("POST", "/v1/test/grant_items", {"grades": random.sample(["SR", "SSR", "UR", "LR"], 2)}, t)
    for it in ((call("GET", "/v1/items", token=t) or {}).get("items") or [])[:2]:
        call("POST", "/v1/market/list", {"item_id": it["id"], "currency": "gold", "price": random.choice([250_000, 800_000, 1_500_000, 4_200_000])}, t, ok_fail=True)

# 공지·우편(주인공이 관리자)
call("POST", "/v1/admin/notice", {"title": "11월 정기 점검 안내", "body": "11월 13일(목) 오전 4시~6시 서버 점검이 있습니다.\n점검 보상: 다이아 300개", "kind": "maintenance", "pinned": True}, mt)
call("POST", "/v1/admin/notice", {"title": "신규 UR 영웅 크로노스 등장!", "body": "시간의 지배자 크로노스가 다이아 모집에 등장합니다.", "kind": "event"}, mt, ok_fail=True)
call("POST", "/v1/admin/notice", {"title": "성주님들께 드리는 감사 인사", "body": "CastleRPG를 즐겨 주셔서 감사합니다."}, mt)
call("POST", "/v1/admin/mail", {"title": "출시 기념 선물", "body": "성주님, 출시를 기념해 다이아를 드립니다.", "reward": {"diamonds": 1000, "gold": 500000}, "to": "all"}, mt)
call("POST", "/v1/admin/mail", {"title": "점검 보상", "body": "점검으로 불편을 드려 죄송합니다.", "reward": {"diamonds": 300, "keys_equip": 3}, "to": my_code}, mt)
call("POST", "/v1/admin/mail", {"title": "방치 주머니 선물", "body": "가방에서 열어 보세요.", "reward": {"pouch_gold_60": 3, "pouch_res_120": 2, "pouch_gold_360": 1, "speedup_any_60": 5}, "to": my_code}, mt)
call("POST", "/v1/admin/coupon", {"code": "CASTLE2026", "reward": {"diamonds": 500}, "max_uses": 1000}, mt, ok_fail=True)
call("POST", "/v1/inquiry", {"category": "bug", "title": "결제 문의", "body": "다이아가 안 들어왔어요"}, bots[2][0], ok_fail=True)
print("SEED DONE")
