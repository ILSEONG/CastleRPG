"""로우폴리 영웅 몸 -> 삼각형 예산 안으로(docs/meshy-assets.md "로우폴리 영웅").

Usage: python3 dev/meshy_lowpoly.py assets/models/characters/<model>.glb <body>.glb assets/models/meshy/heroes/<id>.glb [--tris 4500]
Needs numpy, Pillow, scipy and pymeshlab (on a bare Linux also the libopengl0 package).

<body>.glb is dev/meshy_fit.py output for a Meshy low-poly mesh (6-7k triangles). MeshLab's quadric edge collapse with
texture keeps the UV seams, so the painted texture stays as it is; every triangle then gets its own vertices and face
normal (flat facets). Joints and weights come from the nearest vertex of the input body.
"""
import io, os, sys, tempfile
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree
import pymeshlab as ml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshy_fit import GLB, base_body, write  # noqa: E402


def main():
    base, body, out = sys.argv[1:4]
    target = int(sys.argv[sys.argv.index("--tris") + 1]) if "--tris" in sys.argv else 4500
    h = GLB(body)
    pr = h.j["meshes"][0]["primitives"][0]
    Q = h.acc(pr["attributes"]["POSITION"]).astype(np.float64)
    UV = h.acc(pr["attributes"]["TEXCOORD_0"]).astype(np.float64)
    J = h.acc(pr["attributes"]["JOINTS_0"])
    W = h.acc(pr["attributes"]["WEIGHTS_0"])
    idx = h.acc(pr["indices"]).reshape(-1, 3).astype(np.int64)
    bv = h.j["bufferViews"][h.j["images"][0]["bufferView"]]
    tex = bytes(h.bin[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]])

    # 같은 자리 정점을 묶어(UV 이음새는 면마다 UV로 남긴다) MeshLab이 읽는 OBJ + 텍스처로.
    uq, inv = np.unique(np.round(Q, 5), axis=0, return_inverse=True)
    F = inv.reshape(-1)[idx]
    keep = (F[:, 0] != F[:, 1]) & (F[:, 1] != F[:, 2]) & (F[:, 0] != F[:, 2])
    F, wuv = F[keep], UV[idx[keep]].reshape(-1, 2)
    tmp = tempfile.mkdtemp()
    Image.open(io.BytesIO(tex)).save(os.path.join(tmp, "t.png"))
    with open(os.path.join(tmp, "m.mtl"), "w") as f:
        f.write("newmtl m\nmap_Kd t.png\n")
    with open(os.path.join(tmp, "m.obj"), "w") as f:
        f.write("mtllib m.mtl\nusemtl m\n")
        f.writelines("v %.6f %.6f %.6f\n" % tuple(v) for v in uq)
        f.writelines("vt %.6f %.6f\n" % (u, 1.0 - v) for u, v in wuv)
        f.writelines("f %d/%d %d/%d %d/%d\n" % (a + 1, 3 * i + 1, b + 1, 3 * i + 2, c + 1, 3 * i + 3) for i, (a, b, c) in enumerate(F))
    ms = ml.MeshSet()
    ms.load_new_mesh(os.path.join(tmp, "m.obj"))
    if len(F) > target:
        ms.apply_filter("meshing_decimation_quadric_edge_collapse_with_texture", targetfacenum=target, qualitythr=0.5,
                        extratcoordw=1.0, preserveboundary=True, optimalplacement=True, preservenormal=True, planarquadric=True)
    m = ms.current_mesh()
    tri = m.vertex_matrix()[m.face_matrix()]
    tuv = m.wedge_tex_coord_matrix().reshape(-1, 2).copy()
    tuv[:, 1] = 1.0 - tuv[:, 1]

    V = tri.reshape(-1, 3)
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    _, near = cKDTree(Q).query(V)
    g = GLB(base)
    write(g, base_body(g)[3], V, tuv.astype(np.float32), np.arange(len(V), dtype=np.uint32), J[near].astype(np.uint16),
          W[near].astype(np.float32), tex, out, np.repeat(n, 3, 0).astype(np.float32))
    print({"out": out, "tris": len(tri), "from": len(F)})


if __name__ == "__main__":
    main()
