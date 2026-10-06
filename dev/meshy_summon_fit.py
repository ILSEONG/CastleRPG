"""Meshy 소환수 메시 -> 부품 GLB (docs/meshy-assets.md "소환수").

Usage: python3 dev/meshy_summon_fit.py <kind> <meshy>.glb assets/models/meshy/summons/<kind>.glb [--tex 1024]
Needs numpy and Pillow.

Turns the mesh to face -Z (summon.gd front), scales it to the kind's size (KIND below) and splits it into the parts
summon.gd animates, the same joints as its coded shape (summon.gd _build): Part0 = body, Part1 / Part2 = the moving parts.
Each part is a node whose origin is its pivot. One shared JPEG texture. A kind with fewer parts here (spirit) takes the
rest from its coded shape in summon.gd.
- golem: forearms are separate floating rock islands (drawn that way); an island far out to the side is an arm, pivoting
  at the shoulder boulder above it.
- wolf: below the belly = legs, front pair (Part1) / hind pair (Part2), pivot at the belly cut.
- skeleton: the sword arm (Part1, outside the rib cage) and the legs (Part2, below the pelvis).
- treant: the leaf crown (Part1, above the trunk) and the two floating branch arms (Part2, one part, pivot mid-trunk).
- phoenix / hawk: the wings outside the body (Part1 -X, Part2 +X), pivot at the wing root.
- turret: the crossbow head above the turning plate (Part1).
"""
import io, json, struct, sys
import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from meshy_fit import load_meshy  # noqa: E402

# 종류 -> (키 또는 날개 폭(span) m, Meshy 정면 +Z에서 -Z로 돌린 뒤 더 돌리는 각(도, +Y축), 바닥 y). summon.gd 코드 모양 크기에 맞춘다.
KIND = {
    "golem": {"height": 2.3},
    "wolf": {"height": 1.15},
    "skeleton": {"height": 1.6},
    "treant": {"height": 2.7},
    "spirit": {"height": 1.1, "floor": -0.45},
    "phoenix": {"span": 2.4},
    "hawk": {"span": 1.7},
    "turret": {"height": 1.15, "yaw": 90.0},
}
ARM_X = 0.66  # 섬 중심 |x| > 이만큼 × 최대 |x| 이면 팔
SHOULDER_X = 0.5  # 몸 섬 중 중심 |x| > 이만큼 × 최대 |x| = 어깨(팔 관절 높이)


