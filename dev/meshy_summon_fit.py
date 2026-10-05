"""Meshy 소환수 메시 -> 부품 GLB (docs/meshy-assets.md "소환수").

Usage: python3 dev/meshy_summon_fit.py golem <meshy>.glb assets/models/meshy/summons/golem.glb [--height 2.3] [--tex 1024]
Needs numpy and Pillow.

Turns the mesh to face -Z (summon.gd front), scales it to --height with the feet on y = 0 and centred, then splits it
into the parts summon.gd animates: Part0 = body, Part1 / Part2 = the -X / +X arm. The golem's forearms and fists are
separate floating rock islands (drawn that way on purpose), so an island whose centre is far out to the side is an arm;
the arm pivots at the shoulder boulder above it. Each part is a node whose origin is its pivot. One shared JPEG texture.
"""
import io, json, struct, sys
import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from meshy_fit import load_meshy  # noqa: E402

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
    assert kind == "golem", "only the golem split is defined"
    height = float(sys.argv[sys.argv.index("--height") + 1]) if "--height" in sys.argv else 2.3
    size = int(sys.argv[sys.argv.index("--tex") + 1]) if "--tex" in sys.argv else 1024
    P, uv, idx, tex, nrm = load_meshy(src)
    flip = np.array([-1.0, 1.0, -1.0])  # Meshy 정면 +Z -> 소환수 정면 -Z
    P = P * flip
    nrm = nrm * flip
    lo, hi = P.min(0), P.max(0)
    s = height / (hi[1] - lo[1])
    P = (P - [(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2]) * s
    part, piv = split_arms(P, idx)
    tri = idx.reshape(-1, 3)
    parts = []
    for k in range(3):
        t = tri[part == k]
        used, local = np.unique(t.reshape(-1), return_inverse=True)
        parts.append(("Part%d" % k, piv[k], P[used], nrm[used], uv[used], local.astype(np.uint32)))
    img = Image.open(io.BytesIO(tex)).convert("RGB")
    if img.width > size:
        img = img.resize((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=90)
    write(parts, buf.getvalue(), out)
    print(json.dumps({"tris": int(len(tri)), "parts": [int((part == k).sum()) for k in range(3)], "scale": round(s, 4),
                      "size": [round(v, 3) for v in (P.max(0) - P.min(0))], "pivots": piv.round(3).tolist()}))


if __name__ == "__main__":
    main()
