"""Meshy T자세 메시 -> KayKit 뼈대에 입힌 몸 GLB (docs/meshy-assets.md "게임에 넣기").

Usage: python3 dev/meshy_fit.py assets/models/characters/Knight.glb hero_meshy.glb assets/models/meshy/heroes/<id>.glb [--tex 1024] [--unpose]
Needs numpy and Pillow.

Writes a body-only GLB: the KayKit joint hierarchy and skin (same joints, order and
inverse binds) plus the Meshy mesh as one skinned mesh ("MeshyBody"). The game
puts it on the KayKit model in place of the KayKit body. KayKit rest == bind ==
T-pose, so the Meshy T-pose mesh is aligned to it in world space and takes its
skin weights from the nearest KayKit body points.
"""
import io, json, struct, sys
import numpy as np
from PIL import Image

# --- 작은 glTF 바이너리 읽기 ---
CTYPE = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class GLB:
    def __init__(self, path):
        d = open(path, "rb").read()
        jl = struct.unpack("<I", d[12:16])[0]
        self.j = json.loads(d[20:20 + jl])
        o = 20 + jl
        bl = struct.unpack("<I", d[o:o + 4])[0]
        self.bin = bytearray(d[o + 8:o + 8 + bl])

    def acc(self, i):
        a = self.j["accessors"][i]
        bv = self.j["bufferViews"][a["bufferView"]]
        n = NCOMP[a["type"]]
        dt = np.dtype(CTYPE[a["componentType"]])
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride", 0) or n * dt.itemsize
        raw = bytes(self.bin[off:off + stride * (a["count"] - 1) + n * dt.itemsize])
        if stride == n * dt.itemsize:
            arr = np.frombuffer(raw, dtype=dt).reshape(a["count"], n)
        else:
            arr = np.stack([np.frombuffer(raw[k * stride:k * stride + n * dt.itemsize], dtype=dt) for k in range(a["count"])])
        if a.get("normalized"):
            arr = arr.astype(np.float32) / np.iinfo(dt).max
        return arr


def quat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def trs(n):
    if "matrix" in n:
        return np.array(n["matrix"]).reshape(4, 4).T
    M = np.eye(4)
    M[:3, :3] = quat(n.get("rotation", [0, 0, 0, 1])) * np.array(n.get("scale", [1, 1, 1]))
    M[:3, 3] = n.get("translation", [0, 0, 0])
    return M


GEAR_PARENTS = {"handslot.l", "handslot.r"}
FEET = ("foot.l", "foot.r", "toes.l", "toes.r")


def parents(j):
    p = {}
    for i, n in enumerate(j["nodes"]):
        for c in n.get("children", []):
            p[c] = i
    return p


def world(j, par, i):
    M = trs(j["nodes"][i])
    while i in par:
        i = par[i]
        M = trs(j["nodes"][i]) @ M
    return M


def base_body(g):
    """KayKit body points in world space with their joint weights (skin joint indices)."""
    j = g.j
    par = parents(j)
    joints = j["skins"][0]["joints"]
    jidx = {n: k for k, n in enumerate(joints)}
    P, J, W, body_nodes = [], [], [], []
    for i, n in enumerate(j["nodes"]):
        if "mesh" not in n:
            continue
        pname = j["nodes"][par[i]]["name"] if i in par else ""
        if pname in GEAR_PARENTS:
            continue
        body_nodes.append(i)
        for prim in j["meshes"][n["mesh"]]["primitives"]:
            pos = g.acc(prim["attributes"]["POSITION"]).astype(np.float64)
            if "skin" in n:
                P.append(pos)
                J.append(g.acc(prim["attributes"]["JOINTS_0"]).astype(np.int64))
                W.append(g.acc(prim["attributes"]["WEIGHTS_0"]).astype(np.float64))
            else:  # rigid piece on a bone (helmet, hat, cape)
                M = world(j, par, i)
                P.append(pos @ M[:3, :3].T + M[:3, 3])
                jj = np.zeros((len(pos), 4), np.int64)
                jj[:, 0] = jidx[par[i]]
                ww = np.zeros((len(pos), 4))
                ww[:, 0] = 1
                J.append(jj)
                W.append(ww)
    return np.concatenate(P), np.concatenate(J), np.concatenate(W), body_nodes