def islands(P, idx):
    """Triangle -> connected island id (vertices welded by position)."""
    _, inv = np.unique(np.round(P, 5), axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    par = np.arange(inv.max() + 1)

    def find(a):
        while par[a] != a:
            par[a] = par[par[a]]
            a = par[a]
        return a

    T = inv[idx.reshape(-1, 3)]
    for a, b, c in T:
        ra = find(a)
        par[find(b)] = ra
        par[find(c)] = ra
    return np.array([find(v) for v in T[:, 0]])


def split_arms(P, idx):
    """-> (part per triangle: 0 body / 1 -X arm / 2 +X arm, pivots [3 x 3])."""
    tri = idx.reshape(-1, 3)
    isl = islands(P, idx)
    xmax = np.abs(P[:, 0]).max()
    part = np.zeros(len(tri), int)
    shoulder = {1: [], 2: []}
    for i in np.unique(isl):
        sel = isl == i
        c = P[tri[sel].reshape(-1)].mean(0)
        side = 1 if c[0] < 0 else 2
        if abs(c[0]) > ARM_X * xmax:
            part[sel] = side
        elif abs(c[0]) > SHOULDER_X * xmax:
            shoulder[side].append(P[tri[sel].reshape(-1)])
    piv = np.zeros((3, 3))
    for side in (1, 2):
        arm = P[tri[part == side].reshape(-1)]
        assert len(arm) and shoulder[side], "no arm / shoulder islands on side %d" % side
        sh = np.concatenate(shoulder[side])
        piv[side] = [arm[:, 0].mean(), sh[:, 1].mean(), sh[:, 2].mean()]
    return part, piv


def cut_legs(P, tri, frac):
    """wolf: triangles under frac x height = legs; front (-Z) pair -> 1, hind -> 2. Pivot = (0, cut, mean z of the pair)."""
    C = P[tri].mean(1)
    cut = frac * P[:, 1].max()
    zc = (C[:, 2].min() + C[:, 2].max()) / 2
    part = np.where(C[:, 1] < cut, np.where(C[:, 2] < zc, 1, 2), 0)
    piv = np.zeros((3, 3))
    for k in (1, 2):
        piv[k] = [0.0, cut, C[part == k, 2].mean()]
    return part, piv


def split_skeleton(P, tri):
    """Sword arm = outside the rib cage on the sword side (the side reaching furthest forward); legs = under the pelvis."""
    C = P[tri].mean(1)
    H = P[:, 1].max()
    tip = P[P[:, 2].argmin()]  # 칼끝(정면 -Z로 가장 멀리)
    side = np.sign(tip[0])
    sh_y = 0.8 * H
    torso = (C[:, 1] > 0.6 * H) & (C[:, 1] < 0.72 * H) & (np.abs(C[:, 0]) < 0.2 * H)  # 갈비뼈
    edge = np.abs(C[torso, 0]).max()
    part = np.zeros(len(tri), int)
    arm = (C[:, 0] * side > edge) & (C[:, 1] < sh_y) & (C[:, 1] > tip[1] - 0.08 * H)
    part[arm] = 1
    legs = (C[:, 1] < 0.42 * H) & ~arm & (np.abs(C[:, 0]) < 0.17 * H)
    part[legs] = 2
    piv = np.zeros((3, 3))
    A = P[tri[arm].reshape(-1)]
    top = A[A[:, 1] > A[:, 1].max() - 0.06 * H]  # 어깨 = 팔 맨 위
    piv[1] = [top[:, 0].mean(), top[:, 1].mean(), top[:, 2].mean()]
    piv[2] = [0.0, 0.42 * H, C[legs, 2].mean()]
    return part, piv


def split_treant(P, tri, uv, img):
    """Arms = side islands (floating branches), both in Part2; crown = above the lowest leafy (green) row near the top."""
    C = P[tri].mean(1)
    isl = islands(P, tri.reshape(-1))
    xmax = np.abs(P[:, 0]).max()
    arm = np.zeros(len(tri), bool)
    for i in np.unique(isl):
        sel = isl == i
        if abs(C[sel, 0].mean()) > 0.5 * xmax:
            arm |= sel
    H = P[:, 1].max()
    col = tex_color(uv, tri, img)
    green = (col[:, 1] > col[:, 0] * 1.15) & (col[:, 1] > col[:, 2]) & (C[:, 1] > 0.6 * H) & ~arm
    cut = np.percentile(C[green, 1], 3)
    out = np.zeros(len(tri), int)
    out[(C[:, 1] > cut) & ~arm] = 1
    out[arm] = 2
    piv = np.zeros((3, 3))
    piv[1] = [0.0, cut, C[out == 1, 2].mean()]
    A = P[tri[arm].reshape(-1)]
    piv[2] = [0.0, np.percentile(A[:, 1], 85), C[out == 0, 2].mean()]
    return out, piv


def split_wings(P, tri):
    """Wings = outside the body width (measured at the head/tail line); pivot = wing root."""
    C = P[tri].mean(1)
    span = P[:, 0].max() - P[:, 0].min()
    root = 0.1 * span
    wing_y = np.median(C[np.abs(C[:, 0]) > 0.3 * span, 1])
    part = np.where(C[:, 0] < -root, 1, np.where(C[:, 0] > root, 2, 0))
    part[C[:, 1] < wing_y - 0.1 * span] = 0  # 아래로 늘어진 꼬리깃·발은 몸통
    piv = np.zeros((3, 3))
    for k, sx in ((1, -1), (2, 1)):
        near = (part == k) & (np.abs(C[:, 0]) < root * 1.6)
        piv[k] = [sx * root, C[near, 1].mean(), C[near, 2].mean()]
    return part, piv


def split_turret(P, tri, frac=0.55):
    """Head = above the turning plate; pivot on the stand axis."""
    C = P[tri].mean(1)
    cut = frac * P[:, 1].max()
    part = (C[:, 1] > cut).astype(int)
    stand = P[tri[C[:, 1] < cut].reshape(-1)]
    piv = np.zeros((2, 3))
    piv[1] = [stand[:, 0].mean(), cut, stand[:, 2].mean()]
    return part, piv


def tex_color(uv, tri, img):
    a = np.asarray(img)
    h, w = a.shape[:2]
    U = uv[tri].mean(1)
    return a[np.clip((U[:, 1] * h).astype(int), 0, h - 1), np.clip((U[:, 0] * w).astype(int), 0, w - 1)].astype(float)


def write(parts, tex, out):
    """parts = [(name, pivot, P, nrm, uv, idx)] -> GLB, one node per part at its pivot, one shared textured material."""
    j = {"asset": {"version": "2.0", "generator": "CastleRPG meshy_summon_fit"}, "scene": 0, "scenes": [{"nodes": []}],
         "nodes": [], "meshes": [], "accessors": [], "bufferViews": [], "buffers": []}
    blob = bytearray()

    def add(arr, target=None, typ=None, ctype=None, minmax=False):
        nonlocal blob
        while len(blob) % 4:
            blob += b"\0"
        raw = arr.tobytes()
        j["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw), **({"target": target} if target else {})})
        blob += raw
        if typ is None:
            return len(j["bufferViews"]) - 1
        a = {"bufferView": len(j["bufferViews"]) - 1, "componentType": ctype, "count": len(arr), "type": typ}
        if minmax:
            a["min"] = arr.min(0).tolist()
            a["max"] = arr.max(0).tolist()
        j["accessors"].append(a)
        return len(j["accessors"]) - 1

    for name, piv, P, nrm, uv, idx in parts:
        attrs = {"POSITION": add((P - piv).astype(np.float32), 34962, "VEC3", 5126, True),
                 "NORMAL": add(nrm.astype(np.float32), 34962, "VEC3", 5126),
                 "TEXCOORD_0": add(uv.astype(np.float32), 34962, "VEC2", 5126)}
        ind = add(idx.astype(np.uint16), 34963, "SCALAR", 5123)
        j["meshes"].append({"name": name, "primitives": [{"attributes": attrs, "indices": ind, "material": 0}]})
        j["nodes"].append({"name": name, "mesh": len(j["meshes"]) - 1, "translation": [float(v) for v in piv]})
        j["scenes"][0]["nodes"].append(len(j["nodes"]) - 1)
    j["images"] = [{"bufferView": add(np.frombuffer(tex, np.uint8)), "mimeType": "image/jpeg", "name": "meshy_texture"}]
    j["samplers"] = [{"magFilter": 9729, "minFilter": 9987}]
    j["textures"] = [{"sampler": 0, "source": 0}]
    j["materials"] = [{"name": "meshy", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0,
                                                                 "roughnessFactor": 1.0}, "doubleSided": True}]
    while len(blob) % 4:
        blob += b"\0"
    j["buffers"] = [{"byteLength": len(blob)}]
    js = json.dumps(j, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    with open(out, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


def main():
    kind, src, out = sys.argv[1:4]
    cfg = KIND[kind]
    size = int(sys.argv[sys.argv.index("--tex") + 1]) if "--tex" in sys.argv else 1024
    P, uv, idx, tex, nrm = load_meshy(src)
    flip = np.array([-1.0, 1.0, -1.0])  # Meshy 정면 +Z -> 소환수 정면 -Z
    P = P * flip
    nrm = nrm * flip
    a = np.radians(cfg.get("yaw", 0.0))
    R = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])  # Godot와 같은 +Y축 회전
    P = P @ R.T
    nrm = nrm @ R.T
    lo, hi = P.min(0), P.max(0)
    s = cfg["height"] / (hi[1] - lo[1]) if "height" in cfg else cfg["span"] / (hi[0] - lo[0])
    P = (P - [(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2]) * s
    P[:, 1] += cfg.get("floor", 0.0)
    tri = idx.reshape(-1, 3)
    img = Image.open(io.BytesIO(tex)).convert("RGB")
    if kind == "golem":
        part, piv = split_arms(P, idx)
    elif kind == "wolf":
        part, piv = cut_legs(P, tri, 0.36)
    elif kind == "skeleton":
        part, piv = split_skeleton(P, tri)
    elif kind == "treant":
        part, piv = split_treant(P, tri, uv, img)
    elif kind in ("phoenix", "hawk"):
        part, piv = split_wings(P, tri)
    elif kind == "turret":
        part, piv = split_turret(P, tri)
    else:
        part, piv = np.zeros(len(tri), int), np.zeros((1, 3))
    if "span" in cfg:  # 나는 것: 날개 관절 높이·깊이를 원점에(코드 모양처럼 몸 가운데가 피벗)
        c = (piv[1] + piv[2]) / 2
        shift = np.array([0.0, c[1], c[2]])
    elif kind != "golem":  # 몸통(Part0) 가운데를 원점 위에 — 앞으로 뻗은 칼·꼬리에 밀리지 않게
        body = P[tri[part == 0].reshape(-1)]
        shift = np.array([body[:, 0].mean(), 0.0, body[:, 2].mean()])
        if kind == "wolf":  # 늑대: 앞뒤 다리 사이 가운데
            shift[2] = (piv[1, 2] + piv[2, 2]) / 2
    else:
        shift = np.zeros(3)
    P = P - shift
    piv[1:] -= shift
    parts = []
    for k in range(len(piv)):
        t = tri[part == k]
        used, local = np.unique(t.reshape(-1), return_inverse=True)
        parts.append(("Part%d" % k, piv[k], P[used], nrm[used], uv[used], local.astype(np.uint32)))
    if img.width > size:
        img = img.resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=90)
    write(parts, buf.getvalue(), out)
    print(json.dumps({"kind": kind, "tris": int(len(tri)), "parts": [int((part == k).sum()) for k in range(len(piv))],
                      "scale": round(s, 4), "size": [round(v, 3) for v in (P.max(0) - P.min(0))], "pivots": piv.round(3).tolist()}))


if __name__ == "__main__":
    main()
