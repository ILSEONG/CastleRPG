"""Meshy 고해상도 GLB -> 게임 면 수로 줄인 GLB (텍스처·UV 그대로). 몸 맞추기는 그다음 dev/meshy_fit.py.

Usage: python3 dev/meshy_decimate.py <id>_hq.glb out.glb --tris 12000 [--head-tris 3000] [--head 0.18,0.28]
--head-tris N: 머리(|x| < 0.18, y > 0.28 — Meshy T자세 메시 좌표, 높이 약 -0.95..0.95)에 삼각형 N개를 따로 남긴다.

UR 최고 설정 재생성(2026-10-29, dev/meshy_heroes.py hq)은 리메시 없이 수십만 삼각형으로 나온다. Meshy 리메시(5크레딧)
대신 여기서 텍스처 보존 이차 오차 축소(pymeshlab)로 줄인다: 같은 자리 정점을 이어 붙여 UV 이음매에서 구멍이 나지 않게 하고,
줄인 뒤 UV가 다른 모서리만 정점을 다시 나눈다. 법선은 이어 붙인 메시에서 구해 이음매에 줄이 생기지 않게 한다.
Needs numpy and pymeshlab.
"""
import json, os, shutil, struct, sys, tempfile
import numpy as np
import pymeshlab
from meshy_fit import GLB, load_meshy


def weld(P, idx):
    key = np.round(P / 1e-5).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return P[first], inv.reshape(-1)[idx].reshape(-1, 3)


def decimate(P, uv, idx, tris, head_tris=0, head=(0.18, 0.28)):
    V, F = weld(P, idx)
    # pymeshlab.Mesh로 넣으면 면마다 텍스처 번호가 비어 축소 필터가 거부한다 — OBJ(+mtl)로 읽혀 텍스처 0번을 달게 한다
    d = tempfile.mkdtemp()
    with open(os.path.join(d, "m.mtl"), "w") as f:
        f.write("newmtl m\nmap_Kd t.png\n")
    open(os.path.join(d, "t.png"), "wb").write(b"")
    with open(os.path.join(d, "m.obj"), "w") as f:
        f.write("mtllib m.mtl\nusemtl m\n")
        f.write("".join("v %.6f %.6f %.6f\n" % tuple(v) for v in V))
        f.write("".join("vt %.6f %.6f\n" % tuple(t) for t in uv))
        f.write("".join("f %d/%d %d/%d %d/%d\n" % (a + 1, i + 1, b + 1, j + 1, c + 1, k + 1)
                        for (a, b, c), (i, j, k) in zip(F, idx.reshape(-1, 3))))
    ms = pymeshlab.MeshSet()
    ms.load_new_mesh(os.path.join(d, "m.obj"))
    shutil.rmtree(d)
    ms.meshing_remove_unreferenced_vertices()
    args = dict(qualitythr=0.5, extratcoordw=1.0, preserveboundary=True, boundaryweight=2.0, optimalplacement=True,
                preservenormal=True, planarquadric=True)
    if head_tris:  # 얼굴은 면을 더 남긴다(같은 비율로 줄이면 눈썹·코·수염 윤곽이 먼저 사라진다)
        hx, hy = head
        cond = " && ".join("(abs(x%d) < %f) && (y%d > %f)" % (k, hx, k, hy) for k in range(3))
        ms.compute_selection_by_condition_per_face(condselect=cond)  # 선택만 줄일 때 targetfacenum = 남길 선택 면 수
        if ms.current_mesh().selected_face_number() > head_tris:
            ms.meshing_decimation_quadric_edge_collapse_with_texture(targetfacenum=head_tris, selected=True, **args)
        ms.compute_selection_by_condition_per_face(condselect=cond)
        n_head = ms.current_mesh().selected_face_number()
        ms.apply_selection_inverse(invfaces=True)
        ms.meshing_decimation_quadric_edge_collapse_with_texture(targetfacenum=max(tris - n_head, 1000), selected=True, **args)
        ms.set_selection_none()
    else:
        ms.meshing_decimation_quadric_edge_collapse_with_texture(targetfacenum=tris, **args)
    ms.meshing_remove_unreferenced_vertices()
    m = ms.current_mesh()
    V, F = m.vertex_matrix(), m.face_matrix()
    W = m.wedge_tex_coord_matrix().reshape(-1, 2)
    N = crease_normals(V, F, CREASE)
    # UV나 법선이 다른 모서리만 정점 나누기
    key = np.concatenate([F.reshape(-1, 1).astype(np.float64), np.round(W / 1e-6), np.round(N / 1e-4)], axis=1)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    vid = F.reshape(-1)[first]
    return V[vid], W[first].astype(np.float32), N[first].astype(np.float32), inv.reshape(-1).astype(np.uint32)


