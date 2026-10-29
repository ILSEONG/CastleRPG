"""Meshy 고해상도 GLB -> 게임 면 수로 줄인 GLB (텍스처·UV 그대로). 몸 맞추기는 그다음 dev/meshy_fit.py.

Usage: python3 dev/meshy_decimate.py <id>_hq.glb out.glb --tris 12000 [--head-tris 4000] [--head 0.18,0.28] [--tex 2048] [--no-rebake]
텍스처는 줄인 메시 UV에 원본 표면 색을 다시 굽는다(--tex 크기, 기본 2048; --no-rebake면 원본 텍스처 그대로).
청룡(몸을 감은 용)은 머리를 따로 줄이면 몸 쪽 축소가 깨진다(큰 삼각형·뭉개진 텍스처) — --head-tris 없이 줄인다.
--head-tris N: 머리(|x| < 0.18, y > 0.28 — Meshy T자세 메시 좌표, 높이 약 -0.95..0.95)에 삼각형 N개를 따로 남긴다.

UR 최고 설정 재생성(2026-10-29, dev/meshy_heroes.py hq)은 리메시 없이 수십만 삼각형으로 나온다. Meshy 리메시(5크레딧)
대신 여기서 텍스처 보존 이차 오차 축소(pymeshlab)로 줄인다: 같은 자리 정점을 이어 붙여 UV 이음매에서 구멍이 나지 않게 하고,
줄인 뒤 UV가 다른 모서리만 정점을 다시 나눈다. 법선은 이어 붙인 메시에서 구해 이음매에 줄이 생기지 않게 한다.
Needs numpy, scipy, Pillow and pymeshlab.
"""
import io, json, os, shutil, struct, sys, tempfile
import numpy as np
import pymeshlab
from PIL import Image
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
    args = dict(qualitythr=0.5, extratcoordw=4.0, preserveboundary=True, boundaryweight=2.0, optimalplacement=True,
                preservenormal=True, planarquadric=True)  # extratcoordw 4: UV를 덜 일그러뜨린다(1이면 눈가에 머리색 줄)
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


def rebake(P, uv, idx, img, Q, UV, N, I, size):
    """줄인 메시의 UV 자리마다 원본(고해상도) 표면의 가장 가까운 점 색을 다시 굽는다. 같은 UV 배치를 쓰더라도 면을 접으면
    텍스처가 끌려가 무늬(현무 등껍질 육각 무늬)가 일그러진다 — 원본 표면에서 다시 가져오면 원본 그대로 보인다."""
    from scipy.spatial import cKDTree
    from scipy.ndimage import distance_transform_edt
    F = idx.reshape(-1, 3)
    A, B, C = P[F[:, 0]], P[F[:, 1]], P[F[:, 2]]
    fn = np.cross(B - A, C - A)
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    tree = cKDTree((A + B + C) / 3)
    src = np.asarray(img.convert("RGB"), np.float32)
    sh, sw = src.shape[:2]
    # 줄인 메시를 UV 평면에 그려 텍셀마다 3D 점·법선
    G = I.reshape(-1, 3)
    pix, pts, nrm = [], [], []
    for tri in G:
        t2 = UV[tri].astype(np.float64) * size
        x0, y0 = np.floor(t2.min(0)).astype(int)
        x1, y1 = np.ceil(t2.max(0)).astype(int)
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, size - 1), min(y1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        q = np.stack([xs.ravel(), ys.ravel()], 1)
        a, b, c = t2
        m = np.array([b - a, c - a]).T
        if abs(np.linalg.det(m)) < 1e-12:
            continue
        l12 = np.linalg.solve(m, (q - a).T).T
        w = np.c_[1 - l12.sum(1), l12]
        ok = (w > -1e-4).all(1)
        if not ok.any():
            continue
        w = w[ok]
        pix.append((q[ok] - 0.5).astype(np.int64))
        pts.append(w @ Q[tri])
        nrm.append(w @ N[tri])
    pix, pts, nrm = np.concatenate(pix), np.concatenate(pts), np.concatenate(nrm)
    col = np.zeros((len(pts), 3), np.float32)
    for s in range(0, len(pts), 200000):
        p, n = pts[s:s + 200000], nrm[s:s + 200000]
        _, cand = tree.query(p, k=8)
        a, b, c = A[cand], B[cand], C[cand]
        nf = fn[cand]
        # 삼각형 평면에 내린 점의 무게중심 좌표(밖이면 잘라 다시 맞춤) — 원본 삼각형은 아주 작아 근사로 충분
        v0, v1, v2 = b - a, c - a, p[:, None] - a
        d00, d01, d11 = (v0 * v0).sum(2), (v0 * v1).sum(2), (v1 * v1).sum(2)
        d20, d21 = (v2 * v0).sum(2), (v2 * v1).sum(2)
        den = np.maximum(d00 * d11 - d01 * d01, 1e-20)
        bv, bw = (d11 * d20 - d01 * d21) / den, (d00 * d21 - d01 * d20) / den
        bar = np.clip(np.stack([1 - bv - bw, bv, bw], 2), 0, None)
        bar /= np.maximum(bar.sum(2, keepdims=True), 1e-12)
        cp = bar[..., :1] * a + bar[..., 1:2] * b + bar[..., 2:] * c
        dist = np.linalg.norm(cp - p[:, None], axis=2) + 10.0 * ((nf * n[:, None]).sum(2) < 0)  # 뒷면(겹친 옷) 제외
        best = dist.argmin(1)
        r = np.arange(len(p))
        tuv = (bar[r, best][:, :, None] * uv[F[cand[r, best]]]).sum(1)
        x = np.clip(tuv[:, 0] * sw - 0.5, 0, sw - 1.001)
        y = np.clip(tuv[:, 1] * sh - 0.5, 0, sh - 1.001)
        xi, yi = x.astype(int), y.astype(int)
        fx, fy = (x - xi)[:, None], (y - yi)[:, None]
        col[s:s + 200000] = (src[yi, xi] * (1 - fx) * (1 - fy) + src[yi, xi + 1] * fx * (1 - fy)
                             + src[yi + 1, xi] * (1 - fx) * fy + src[yi + 1, xi + 1] * fx * fy)
    out = np.asarray(img.convert("RGB").resize((size, size), Image.LANCZOS), np.float32)
    covered = np.zeros((size, size), bool)
    out[pix[:, 1], pix[:, 0]] = col
    covered[pix[:, 1], pix[:, 0]] = True
    d, (iy, ix) = distance_transform_edt(~covered, return_indices=True)
    near = (d > 0) & (d <= 4)  # UV 섬 가장자리 4px 번짐(밉맵·이음매)
    out[near] = out[iy[near], ix[near]]
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)), float(covered.mean())


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
    info = {}
    if "--no-rebake" not in sys.argv:
        size = int(sys.argv[sys.argv.index("--tex") + 1]) if "--tex" in sys.argv else 2048
        im, cov = rebake(P, uv, idx, Image.open(io.BytesIO(tex)), Q, UV, N, I, size)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=92)
        tex, mime, info = buf.getvalue(), "image/jpeg", {"rebake": size, "uv_cover": round(cov, 3)}
    write(out, Q, UV, N, I, tex, mime)
    print(json.dumps({"out": out, "src_tris": len(idx) // 3, "tris": len(I) // 3, "verts": len(Q), **info}))


if __name__ == "__main__":
    main()
