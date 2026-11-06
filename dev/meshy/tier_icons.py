"""PVP 티어 문양(2026-11-05 "티어 문양이 너무 멋없어"): Meshy 그림(nano-banana-pro, 4:3) 한 장 = 위 4칸·아래 3칸, 브론즈→챌린저 순서.
흰 배경을 빼고(빛·무지개처럼 옅은 부분은 흰색과 섞인 만큼 반투명) assets/ui/pvp/tiers/<티어>.png(SIZE×SIZE)로 저장한다.
실행: python3 -I dev/meshy/tier_icons.py <시트.png> [미리보기.png]   (numpy·scipy·Pillow 필요)
원본 그림과 프롬프트: /mnt/project-files/design/pvp_tiers/
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ORDER = ["bronze", "silver", "gold", "platinum", "diamond", "master", "challenger"]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "ui", "pvp", "tiers")
SIZE = 192
FILL = 0.96


def unmix(rgb):
    """흰 배경 위 그림 → (색, 알파). 알파 = 흰색에서 가장 먼 채널, 가운데 단단한 몸통은 알파 1."""
    a = ((255.0 - rgb) / 255.0).max(axis=2)
    a = np.clip((a - 0.03) / 0.97, 0.0, 1.0)  # 종이 얼룩 같은 아주 옅은 회색은 버린다
    core = ndimage.binary_fill_holes(ndimage.binary_closing(a > 0.45, iterations=4))  # 짙은 테두리 안쪽(옅은 은빛 면 포함)은 단단하게
    a = np.where(core, 1.0, a)
    col = np.where(a[..., None] > 0.004, (rgb - 255.0 * (1.0 - a[..., None])) / np.maximum(a[..., None], 1e-6), 0.0)
    return np.clip(col, 0.0, 255.0), a


def cut(path):
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.float64)
    h, w, _ = rgb.shape
    col, alpha = unmix(rgb)
    # 덩어리 → 칸(위 줄 4칸, 아래 줄 3칸). 칸 경계를 넘는 날개도 무게중심으로 제 칸에 붙는다
    comp, n = ndimage.label(alpha > 0.06, structure=np.ones((3, 3)))
    masks = [np.zeros((h, w), bool) for _ in range(7)]
    for idx, sl in enumerate(ndimage.find_objects(comp), start=1):
        m = comp[sl] == idx
        if m.sum() < 12:
            continue
        ys, xs = np.nonzero(m)
        cy = ys.mean() + sl[0].start
        cx = xs.mean() + sl[1].start
        i = int(min(3, cx // (w / 4))) if cy < h / 2 else 4 + int(min(2, cx // (w / 3)))
        masks[i][sl] |= m
    res = []
    for m in masks:
        if not m.any():
            raise SystemExit("빈 칸")
        ys, xs = np.nonzero(m)
        by0, by1, bx0, bx1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        side = int(max(by1 - by0, bx1 - bx0) / FILL)
        canvas = np.zeros((side, side, 4))
        oy = (side - (by1 - by0)) // 2
        ox = (side - (bx1 - bx0)) // 2
        aa = alpha[by0:by1, bx0:bx1] * m[by0:by1, bx0:bx1]
        canvas[oy:oy + by1 - by0, ox:ox + bx1 - bx0, :3] = col[by0:by1, bx0:bx1] * aa[..., None]
        canvas[oy:oy + by1 - by0, ox:ox + bx1 - bx0, 3] = aa * 255.0
        p = np.stack([np.asarray(Image.fromarray(canvas[..., c].astype(np.float32), "F").resize((SIZE, SIZE), Image.LANCZOS))
                      for c in range(4)], axis=-1).astype(np.float64)
        p[..., 3] = np.clip(p[..., 3], 0.0, 255.0)
        al = p[..., 3:4] / 255.0
        p[..., :3] = np.where(al > 0.004, p[..., :3] / np.maximum(al, 1e-6), 0.0)
        res.append(Image.fromarray(np.clip(p, 0, 255).astype(np.uint8), "RGBA"))
    return res


def main():
    if len(sys.argv) not in (2, 3):
        raise SystemExit(__doc__)
    imgs = cut(sys.argv[1])
    os.makedirs(OUT, exist_ok=True)
    for name, img in zip(ORDER, imgs):
        img.save(os.path.join(OUT, name + ".png"), optimize=True)
    if len(sys.argv) == 3:  # 어두운 바탕·양피지 바탕 위 미리보기
        sheet = Image.new("RGBA", (SIZE * 7, SIZE * 2), (0, 0, 0, 255))
        sheet.paste(Image.new("RGBA", (SIZE * 7, SIZE), (32, 40, 64, 255)), (0, 0))
        sheet.paste(Image.new("RGBA", (SIZE * 7, SIZE), (236, 222, 190, 255)), (0, SIZE))
        for i, img in enumerate(imgs):
            sheet.alpha_composite(img, (i * SIZE, 0))
            sheet.alpha_composite(img, (i * SIZE, SIZE))
        sheet.convert("RGB").save(sys.argv[2])
    print("ok", len(imgs))


if __name__ == "__main__":
    main()
