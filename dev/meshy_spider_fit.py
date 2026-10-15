"""Meshy 거미(파티 퀘스트 거미 여왕·새끼 거미) 메시 -> 부품 GLB (scripts/spider_model.gd가 움직인다).

Usage: python3 dev/meshy_spider_fit.py <meshy>.glb assets/models/meshy/enemies/<spider_queen|spiderling>.glb [--tex 1024] [--open 0.05] [--preview out.png]
Needs numpy, scipy, Pillow (dev/meshy_dragon_fit.py와 같은 GLB 읽기·쓰기).

드래곤처럼 사람 모양이 아니라 KayKit 뼈대를 못 쓴다. 움직일 부위를 잘라 부품마다 노드(원점 = 관절)로 둔다:
Body(머리가슴, 원점 = 배와 이어지는 허리), Abdomen(배, 허리 관절), Head(머리 앞쪽 — 눈·송곳니, 목 관절),
L1~L4(-X)·R1~R4(+X)(다리, 1 = 앞, 몸에 붙는 엉덩이 관절). 노드는 모두 뿌리 아래에 평평하게 있고 spider_model.gd가 Body 아래로 옮긴다.
정면 = Meshy 그대로 +Z(dragon과 같다). 바닥 y = 0, 키 = 1(게임 크기는 spider_model.gd size).

자르기: 메시 속을 채운 복셀을 공(--open, 반지름 = 키 비율)으로 열면(opening) 가는 다리가 지워지고 몸(배·머리가슴)만 남는다
(위에서 본 실루엣으로는 머리 밑으로 뻗은 앞다리가 몸에 가려 안 된다). 그 밖의 삼각형이 다리 후보 → 메시 연결 덩어리로 묶어 큰 것 8개 = 다리(작은 것 — 송곳니·가시 — 은 몸). 다리 원점 = 몸과 맞닿은 경계 정점 가운데.
배·머리가슴 경계 = 몸 단면이 가장 작은 z(허리).
"""
import io, json, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from meshy_fit import load_meshy  # noqa: E402
from meshy_summon_fit import write  # noqa: E402

NAMES = ["Body", "Abdomen", "Head", "L1", "L2", "L3", "L4", "R1", "R2", "R3", "R4"]
VOX = 0.012  # 복셀 한 변(키 비율)
HEAD_FRAC = 0.42  # 머리가슴 앞쪽 이만큼(길이 비율)이 Head


def solid(P, tri, lo, n):
    """메시 속을 채운 복셀(겉면 점을 고르게 뿌린 뒤 구멍 메우기)."""
    A, B, Cc = P[tri[:, 0]], P[tri[:, 1]], P[tri[:, 2]]
    area = np.linalg.norm(np.cross(B - A, Cc - A), axis=1) / 2
    k = np.maximum(6, (area / (VOX * VOX) * 24).astype(int))
    rep = np.repeat(np.arange(len(tri)), k)
    u, v = np.random.default_rng(0).random((2, len(rep)))
    flip = u + v > 1
    u[flip], v[flip] = 1 - u[flip], 1 - v[flip]
    pts = A[rep] + (B[rep] - A[rep]) * u[:, None] + (Cc[rep] - A[rep]) * v[:, None]
    vol = np.zeros(n, bool)
    ijk = np.clip(((pts - lo) / VOX).astype(int) + 1, 0, np.array(n) - 1)
    vol[ijk[:, 0], ijk[:, 1], ijk[:, 2]] = True
    vol = ndimage.binary_closing(vol, iterations=1)
    # 3D 구멍 메우기는 겉면의 작은 틈(열린 모서리) 하나로 새어 버린다 — 축마다 2D 단면을 메워 둘 이상이 속이라 하면 속
    votes = np.zeros(n, np.int8)
    for ax in range(3):
        f = np.zeros(n, bool)
        for i in range(n[ax]):
            sl = [slice(None)] * 3
            sl[ax] = i
            f[tuple(sl)] = ndimage.binary_fill_holes(vol[tuple(sl)])
        votes += f
    return vol | (votes >= 2)


def weld(P, tri):
    _, w = np.unique(np.round(P, 5), axis=0, return_inverse=True)
    return w.reshape(-1)[tri]


