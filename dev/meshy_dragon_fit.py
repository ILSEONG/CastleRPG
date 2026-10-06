"""Meshy 드래곤(길드 보스) 메시 -> 부품 GLB (scripts/dragon_model.gd가 움직인다).

Usage: python3 dev/meshy_dragon_fit.py dev/meshy/out/enemies/dragon/dragon_meshy.glb assets/models/meshy/enemies/dragon.glb [--tex 1024] [--preview out.png]
Needs numpy and Pillow (dev/meshy_summon_fit.py와 같은 GLB 쓰기).

Meshy 드래곤은 사람 모양이 아니라 자동 리깅(KayKit 뼈대)을 못 쓴다. 대신 움직일 부위를 잘라 부품마다 노드(원점 = 관절)로 둔다:
Body(몸통·다리), WingL(-X)·WingR(+X)(날개 뿌리 관절), Neck(목·머리, 목 밑 관절), Tail(꼬리, 엉덩이 관절).
정면은 Meshy 그대로 +Z(Godot 모델 정면, unit_model.face와 같다). 바닥 y = 0, 몸통 가운데가 원점.
"""
import io, json, sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from meshy_fit import load_meshy  # noqa: E402
from meshy_summon_fit import write  # noqa: E402

HEIGHT = 1.0  # 정규화 키(m) — 게임 크기는 dragon_model.gd SCALE
NAMES = ["Body", "WingL", "WingR", "Neck", "Tail"]


def split(P, tri):
    C = P[tri].mean(1)
    h = P[:, 1].max()
    span = P[:, 0].max()  # 좌우 대칭(가운데 0)
    zf, zb = P[:, 2].max(), P[:, 2].min()
    part = np.zeros(len(tri), int)
    # 날개: 몸 폭 밖(|x| > 0.22 × 반폭)이고 등 높이 위(다리·꼬리는 낮다)
    wing = (np.abs(C[:, 0]) > 0.22 * span) & (C[:, 1] > 0.42 * h)
    part[wing & (C[:, 0] < 0)] = 1
    part[wing & (C[:, 0] > 0)] = 2
    # 목·머리: 앞쪽 위
    neck = (part == 0) & (C[:, 2] > zb + 0.62 * (zf - zb)) & (C[:, 1] > 0.55 * h)
    part[neck] = 3
    # 꼬리: 뒤쪽(엉덩이 뒤)이고 등보다 낮다
    tail = (part == 0) & (C[:, 2] < zb + 0.32 * (zf - zb)) & (C[:, 1] < 0.6 * h)
    tail |= (part == 0) & (np.abs(C[:, 0]) > 0.3 * span) & (C[:, 1] < 0.42 * h)  # 옆으로 감아 앞으로 온 꼬리 끝
    part[tail] = 4
    piv = np.zeros((5, 3))
    for k, sx in ((1, -1), (2, 1)):
        root = (part == k)
        rx = np.abs(C[root, 0])
        near = root.copy()
        near[root] = rx < np.percentile(rx, 8)
        piv[k] = [sx * np.percentile(rx, 3), C[near, 1].mean(), C[near, 2].mean()]
    nk = C[part == 3]
    piv[3] = [0.0, nk[:, 1].min() + 0.05 * h, np.percentile(nk[:, 2], 15)]
    tl = C[(part == 4) & (np.abs(C[:, 0]) < 0.3 * span)]
    piv[4] = [0.0, np.percentile(tl[:, 1], 70), tl[:, 2].max()]
    return part, piv


def preview(P, tri, part, piv, out):
    cols = [(150, 150, 160), (220, 60, 60), (60, 90, 220), (60, 180, 80), (220, 170, 40)]
    W = 360
    img = Image.new("RGB", (W * 3, W), (240, 240, 240))
    d = ImageDraw.Draw(img)
    lo, hi = P.min(0), P.max(0)
    s = (W - 20) / (hi - lo).max()
    C = P[tri].mean(1)
    for vi, (ax, ay, az, sg) in enumerate([(0, 1, 2, 1), (2, 1, 0, -1), (0, 2, 1, 1)]):
        for t in np.argsort(C[:, az] * sg):
            d.polygon([(vi * W + 10 + (P[v, ax] - lo[ax]) * s, W - 10 - (P[v, ay] - lo[ay]) * s) for v in tri[t]], fill=cols[part[t]])
        for k in range(1, 5):
            x, y = vi * W + 10 + (piv[k, ax] - lo[ax]) * s, W - 10 - (piv[k, ay] - lo[ay]) * s
            d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(0, 0, 0))
    img.save(out)


def main():
    src, out = sys.argv[1:3]
    size = int(sys.argv[sys.argv.index("--tex") + 1]) if "--tex" in sys.argv else 1024
    P, uv, idx, tex, nrm = load_meshy(src)
    lo, hi = P.min(0), P.max(0)
    s = HEIGHT / (hi[1] - lo[1])
    P = (P - [(lo[0] + hi[0]) / 2, lo[1], 0.0]) * s
    tri = idx.reshape(-1, 3)
    part, piv = split(P, tri)
    body = P[tri[part == 0].reshape(-1)]
    shift = np.array([0.0, 0.0, body[:, 2].mean()])
    P = P - shift
    piv[1:] -= shift
    if "--preview" in sys.argv:
        preview(P, tri, part, piv, sys.argv[sys.argv.index("--preview") + 1])
    parts = []
    for k in range(5):
        t = tri[part == k]
        used, local = np.unique(t.reshape(-1), return_inverse=True)
        parts.append((NAMES[k], piv[k], P[used], nrm[used], uv[used], local.astype(np.uint32)))
    img = Image.open(io.BytesIO(tex)).convert("RGB")
    if img.width > size:
        img = img.resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=90)
    write(parts, buf.getvalue(), out)
    print(json.dumps({"tris": int(len(tri)), "parts": dict(zip(NAMES, [int((part == k).sum()) for k in range(5)])),
                      "size": [round(v, 3) for v in (P.max(0) - P.min(0))], "pivots": piv.round(3).tolist()}))


if __name__ == "__main__":
    main()
