"""MR(신화, 2026-10-29) 장비 그림: 같은 부위 LR 그림(assets/ui/items/<kind>_LR.png)을 검붉게 다시 칠한다.
밝기는 그대로 두고 색만 핏빛(어두운 곳) → 진홍(밝은 곳)으로 바꾼다 — LR 무지개 금과 구분되고 금빛 장식이 남지 않는다. 투명도는 그대로.
실행: python3 dev/meshy/item_icons_mr.py (PIL 필요). 결과 assets/ui/items/<kind>_MR.png(128 px).
"""
import glob
import os

from PIL import Image

DIR = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "ui", "items")
DARK = (22, 0, 4)
MID = (105, 6, 18)
LIGHT = (235, 72, 82)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def recolor(src: str, dst: str) -> None:
    img = Image.open(src).convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            c = lerp(DARK, MID, lum / 0.6) if lum < 0.6 else lerp(MID, LIGHT, ((lum - 0.6) / 0.4) ** 1.4)
            px[x, y] = (*c, a)
    img.save(dst)


for src in sorted(glob.glob(os.path.join(DIR, "*_LR.png"))):
    recolor(src, src[: -len("_LR.png")] + "_MR.png")
    print(os.path.basename(src)[: -len("_LR.png")] + "_MR.png")