def split(P, tri, open_r):
    C = P[tri].mean(1)
    lo = P.min(0)
    n = tuple(int(v) for v in ((P.max(0) - lo) / VOX).astype(int) + 3)
    vol = solid(P, tri, lo, n)
    r = max(1, int(round(open_r / VOX)))
    zz, yy, xx = np.mgrid[-r:r + 1, -r:r + 1, -r:r + 1]
    body_v = ndimage.binary_opening(vol, structure=(xx * xx + yy * yy + zz * zz) <= r * r)  # 가는 다리는 지워지고 몸만 남는다
    lab, nl = ndimage.label(body_v)
    if nl > 1:  # 가장 큰 덩어리만(다리 끝 뭉치가 남으면 뺀다)
        body_v = lab == (np.bincount(lab.reshape(-1))[1:].argmax() + 1)
    near = ndimage.binary_dilation(body_v, iterations=2)
    ijk = np.clip(((C - lo) / VOX).astype(int) + 1, 0, np.array(n) - 1)
    inside = near[ijk[:, 0], ijk[:, 1], ijk[:, 2]]
    # 다리 후보 → 연결 덩어리
    W = weld(P, tri)
    cand = np.nonzero(~inside)[0]
    nv = W.max() + 1
    e = np.concatenate([W[cand][:, [0, 1]], W[cand][:, [1, 2]]])
    _, vlab = connected_components(coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(nv, nv)), directed=False)
    tlab = vlab[W[cand, 0]]
    sizes = np.bincount(tlab)
    order = np.argsort(-sizes)
    nleg = 8 if len(order) >= 8 and sizes[order[7]] >= 0.3 * sizes[order[0]] else 6  # Meshy가 다리를 6개로 만들기도 한다(2026-10 여왕) → 넷째 쌍은 복사
    big = order[:nleg]
    if len(big) < nleg or sizes[big[-1]] < 0.3 * sizes[big[0]]:
        top = np.argsort(-sizes)[:12]
        raise SystemExit("다리 덩어리가 8개가 아니다(--open을 바꿔 본다): %s" % [(int(sizes[k]), C[cand[tlab == k]].mean(0).round(2).tolist()) for k in top if sizes[k]])
    part = np.zeros(len(tri), int)  # 0 = 몸(아직 Body·Abdomen·Head 안 나눔)
    # 허리: 몸 단면(z 슬라이스 복셀 수)이 가장 작은 z(가운데 40% 안)
    area = body_v.sum((0, 1)).astype(float)
    rows = np.nonzero(area)[0]
    a, b = rows.min(), rows.max()
    mid = np.arange(a + int(0.3 * (b - a)), a + int(0.7 * (b - a)) + 1)
    px = VOX
    z_cut = lo[2] + (mid[np.argmin(area[mid])] - 1) * px
    z_front = C[inside, 2].max()
    z_head = z_front - HEAD_FRAC * (z_front - z_cut)
    legs = []
    for k in big:
        idx = cand[tlab == k]
        c = C[idx].mean(0)
        legs.append((idx, c))
    side = {"L": [], "R": []}
    vert_body = np.zeros(nv, bool)
    vert_body[W[inside].reshape(-1)] = True
    pivots = {}
    Pw = np.zeros((nv, 3))
    Pw[W.reshape(-1)] = P[tri.reshape(-1)]
    for idx, c in legs:
        vs = np.unique(W[idx].reshape(-1))
        edge = vs[vert_body[vs]]  # 몸 삼각형과 같이 쓰는 정점 = 관절 고리
        allv = W[idx].reshape(-1)
        if len(edge) >= 3:
            piv = Pw[edge].mean(0)
        else:  # 몸과 안 이어졌으면 몸 가운데에 가장 가까운 점들
            pts = Pw[np.unique(allv)]
            dd = np.hypot(pts[:, 0], pts[:, 2] - z_cut)
            piv = pts[dd <= np.percentile(dd, 5)].mean(0)
        side["L" if c[0] < 0 else "R"].append((piv[2], idx, piv))  # 이름: 쪽(x 부호)마다 관절 z가 앞(큰 것)부터 1~4
    if len(side["L"]) != nleg // 2 or len(side["R"]) != nleg // 2:
        raise SystemExit("쪽마다 다리 %d개가 아니다: L %d R %d" % (nleg // 2, len(side["L"]), len(side["R"])))
    extra = {}
    for s in "LR":
        slots = [1, 2, 3, 4] if nleg == 8 else [1, 3, 4]
        legs_s = sorted(side[s], key=lambda q: -q[0])
        for i, (_, idx, piv) in zip(slots, legs_s):
            k = NAMES.index("%s%d" % (s, i))
            part[idx] = k
            pivots[k] = piv
        if nleg == 6:  # 둘째 다리 = 가운데 다리(3)를 앞 다리(1)와 그 사이 방향으로 돌린 복사본, 관절도 둘 사이
            yaw = []
            for _, idx, piv in legs_s[:2]:
                pts = P[tri[idx].reshape(-1)]
                tip = pts[np.argmax(np.hypot(pts[:, 0] - piv[0], pts[:, 2] - piv[2]))]
                yaw.append(np.arctan2(tip[0] - piv[0], tip[2] - piv[2]))
            want = yaw[1] + 0.5 * np.angle(np.exp(1j * (yaw[0] - yaw[1])))
            k2 = NAMES.index(s + "2")
            pivots[k2] = (legs_s[0][2] + legs_s[1][2]) / 2
            extra[k2] = (NAMES.index(s + "3"), float(want - yaw[1]))
    body = part == 0
    part[body & (C[:, 2] < z_cut)] = 1
    part[body & (C[:, 2] > z_head)] = 2
    piv = np.zeros((len(NAMES), 3))
    for k, v in pivots.items():
        piv[k] = v
    ceph = C[part == 0]
    waist = C[(part <= 1) & (np.abs(C[:, 2] - z_cut) < 2 * px + 0.02)]
    wy = waist[:, 1].mean() if len(waist) else ceph[:, 1].mean()
    piv[0] = [0.0, wy, z_cut]
    piv[1] = [0.0, wy, z_cut]
    hd = C[part == 2]
    piv[2] = [0.0, hd[:, 1].mean(), z_head]
    return part, piv, extra, dict(z_cut=float(z_cut), z_head=float(z_head), open_px=r, legs=nleg)


def add_copies(P, nrm, uv, tri, part, piv, extra):
    """extra = {새 부품: (원본 부품, 돌릴 각)} — 원본 다리 삼각형을 자기 관절 둘레로 Y축만큼 돌려 새 관절로 옮겨 붙인다."""
    for k, (src, ang) in extra.items():
        t = tri[part == src]
        used, local = np.unique(t.reshape(-1), return_inverse=True)
        c, sn = np.cos(ang), np.sin(ang)
        R = np.array([[c, 0, sn], [0, 1, 0], [-sn, 0, c]])  # Godot와 같은 +Y축 회전(yaw = atan2(x, z)가 ang만큼 는다)
        q = (P[used] - piv[src]) @ R.T + piv[k]
        base = len(P)
        P = np.concatenate([P, q])
        nrm = np.concatenate([nrm, nrm[used] @ R.T])
        uv = np.concatenate([uv, uv[used]])
        tri = np.concatenate([tri, local.reshape(-1, 3) + base])
        part = np.concatenate([part, np.full(len(t), k)])
    return P, nrm, uv, tri, part


def preview(P, tri, part, piv, out):
    cols = [(150, 150, 160), (120, 60, 160), (60, 180, 80), (220, 60, 60), (230, 140, 40), (220, 200, 40), (160, 90, 40),
            (60, 90, 220), (60, 200, 220), (40, 140, 140), (120, 120, 240)]
    W = 380
    img = Image.new("RGB", (W * 3, W), (240, 240, 240))
    d = ImageDraw.Draw(img)
    lo, hi = P.min(0), P.max(0)
    s = (W - 20) / (hi - lo).max()
    C = P[tri].mean(1)
    for vi, (ax, ay, az, sg, fy) in enumerate([(0, 1, 2, 1, 1), (2, 1, 0, 1, 1), (0, 2, 1, 1, -1)]):
        def xy(p):
            y = (p[ay] - lo[ay]) * s
            return (vi * W + 10 + (p[ax] - lo[ax]) * s, W - 10 - y if fy > 0 else 10 + y)
        for t in np.argsort(C[:, az] * sg):
            d.polygon([xy(P[v]) for v in tri[t]], fill=cols[part[t]], outline=(0, 0, 0))
        for k in range(len(NAMES)):
            x, y = xy(piv[k])
            d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(0, 0, 0))
    img.save(out)


def main():
    src, out = sys.argv[1:3]
    size = int(sys.argv[sys.argv.index("--tex") + 1]) if "--tex" in sys.argv else 1024
    open_r = float(sys.argv[sys.argv.index("--open") + 1]) if "--open" in sys.argv else 0.05
    P, uv, idx, tex, nrm = load_meshy(src)
    lo, hi = P.min(0), P.max(0)
    P = (P - [(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2]) / (hi[1] - lo[1])
    tri = idx.reshape(-1, 3)
    part, piv, extra, info = split(P, tri, open_r)
    P, nrm, uv, tri, part = add_copies(P, nrm, uv, tri, part, piv, extra)
    # 원점: 허리(Body 원점) 아래 바닥 — 몸이 돌아도 제자리
    shift = np.array([0.0, 0.0, piv[0, 2]])
    P = P - shift
    piv = piv - shift
    if "--preview" in sys.argv:
        preview(P, tri, part, piv, sys.argv[sys.argv.index("--preview") + 1])
    parts = []
    for k in range(len(NAMES)):
        t = tri[part == k]
        used, local = np.unique(t.reshape(-1), return_inverse=True)
        parts.append((NAMES[k], piv[k], P[used], nrm[used], uv[used], local.astype(np.uint32)))
    img = Image.open(io.BytesIO(tex)).convert("RGB")
    if img.width > size:
        img = img.resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=88)
    write(parts, buf.getvalue(), out)
    print(json.dumps({"tris": int(len(tri)), "parts": dict(zip(NAMES, [int((part == k).sum()) for k in range(len(NAMES))])),
                      "size": [round(v, 3) for v in (P.max(0) - P.min(0))], "pivots": piv.round(3).tolist(), **info}))


if __name__ == "__main__":
    main()