def joint_pos(g, name):
    j = g.j
    par = parents(j)
    i = next(k for k, n in enumerate(j["nodes"]) if n.get("name") == name)
    return world(j, par, i)[:3, 3]


def load_meshy(path):
    g = GLB(path)
    j = g.j
    par = parents(j)
    ni = next(i for i, n in enumerate(j["nodes"]) if "mesh" in n)
    M = world(j, par, ni)
    prim = j["meshes"][j["nodes"][ni]["mesh"]]["primitives"][0]
    pos = g.acc(prim["attributes"]["POSITION"]).astype(np.float64)
    pos = pos @ M[:3, :3].T + M[:3, 3]
    uv = g.acc(prim["attributes"]["TEXCOORD_0"]).astype(np.float32)
    nrm = g.acc(prim["attributes"]["NORMAL"]).astype(np.float64) @ M[:3, :3].T if "NORMAL" in prim["attributes"] else None
    idx = g.acc(prim["indices"]).reshape(-1).astype(np.uint32)
    img = j["images"][j["textures"][j["materials"][prim["material"]]["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]]
    bv = j["bufferViews"][img["bufferView"]]
    data = bytes(g.bin[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])
    return pos, uv, idx, data, nrm


def arm_line(P, frac=0.8):
    ax = np.abs(P[:, 0])
    arm = P[ax > frac * ax.max()]
    return np.median(arm[:, 1]), ax.max()


def align(P, base_P, g):
    """Uniform scale (feet -> arm line), centre, then stretch the arms so hand tips meet."""
    arm_y_b = joint_pos(g, "upperarm.l")[1]
    foot_b = base_P[:, 1].min()
    sh_b = abs(joint_pos(g, "upperarm.l")[0])
    tip_b = np.abs(base_P[np.abs(base_P[:, 1] - arm_y_b) < 0.15][:, 0]).max()
    arm_y, _ = arm_line(P)
    foot = P[:, 1].min()
    s = (arm_y_b - foot_b) / (arm_y - foot)
    Q = (P - [0, foot, 0]) * s + [0, foot_b, 0]
    band = np.abs(Q[:, 1] - arm_y_b) < 0.25
    xs = Q[band, 0]
    Q[:, 0] -= (xs.max() + xs.min()) / 2
    torso = (np.abs(Q[:, 0]) < sh_b) & (Q[:, 1] > arm_y_b - 0.5) & (Q[:, 1] < arm_y_b)
    btorso = (np.abs(base_P[:, 0]) < sh_b) & (base_P[:, 1] > arm_y_b - 0.5) & (base_P[:, 1] < arm_y_b)
    Q[:, 2] += np.median(base_P[btorso, 2]) - np.median(Q[torso, 2])
    tip = np.abs(Q[np.abs(Q[:, 1] - arm_y_b) < 0.15][:, 0]).max()
    k = (tip_b - sh_b) / (tip - sh_b)
    ax = np.abs(Q[:, 0])
    out = ax > sh_b
    Q[out, 0] = np.sign(Q[out, 0]) * (sh_b + (ax[out] - sh_b) * k)
    return Q, dict(scale=s, arm_stretch=k)


def arms_down(P):
    """Meshy sometimes ignores pose_mode t-pose (arms hanging or in an A-pose). True when the arms are not out to the sides."""
    h = P[:, 1].max() - P[:, 1].min()
    ax = np.abs(P[:, 0])
    a = P[ax > 0.55 * ax.max()]
    slope = np.polyfit(np.abs(a[:, 0]), a[:, 1], 1)[0]
    return 2 * ax.max() / h < 0.7 or slope < -0.4


def arm_sets(g):
    """Skin joint indices of each arm subtree (upperarm.l / upperarm.r and everything under it)."""
    j = g.j
    joints = j["skins"][0]["joints"]
    out = {}
    for side in "lr":
        root = next(k for k, n in enumerate(j["nodes"]) if n.get("name") == "upperarm." + side)
        sub, stack = set(), [root]
        while stack:
            k = stack.pop()
            sub.add(k)
            stack += j["nodes"][k].get("children", [])
        out[side] = np.array([joints.index(k) for k in sub if k in joints])
    return out


def arm_pose(g, theta):
    """World transforms that swing each KayKit arm down by theta (radians) about its shoulder."""
    A = {}
    for side, sgn in (("l", -1.0), ("r", 1.0)):
        p = joint_pos(g, "upperarm." + side)
        c, s = np.cos(sgn * theta), np.sin(sgn * theta)
        R = np.eye(4)
        R[:2, :2] = [[c, -s], [s, c]]
        T, Ti = np.eye(4), np.eye(4)
        T[:3, 3], Ti[:3, 3] = p, -p
        A[side] = T @ R @ Ti
    return A


def arm_mix(J, W, sets):
    """Per-vertex weight on the left / right arm subtrees."""
    return [(W * np.isin(J, sets[side])).sum(1) for side in "lr"]


def unpose_arms(P, nrm, base_P, base_J, base_W, g, idx):
    """A-pose / arms-down Meshy mesh -> T-pose: find the arm angle and scale where the posed KayKit body sits on the
    mesh, take weights there, then undo the arm swing with those weights (linear blend skinning in reverse)."""
    sets = arm_sets(g)
    aL, aR = arm_mix(base_J, base_W, sets)
    skinned = base_W.sum(1) > 0
    foot_b = base_P[:, 1].min()
    h_b = base_P[:, 1].max() - foot_b
    foot = P[:, 1].min()
    s0 = h_b / (P[:, 1].max() - foot)
    rng = np.random.default_rng(0)
    pick = rng.choice(len(base_P), min(1200, len(base_P)), replace=False)
    best = None
    for theta in np.radians(np.arange(0, 86, 5)):
        A = arm_pose(g, theta)
        Bh = np.c_[base_P, np.ones(len(base_P))]
        B = base_P * (1 - aL - aR)[:, None] + (Bh @ A["l"].T)[:, :3] * aL[:, None] + (Bh @ A["r"].T)[:, :3] * aR[:, None]
        Bs = B[pick]
        for f in np.linspace(0.8, 1.25, 10):
            Q = (P - [0, foot, 0]) * s0 * f + [0, foot_b, 0]
            Q[:, 0] -= (Q[:, 0].max() + Q[:, 0].min()) / 2
            Q[:, 2] -= np.median(Q[:, 2]) - np.median(B[:, 2])
            sub = Q[rng.choice(len(Q), min(2500, len(Q)), replace=False)]
            d = np.sqrt(((Bs[:, None, :] - sub[None, :, :]) ** 2).sum(2))
            cost = d.min(1).mean() + d.min(0).mean()  # both ways: a too-big mesh would cover the body but stick out
            if best is None or cost < best[0]:
                best = (cost, theta, s0 * f, Q, B)
    _, theta, s, Q, B = best
    J, W = transfer(Q, B, base_J, base_W, len(g.j["skins"][0]["joints"]), idx)
    mL, mR = arm_mix(J.astype(np.int64), W, sets)
    A = arm_pose(g, theta)
    M = np.eye(4)[None] * (1 - mL - mR)[:, None, None] + A["l"][None] * mL[:, None, None] + A["r"][None] * mR[:, None, None]
    Mi = np.linalg.inv(M)
    T = np.einsum("nij,nj->ni", Mi, np.c_[Q, np.ones(len(Q))])[:, :3]
    if nrm is not None:
        nrm = np.einsum("nij,nj->ni", Mi[:, :3, :3], nrm)
    return T, nrm, dict(arm_down_deg=float(np.degrees(theta)), pose_scale=float(s))


def transfer(Q, base_P, base_J, base_W, njoints, idx, k=6, smooth=3):
    n = len(Q)
    Wd = np.zeros((n, njoints))
    for a in range(0, n, 2048):
        q = Q[a:a + 2048]
        d = np.linalg.norm(q[:, None, :] - base_P[None, :, :], axis=2)
        # keep left/right apart: off the midline only same-side sources
        side_q = np.sign(np.where(np.abs(q[:, 0]) < 0.04, 0, q[:, 0]))
        side_b = np.sign(np.where(np.abs(base_P[:, 0]) < 0.04, 0, base_P[:, 0]))
        clash = (side_q[:, None] * side_b[None, :]) < 0
        d[clash] = 1e9
        nn = np.argsort(d, axis=1)[:, :k]
        dn = np.take_along_axis(d, nn, 1)
        w = 1.0 / np.maximum(dn, 1e-4) ** 2
        w /= w.sum(1, keepdims=True)
        for c in range(k):
            src = nn[:, c]
            for s in range(4):
                np.add.at(Wd, (np.arange(a, a + len(q)), base_J[src, s]), w[:, c] * base_W[src, s])
    # smooth over mesh connectivity (vertices welded by position so UV seams stay closed)
    key = np.round(Q, 5)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    m = weld.max() + 1
    Ww = np.zeros((m, njoints))
    np.add.at(Ww, weld, Wd)
    cnt = np.bincount(weld, minlength=m)[:, None]
    Ww /= cnt
    tri = weld[idx.reshape(-1, 3)]
    e = np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]], tri[:, [2, 0]]])
    e = np.concatenate([e, e[:, ::-1]])
    deg = np.bincount(e[:, 0], minlength=m)[:, None]
    for _ in range(smooth):
        acc = np.zeros_like(Ww)
        np.add.at(acc, e[:, 0], Ww[e[:, 1]])
        Ww = 0.5 * Ww + 0.5 * acc / np.maximum(deg, 1)
    Wd = Ww[weld]
    top = np.argsort(-Wd, axis=1)[:, :4]
    tw = np.take_along_axis(Wd, top, 1)
    tw /= tw.sum(1, keepdims=True)
    return top.astype(np.uint16), tw.astype(np.float32)


