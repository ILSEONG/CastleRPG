#!/usr/bin/env python3
"""시작 화면 그림(assets/ui/splash.png) 만들기 — 앱 아이콘과 같은 느낌으로.

부트 스플래시(project.godot boot_splash), 로딩 화면(preloader.gd), 로그인 화면(login_screen.gd)이 같은 그림을 쓴다.
 - 배경: 아이콘처럼 삼각형으로 쪼갠 따뜻한 주황 하늘(위 진한 주황 → 아래 크림). 크게 그려 줄여 가장자리를 매끈하게.
 - 가운데: 아이콘의 성(잔디 섬·소나무). 아이콘 1024에서 오려 낸다 — 마스크는 적응형 전경(adaptive_fg_432)의 알파
   (같은 장면: 아이콘 = 전경 가운데 2/3를 1024로 늘린 것).
 - 위: 게임 이름 로고(흰 글자, 지붕 파랑 테두리·두께) + 부제 알약.
화면을 덮어 늘리므로(cover) 20:9 폰에서는 좌우가 잘린다 — 내용은 가운데 80% 안에 둔다.
사용: python3 dev/make_splash.py  (Pillow, numpy)
"""
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
W, H = 1080, 1920
SS = 2  # 배경 삼각형 슈퍼샘플링
TOP = np.array([247, 160, 66], float)  # 아이콘 위쪽 주황
BOTTOM = np.array([255, 232, 186], float)  # 아이콘 아래쪽 크림
TITLE = "CASTLE RPG"
SUBTITLE = "방치형 디펜스 RPG"
FONT = os.path.join(ROOT, "assets/fonts/Pretendard-SemiBold.otf")
BLUE = (64, 120, 205)  # 아이콘 지붕 파랑
BLUE_DARK = (36, 74, 138)  # 그보다 어두운(테두리·두께)


def sky_color(y: float) -> np.ndarray:
    t = min(1.0, max(0.0, y / H)) ** 0.9
    return TOP * (1 - t) + BOTTOM * t


def background(rng: random.Random) -> Image.Image:
    cols, rows = 6, 10
    cw, ch = W / cols, H / rows
    pts = {}
    for r in range(rows + 1):
        for c in range(cols + 1):
            x, y = c * cw, r * ch
            if 0 < c < cols:
                x += rng.uniform(-0.38, 0.38) * cw
            if 0 < r < rows:
                y += rng.uniform(-0.38, 0.38) * ch
            pts[(r, c)] = (x, y)
    img = Image.new("RGB", (W * SS, H * SS))
    d = ImageDraw.Draw(img)
    for r in range(rows):
        for c in range(cols):
            a, b, cc, dd = pts[(r, c)], pts[(r, c + 1)], pts[(r + 1, c + 1)], pts[(r + 1, c)]
            tris = [(a, b, cc), (a, cc, dd)] if rng.random() < 0.5 else [(a, b, dd), (b, cc, dd)]
            for tri in tris:
                cy = sum(p[1] for p in tri) / 3
                col = sky_color(cy) * rng.uniform(0.95, 1.04) + np.array([0, rng.uniform(-6, 6), 0])
                col = tuple(int(v) for v in np.clip(col, 0, 255))
                d.polygon([(p[0] * SS, p[1] * SS) for p in tri], fill=col)
    return img.resize((W, H), Image.LANCZOS)


def glow(img: Image.Image, cx: float, cy: float, r: float, strength: float) -> Image.Image:
    yy, xx = np.mgrid[0:H, 0:W]
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
    k = np.clip(1 - dist, 0, 1) ** 2 * strength
    a = np.array(img, float)
    a = a + (np.array([255, 250, 235], float) - a) * k[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def castle() -> Image.Image:
    icon = Image.open(os.path.join(ROOT, "assets/icon/icon_1024.png")).convert("RGB")
    fg = Image.open(os.path.join(ROOT, "assets/icon/adaptive_fg_432.png")).convert("RGBA")
    m = fg.getchannel("A").crop((72, 72, 360, 360)).resize((1024, 1024), Image.BICUBIC)
    m = m.point(lambda v: 0 if v < 40 else min(255, int((v - 40) * 255 / 160)))  # 테두리를 조금 조여 배경 번짐을 줄인다
    out = icon.convert("RGBA")
    out.putalpha(m)
    return out.crop(out.getbbox())


def text_layer(draw_fn) -> Image.Image:
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer))
    return layer


def main() -> None:
    rng = random.Random(7)
    img = background(rng)
    cs = castle()
    scale = 780 / cs.width
    cs = cs.resize((int(cs.width * scale), int(cs.height * scale)), Image.LANCZOS)
    cx, top = W // 2, 570
    img = glow(img, cx, top + cs.height * 0.5, 620, 0.55).convert("RGBA")
    # 섬 아래 부드러운 그림자
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse((cx - 330, top + cs.height - 80, cx + 330, top + cs.height + 20), fill=(150, 80, 20, 90))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(28)))
    img.alpha_composite(cs, (cx - cs.width // 2, top))

    # 로고: 아래로 두께(어두운 파랑) → 테두리 → 흰 글자, 뒤에 부드러운 그림자
    font = ImageFont.truetype(FONT, 128)
    ty = 230
    tw = font.getbbox(TITLE)[2]
    tx = (W - tw) // 2
    shadow = text_layer(lambda d: d.text((tx, ty + 26), TITLE, font=font, fill=(140, 70, 15, 110), stroke_width=16, stroke_fill=(140, 70, 15, 110)))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(10)))

    def logo(d):
        for dy in range(12, 0, -2):
            d.text((tx, ty + dy), TITLE, font=font, fill=BLUE_DARK, stroke_width=12, stroke_fill=BLUE_DARK)
        d.text((tx, ty), TITLE, font=font, fill=BLUE, stroke_width=12, stroke_fill=BLUE)
    img.alpha_composite(text_layer(logo))
    # 흰 글자(위는 흰색, 아래로 옅은 노랑)
    fill = text_layer(lambda d: d.text((tx, ty), TITLE, font=font, fill=(255, 255, 255, 255)))
    grad = Image.linear_gradient("L").resize((W, 130))
    ga = np.array(grad, float) / 255
    tint = np.zeros((H, W, 3))
    tint[:] = (255, 255, 255)
    band = np.array([255, 255, 255]) * (1 - ga[..., None]) + np.array([255, 236, 160]) * ga[..., None]
    tint[ty + 30:ty + 160] = band
    fa = np.array(fill)
    fa[..., :3] = tint.astype(np.uint8)
    img.alpha_composite(Image.fromarray(fa))

    # 부제 알약(따뜻한 갈색, 테두리는 같은 색의 어두운 쪽)
    sfont = ImageFont.truetype(FONT, 42)
    sb = sfont.getbbox(SUBTITLE)
    pw, ph = sb[2] + 72, 76
    px, py = (W - pw) // 2, ty + 205
    pill = text_layer(lambda d: (
        d.rounded_rectangle((px, py, px + pw, py + ph), radius=ph // 2, fill=(160, 82, 28, 225), outline=(118, 56, 16, 255), width=4),
        d.text((W // 2, py + ph // 2), SUBTITLE, font=sfont, fill=(255, 246, 225), anchor="mm"),
    ))
    img.alpha_composite(pill)

    out = os.path.join(ROOT, "assets/ui/splash.png")
    img.convert("RGB").save(out, optimize=True)
    print(out, os.path.getsize(out))


if __name__ == "__main__":
    main()
