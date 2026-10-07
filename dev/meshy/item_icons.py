"""장비 아이콘(2026-10-07 장비 디자인): Meshy 그림(nano-banana-pro, 4:3) 한 장 = 한 부위의 등급 6단계(3×2 칸, 위 줄 N·R·SR, 아래 줄 SSR·UR·LR)를
잘라 assets/ui/items/<부위>_<등급>.png (128×128, 투명 배경)로 만든다. scripts/icons.gd draw_item이 이 그림을 쓴다(없으면 벡터 그림).
실행: python3 -I dev/meshy/item_icons.py <부위> <그림.png> [<부위> <그림.png> ...]   (numpy·scipy·Pillow 필요)

자르기: 흰 배경을 가장자리에서 이어진 부분과 외곽선에 갇힌 흰 틈만 지운다(물체 위 흰 빛은 남는다) → 남은 덩어리를 무게중심으로 3×2 칸에
나눈다 → 칸마다 덩어리를 정사각 안 가운데(긴 변 = 92%)에 놓고 128 px로 줄인다. 외곽선 바깥 흰 번짐은 어두운 외곽선 색 + 반투명으로 바꾼다.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

GRADES = ["N", "R", "SR", "SSR", "UR", "LR"]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "ui", "items")
SIZE = 128
FILL = 0.92


def cut(path):
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float64)
    h, w, _ = rgb.shape
    lo = rgb.min(axis=2)
    hi = rgb.max(axis=2)
    whiteish = (lo >= 232) & (hi - lo <= 14)
    lab, _ = ndimage.label(whiteish)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(edge))
    # 갇힌 배경(석궁 활·시위 사이, 끈 고리 안): 둘레가 짙은 외곽선이거나, 아주 크고 새하얀 흰 덩어리. 물체 위 흰 빛(밝은 면에 둘러싸임)은 남긴다
    lum = rgb.mean(axis=2)
    for idx, sl in enumerate(ndimage.find_objects(lab), start=1):
        if idx in edge or sl is None:
            continue
        m = lab == idx
        area = m.sum()
        if area < 150:
            continue
        ring = ndimage.binary_dilation(m, iterations=4) & ~ndimage.binary_dilation(m, iterations=1)
        if lum[ring].mean() < 60 or (area >= 4000 and lo[m].mean() >= 253):
            bg |= m
    fg = ~bg
    # 번짐: 배경에서 2 px 안의 회색빛 점 → 흰색과 섞인 외곽선으로 보고 알파를 낮춘다
    near = fg & ndimage.binary_dilation(bg, iterations=2)
    alpha = fg.astype(np.float64)
    sat = hi - lo
    ink = np.array([34.0, 30.0, 38.0])
    soft = near & (sat < 40)
    a = np.clip((255.0 - lum) / (255.0 - ink.mean()), 0.0, 1.0)
    alpha[soft] = a[soft]
    rgb[soft] = ink
    # 덩어리 → 칸
    comp, n = ndimage.label(fg, structure=np.ones((3, 3)))
    cells = {i: np.zeros((h, w), bool) for i in range(6)}
    min_area = h * w * 0.0004
    for idx, sl in enumerate(ndimage.find_objects(comp), start=1):
        m = comp[sl] == idx
        if m.sum() < min_area:
            continue
        ys, xs = np.nonzero(m)
        cy = ys.mean() + sl[0].start
        cx = xs.mean() + sl[1].start
        cell = int(min(2, cx // (w / 3))) + 3 * int(min(1, cy // (h / 2)))
        cells[cell][sl] |= m
    out = []
    for i in range(6):
        m = cells[i]
        if not m.any():
            raise SystemExit("%s: %d번 칸이 비었다" % (path, i + 1))
        ys, xs = np.nonzero(m)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        side = int(max(y1 - y0, x1 - x0) / FILL)
        canvas = np.zeros((side, side, 4))
        oy = (side - (y1 - y0)) // 2
        ox = (side - (x1 - x0)) // 2
        a = alpha[y0:y1, x0:x1] * m[y0:y1, x0:x1]
        canvas[oy:oy + y1 - y0, ox:ox + x1 - x0, :3] = rgb[y0:y1, x0:x1] * a[..., None]  # 미리 곱한 알파로 줄인다(가장자리 번짐 없음)
        canvas[oy:oy + y1 - y0, ox:ox + x1 - x0, 3] = a * 255.0
        p = np.stack([np.asarray(Image.fromarray(canvas[..., c].astype(np.float32), "F").resize((SIZE, SIZE), Image.LANCZOS))
                      for c in range(4)], axis=-1).astype(np.float64)
        p[..., 3] = np.clip(p[..., 3], 0.0, 255.0)
        al = p[..., 3:4] / 255.0
        p[..., :3] = np.where(al > 0.004, p[..., :3] / np.maximum(al, 1e-6), 0.0)
        out.append(Image.fromarray(np.clip(p, 0, 255).astype(np.uint8), "RGBA"))
    return out


def main():
    args = sys.argv[1:]
    if not args or len(args) % 2:
        raise SystemExit(__doc__)
    os.makedirs(OUT, exist_ok=True)
    for kind, path in zip(args[::2], args[1::2]):
        for g, img in zip(GRADES, cut(path)):
            dst = os.path.join(OUT, "%s_%s.png" % (kind, g))
            img.save(dst, optimize=True)
        print(kind, "ok")


if __name__ == "__main__":
    main()