def feet_centre(P, J, W, g):
    """Centroid of the points whose strongest bone is a foot or toe bone of g's skin."""
    names = [g.j["nodes"][n]["name"] for n in g.j["skins"][0]["joints"]]
    dom = J[np.arange(len(J)), W.argmax(1)]
    return P[np.isin(dom, [names.index(n) for n in FEET])].mean(0)


def feet_shift(Q, J, W, bP, bJ, bW, g):
    """Sideways / front-back shift (y stays) that puts the Meshy feet where the KayKit feet are. The torso match in align()
    is thrown off by quivers, capes and bellies (up to 0.4 m on the 2026-10 batch), which left heroes off their portrait
    base and their hands off the weapon slots; the whole body was off by about the same amount, so moving it by the feet fixes all."""
    d = feet_centre(bP, bJ, bW, g) - feet_centre(Q, J, W, g)
    d[1] = 0.0
    return d


def normals(Q, idx):
    tri = idx.reshape(-1, 3)
    fn = np.cross(Q[tri[:, 1]] - Q[tri[:, 0]], Q[tri[:, 2]] - Q[tri[:, 0]])
    key = np.round(Q, 5)
    _, weld = np.unique(key, axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    N = np.zeros((weld.max() + 1, 3))
    for c in range(3):
        np.add.at(N, weld[tri[:, c]], fn)
    N = N[weld]
    return (N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)).astype(np.float32)