CREASE = 35.0  # 면 사이 각이 이보다 크면 모서리를 날카롭게(컨셉의 각진 로우폴리 얼굴·장식 — 부드러운 법선이면 눈썹·코가 뭉개진다)


def crease_normals(V, F, deg):
    """모서리(면 꼭짓점)마다 법선: 그 정점을 쓰는 면 중 이 면과 deg 이내로 꺾인 면들의 넓이 가중 평균."""
    fn = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    unit = fn / np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    corner_v = F.reshape(-1)
    corner_f = np.repeat(np.arange(len(F)), 3)
    order = np.argsort(corner_v, kind="stable")
    starts = np.flatnonzero(np.r_[True, np.diff(corner_v[order]) != 0])
    ends = np.r_[starts[1:], len(order)]
    cos = np.cos(np.radians(deg))
    out = np.zeros((len(corner_v), 3))
    for s, e in zip(starts, ends):
        cs = order[s:e]
        fs = corner_f[cs]
        mask = unit[fs] @ unit[fs].T > cos
        out[cs] = mask @ fn[fs]
    return out / np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-12)


def write(path, P, uv, N, idx, tex, mime):
    blob = bytearray()
    j = {"asset": {"version": "2.0", "generator": "meshy_decimate"}, "bufferViews": [], "accessors": []}

    def add(arr, target=None, typ=None, ctype=None, minmax=False):
        raw = arr.tobytes() if isinstance(arr, np.ndarray) else bytes(arr)
        while len(blob) % 4:
            blob.append(0)
        bv = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw)}
        if target:
            bv["target"] = target
        blob.extend(raw)
        j["bufferViews"].append(bv)
        if typ is None:
            return len(j["bufferViews"]) - 1
        a = {"bufferView": len(j["bufferViews"]) - 1, "componentType": ctype, "count": len(arr), "type": typ}
        if minmax:
            a["min"], a["max"] = arr.min(0).tolist(), arr.max(0).tolist()
        j["accessors"].append(a)
        return len(j["accessors"]) - 1

    attrs = {"POSITION": add(P.astype(np.float32), 34962, "VEC3", 5126, True), "NORMAL": add(N, 34962, "VEC3", 5126),
             "TEXCOORD_0": add(uv, 34962, "VEC2", 5126)}
    ind = add(idx, 34963, "SCALAR", 5125)
    j["images"] = [{"bufferView": add(tex), "mimeType": mime}]
    j["samplers"] = [{"magFilter": 9729, "minFilter": 9987}]
    j["textures"] = [{"sampler": 0, "source": 0}]
    j["materials"] = [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 1.0}}]
    j["meshes"] = [{"primitives": [{"attributes": attrs, "indices": ind, "material": 0}]}]
    j["nodes"] = [{"name": "Mesh", "mesh": 0}]
    j["scenes"] = [{"nodes": [0]}]
    j["scene"] = 0
    while len(blob) % 4:
        blob.append(0)
    j["buffers"] = [{"byteLength": len(blob)}]
    js = json.dumps(j, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


def main():
    src, out = sys.argv[1:3]
    tris = int(sys.argv[sys.argv.index("--tris") + 1]) if "--tris" in sys.argv else 12000
    head_tris = int(sys.argv[sys.argv.index("--head-tris") + 1]) if "--head-tris" in sys.argv else 0
    head = tuple(float(v) for v in sys.argv[sys.argv.index("--head") + 1].split(",")) if "--head" in sys.argv else (0.18, 0.28)
    P, uv, idx, tex, _ = load_meshy(src)
    g = GLB(src)
    mime = g.j["images"][0].get("mimeType", "image/png")
    Q, UV, N, I = decimate(P, uv, idx, tris, head_tris, head)
    write(out, Q, UV, N, I, tex, mime)
    print(json.dumps({"out": out, "src_tris": len(idx) // 3, "tris": len(I) // 3, "verts": len(Q)}))


if __name__ == "__main__":
    main()
