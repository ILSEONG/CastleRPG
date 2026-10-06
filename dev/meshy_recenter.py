"""Already fitted hero bodies -> feet on the KayKit feet (dev/meshy_fit.py feet_shift, which new fits do themselves).

Usage: python3 dev/meshy_recenter.py [<id>...]   (no ids = every assets/models/meshy/heroes/<id>.glb)
Needs numpy. Moves the MeshyBody positions in place (weights, UVs, texture untouched); running it again moves nothing.
The KayKit model per hero is the `model` column of data/heroes.csv.
"""
import csv, json, os, struct, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshy_fit import GLB, base_body, feet_shift  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def save(g, path):
    js = json.dumps(g.j, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    blob = bytes(g.bin)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + blob)


def main():
    models = {r["id"]: r["model"] for r in csv.DictReader(open(os.path.join(ROOT, "data", "heroes.csv")))}
    ids = sys.argv[1:] or sorted(i for i in models if os.path.exists(os.path.join(ROOT, "assets/models/meshy/heroes/%s.glb" % i)))
    bases = {}
    for i in ids:
        m = models[i]
        if m not in bases:
            bg = GLB(os.path.join(ROOT, "assets/models/characters/%s.glb" % m))
            bases[m] = base_body(bg)[:3]
        path = os.path.join(ROOT, "assets/models/meshy/heroes/%s.glb" % i)
        g = GLB(path)
        mesh = [k for k, me in enumerate(g.j["meshes"]) if me.get("name") == "MeshyBody"][0]
        pr = g.j["meshes"][mesh]["primitives"][0]
        acc = g.j["accessors"][pr["attributes"]["POSITION"]]
        P = g.acc(pr["attributes"]["POSITION"]).astype(np.float64)
        J = g.acc(pr["attributes"]["JOINTS_0"]).astype(np.int64)
        W = g.acc(pr["attributes"]["WEIGHTS_0"]).astype(np.float64)
        d = feet_shift(P, J, W, *bases[m], g)
        Q = (P + d).astype(np.float32)
        bv = g.j["bufferViews"][acc["bufferView"]]
        start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        assert bv.get("byteStride", 12) == 12 and acc["componentType"] == 5126
        g.bin[start:start + Q.nbytes] = Q.tobytes()
        acc["min"] = Q.min(0).tolist()
        acc["max"] = Q.max(0).tolist()
        save(g, path)
        print("%-10s dx=%+.3f dz=%+.3f" % (i, d[0], d[2]))


if __name__ == "__main__":
    main()