def write(g, body_nodes, Q, uv, idx, J, W, tex, out, nrm=None):
    """Body-only GLB: the KayKit joint hierarchy + skin (same joints/order/IBMs) + the MeshyBody mesh. No animations, no gear."""
    j = g.j
    par = parents(j)
    skin = j["skins"][0]
    mesh_nodes = {i for i, n in enumerate(j["nodes"]) if "mesh" in n}
    skinned_parent = next(par[b] for b in body_nodes if "skin" in j["nodes"][b])
    keep = []
    stack = list(j["scenes"][j.get("scene", 0)]["nodes"])
    while stack:
        i = stack.pop()
        if i in mesh_nodes:
            continue
        keep.append(i)
        stack += j["nodes"][i].get("children", [])
    keep.sort()
    remap = {o: k for k, o in enumerate(keep)}
    nodes = []
    for o in keep:
        n = {k: v for k, v in j["nodes"][o].items() if k not in ("mesh", "skin", "children")}
        ch = [remap[c] for c in j["nodes"][o].get("children", []) if c in remap]
        if ch:
            n["children"] = ch
        nodes.append(n)
    out_j = {"asset": {"version": "2.0", "generator": "CastleRPG meshy_fit"}, "scene": 0,
             "scenes": [{"nodes": [remap[i] for i in j["scenes"][j.get("scene", 0)]["nodes"]]}],
             "nodes": nodes, "accessors": [], "bufferViews": [], "buffers": []}
    blob = bytearray()

    def add(arr, target=None, typ=None, ctype=None, minmax=False):
        nonlocal blob
        while len(blob) % 4:
            blob += b"\0"
        raw = arr.tobytes()
        bv = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw)}
        if target:
            bv["target"] = target
        blob += raw
        out_j["bufferViews"].append(bv)
        if typ is None:
            return len(out_j["bufferViews"]) - 1
        a = {"bufferView": len(out_j["bufferViews"]) - 1, "componentType": ctype, "count": len(arr), "type": typ}
        if minmax:
            a["min"] = arr.min(0).tolist()
            a["max"] = arr.max(0).tolist()
        out_j["accessors"].append(a)
        return len(out_j["accessors"]) - 1

    ibm = g.acc(skin["inverseBindMatrices"]).astype(np.float32)
    out_j["skins"] = [{"name": skin.get("name", "Skin"), "joints": [remap[x] for x in skin["joints"]],
                       "inverseBindMatrices": add(ibm, None, "MAT4", 5126)}]
    attrs = {
        "POSITION": add(Q.astype(np.float32), 34962, "VEC3", 5126, True),
        "NORMAL": add(normals(Q, idx) if nrm is None else nrm, 34962, "VEC3", 5126),
        "TEXCOORD_0": add(uv, 34962, "VEC2", 5126),
        "JOINTS_0": add(J, 34962, "VEC4", 5123),
        "WEIGHTS_0": add(W, 34962, "VEC4", 5126),
    }
    big = len(Q) > 65535
    ind = add(idx.astype(np.uint32 if big else np.uint16), 34963, "SCALAR", 5125 if big else 5123)
    out_j["images"] = [{"bufferView": add(np.frombuffer(tex, np.uint8)), "mimeType": "image/jpeg", "name": "meshy_texture"}]
    out_j["samplers"] = [{"magFilter": 9729, "minFilter": 9987}]
    out_j["textures"] = [{"sampler": 0, "source": 0}]
    out_j["materials"] = [{"name": "meshy", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0,
                                                                     "roughnessFactor": 1.0}, "doubleSided": True}]
    out_j["meshes"] = [{"name": "MeshyBody", "primitives": [{"attributes": attrs, "indices": ind, "material": 0}]}]
    out_j["nodes"].append({"name": "MeshyBody", "mesh": 0, "skin": 0})
    out_j["nodes"][remap[skinned_parent]].setdefault("children", []).append(len(out_j["nodes"]) - 1)
    while len(blob) % 4:
        blob += b"\0"
    out_j["buffers"] = [{"byteLength": len(blob)}]
    js = json.dumps(out_j, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    with open(out, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


def main():
    base, meshy, out = sys.argv[1:4]
    size = int(sys.argv[sys.argv.index("--tex") + 1]) if "--tex" in sys.argv else 1024
    g = GLB(base)
    bP, bJ, bW, body_nodes = base_body(g)
    P, uv, idx, texdata, nrm = load_meshy(meshy)
    info0 = {}
    if arms_down(P) or "--unpose" in sys.argv:
        P, nrm, info0 = unpose_arms(P, nrm, bP, bJ, bW, g, idx)
    Q, info = align(P, bP, g)
    info.update(info0)
    J, W = transfer(Q, bP, bJ, bW, len(g.j["skins"][0]["joints"]), idx)
    d = feet_shift(Q, J, W, bP, bJ, bW, g)
    Q = Q + d
    info.update(feet_dx=float(d[0]), feet_dz=float(d[2]))
    im = Image.open(io.BytesIO(texdata)).convert("RGB")
    if max(im.size) > size:
        im = im.resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=88)
    if nrm is not None:
        nrm = (nrm / np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)).astype(np.float32)
    write(g, body_nodes, Q, uv, idx, J, W, buf.getvalue(), out, nrm)
    print(json.dumps({"out": out, "tris": len(idx) // 3, "verts": len(Q), **{k: round(v, 3) for k, v in info.items()},
                      "height": round(float(Q[:, 1].max() - Q[:, 1].min()), 3)}))


if __name__ == "__main__":
    main()
