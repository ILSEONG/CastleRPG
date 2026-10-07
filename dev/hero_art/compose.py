"""영웅 일러스트 합성(2026-10-07, 크레딧 없이): tests/hero_art_render.tscn이 찍은 3D 발동 자세(투명 PNG + faces.json)를
영웅 고유 색의 밤하늘·달·성 실루엣·각진 에너지 조각·빛 띠·불씨 위에 올리고, 몸에 고유 색 역광 테두리와 빛 번짐을 더해
assets/ui/heroes/<id>.jpg(640 px)로 저장한다. 같은 영웅은 늘 같은 그림(id 해시 시드).
실행: python3 -I dev/hero_art/compose.py <렌더 폴더> [<출력 폴더>] [id ...]   (numpy·Pillow)
"""
import csv
import json
import math
import os
import random
import sys
import zlib

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
W = 1024
OUT_PX = 640
FACE = (0.5, 0.3)  # 완성 그림에서 얼굴이 올 자리
ZOOM = 1.15  # 렌더를 키우는 배율(무릎 위가 화면을 채운다)


def hexcol(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def heroes():
    with open(os.path.join(ROOT, "data", "heroes.csv"), encoding="utf-8") as f:
        return {r["id"]: r for r in csv.DictReader(f)}


def glow(mask, radius, color, strength=1.0):
    """마스크(L)를 번지게 해 color 빛 층(RGBA)."""
    g = mask.filter(ImageFilter.GaussianBlur(radius))
    a = np.asarray(g, dtype=np.float32) * strength
    layer = np.zeros((mask.size[1], mask.size[0], 4), dtype=np.uint8)
    layer[..., :3] = color
    layer[..., 3] = np.clip(a, 0, 255).astype(np.uint8)
    return Image.fromarray(layer, "RGBA")


def add(base, layer):
    """가산 혼합(빛)."""
    rgb = np.asarray(base.convert("RGB"), dtype=np.float32)
    l = np.asarray(layer, dtype=np.float32)
    rgb += l[..., :3] * (l[..., 3:4] / 255.0)
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")


def background(rng, c):
    dark = mix(c, (12, 10, 26), 0.82)
    top = mix(c, (30, 26, 60), 0.55)
    y = np.linspace(0, 1, W)[:, None]
    grad = np.array(top)[None, None, :] * (1 - y[..., None]) + np.array(dark)[None, None, :] * y[..., None]
    img = Image.fromarray(np.repeat(grad, W, axis=1).astype(np.uint8), "RGB")
    # 구름: 굵은 잡음을 번지게
    noise = Image.fromarray((np.array([[rng.random() for _ in range(16)] for _ in range(16)]) * 255).astype(np.uint8), "L")
    cloud = noise.resize((W, W), Image.BICUBIC).filter(ImageFilter.GaussianBlur(30))
    img = add(img, glow(cloud, 2, mix(c, (200, 200, 230), 0.4), 0.28))
    # 달
    mx, my, mr = rng.choice([0.78, 0.22]) * W, 0.17 * W, 0.13 * W
    moon = Image.new("L", (W, W), 0)
    ImageDraw.Draw(moon).ellipse((mx - mr, my - mr, mx + mr, my + mr), fill=255)
    img = add(img, glow(moon, 60, mix(c, (255, 255, 255), 0.5), 0.9))
    md = ImageDraw.Draw(img)
    md.ellipse((mx - mr, my - mr, mx + mr, my + mr), fill=mix(c, (235, 232, 245), 0.78))
    for _ in range(4):  # 달 얼룩(흐리게)
        a, d, r = rng.random() * 6.28, rng.random() * mr * 0.5, mr * (0.15 + rng.random() * 0.2)
        x, y2 = mx + math.cos(a) * d, my + math.sin(a) * d
        spot = Image.new("L", (W, W), 0)
        ImageDraw.Draw(spot).ellipse((x - r, y2 - r, x + r, y2 + r), fill=40)
        img = Image.composite(Image.new("RGB", (W, W), mix(c, (120, 115, 140), 0.6)), img, spot.filter(ImageFilter.GaussianBlur(r * 0.4)))
    # 성 실루엣(달 쪽)
    sil = mix(c, (8, 6, 18), 0.88)
    side = 1 if mx > W / 2 else -1
    base_x = W * (0.62 if side > 0 else 0.0)
    d2 = ImageDraw.Draw(img)
    x = base_x
    while x < base_x + W * 0.4:
        tw = rng.uniform(40, 90)
        th = rng.uniform(0.25, 0.55) * W
        y0 = W - th
        d2.rectangle((x, y0, x + tw, W), fill=sil)
        d2.polygon([(x - 8, y0), (x + tw / 2, y0 - tw * rng.uniform(0.9, 1.6)), (x + tw + 8, y0)], fill=sil)
        for k in range(int(th // 70)):
            if rng.random() < 0.5:
                wy = y0 + 30 + k * 70
                d2.rectangle((x + tw / 2 - 4, wy, x + tw / 2 + 4, wy + 14), fill=(255, 200, 120))
        x += tw + rng.uniform(-10, 30)
    return img


def shards(rng, c, n, alpha, scale):
    """각진 에너지 조각(참조 그림의 보라 조각처럼): 길쭉한 삼각·사각, 고유 색, 대각선 흐름."""
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ang = rng.choice([-0.5, 0.5]) + math.pi
    for _ in range(n):
        cx, cy = rng.random() * W, rng.random() * W
        L = rng.uniform(40, 160) * scale
        t = rng.uniform(6, 22) * scale
        a = ang + rng.uniform(-0.35, 0.35)
        ux, uy = math.cos(a), math.sin(a)
        px, py = -uy, ux
        pts = [(cx + ux * L, cy + uy * L), (cx + px * t, cy + py * t), (cx - ux * L * 0.4, cy - uy * L * 0.4), (cx - px * t * 0.6, cy - py * t * 0.6)]
        col = mix(c, (255, 255, 255), rng.uniform(0.0, 0.45)) if rng.random() < 0.7 else mix(c, (0, 0, 0), 0.6)
        d.polygon(pts, fill=col + (int(alpha * rng.uniform(0.5, 1.0)),))
    return layer


def ribbons(rng, c, cx, cy, n):
    """캐릭터를 감는 빛 띠(굵기가 변하는 호) — 마스크(L)."""
    m = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(m)
    for i in range(n):
        r = rng.uniform(0.28, 0.45) * W
        a0 = rng.uniform(0, 6.28)
        span = rng.uniform(1.6, 3.0)
        tilt = rng.uniform(0.35, 0.6)
        steps = 240
        for s in range(steps):
            t = s / steps
            a = a0 + span * t
            x = cx + math.cos(a) * r
            y = cy + math.sin(a) * r * tilt + (t - 0.5) * 120
            w = 2 + 10 * math.sin(t * math.pi)
            d.ellipse((x - w, y - w, x + w, y + w), fill=255)
    return m


def embers(rng, c, n):
    m = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(m)
    for _ in range(n):
        x, y, r = rng.random() * W, rng.random() * W, rng.uniform(1.5, 5)
        d.ellipse((x - r, y - r, x + r, y + r), fill=int(rng.uniform(120, 255)))
    return m


def compose(render, face, hero, out):
    rng = random.Random(zlib.crc32(hero["id"].encode()))
    c = hexcol(hero["color"])
    light = mix(c, (255, 255, 255), 0.45)
    img = background(rng, c)
    img = add(img, shards(rng, c, 26, 120, 1.0).filter(ImageFilter.GaussianBlur(3)))
    # 캐릭터: 키워서 얼굴을 FACE에
    ch = Image.open(render).convert("RGBA")
    size = int(W * ZOOM)
    ch = ch.resize((size, size), Image.LANCZOS)
    ox = int(FACE[0] * W - face["x"] * size)
    oy = int(FACE[1] * W - face["y"] * size)
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    layer.paste(ch, (ox, oy), ch)
    alpha = layer.split()[3]
    # 몸 뒤 빛 번짐 + 빛 띠(뒤)
    img = add(img, glow(alpha.filter(ImageFilter.MaxFilter(15)), 40, light, 0.85))
    rib = ribbons(rng, c, FACE[0] * W, FACE[1] * W + 0.25 * W, 3)
    img = add(img, glow(rib, 10, c, 1.0))
    img = add(img, glow(rib, 1, light, 0.9))
    # 땅: 어두운 돌 턱
    d = ImageDraw.Draw(img)
    gy = W * 0.88
    d.polygon([(0, gy + 20), (W * 0.35, gy - 10), (W * 0.7, gy + 5), (W, gy - 15), (W, W), (0, W)], fill=mix(c, (10, 8, 16), 0.85))
    for k in range(9):
        x = k * W / 8 + rng.uniform(-20, 20)
        d.line((x, gy + 10, x + rng.uniform(-30, 30), W), fill=mix(c, (25, 20, 35), 0.8), width=3)
    # 캐릭터: 약간 대비를 올리고 역광 테두리(왼쪽·오른쪽 가장자리)
    rgb = np.asarray(layer, dtype=np.float32)
    col = rgb[..., :3]
    lum = col.mean(axis=2, keepdims=True)
    col = np.clip(lum + (col - lum) * 1.25, 0, 255)  # 채도
    col = np.clip((col - 128) * 1.15 + 128 - 18, 0, 255)  # 대비, 조금 어둡게
    ys = (np.arange(W)[:, None, None] / W)
    tint = np.array(c, dtype=np.float32)[None, None, :]
    shade = np.clip((ys - 0.45) / 0.5, 0, 1) * 0.45  # 아래로 갈수록 어둡고 고유 색 아래 빛
    col = col * (1 - shade) + col * tint / 255.0 * shade * 1.2
    a = rgb[..., 3:4] / 255.0
    base = np.asarray(img, dtype=np.float32)
    base = base * (1 - a) + col * a
    img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB")
    for dx in (-7, 7):
        shifted = ImageChops.offset(alpha, dx, 3)
        edge = ImageChops.subtract(alpha, shifted)
        img = add(img, glow(edge, 2, light, 1.0))
    # 앞쪽: 빛 띠 일부, 조각, 불씨
    front = ribbons(rng, c, FACE[0] * W, FACE[1] * W + 0.32 * W, 1)
    img = add(img, glow(front, 8, c, 0.9))
    img = add(img, glow(front, 1, light, 0.8))
    fs = shards(rng, c, 10, 170, 1.2)
    img = Image.alpha_composite(img.convert("RGBA"), fs).convert("RGB")
    em = embers(rng, c, 70)
    img = add(img, glow(em, 4, c, 1.6))
    img = add(img, glow(em, 0, light, 1.0))
    # 비네트·마무리
    yy, xx = np.mgrid[0:W, 0:W] / W
    v = 1 - 0.55 * np.clip(((xx - 0.5) ** 2 + (yy - 0.42) ** 2) * 2.2, 0, 1)
    arr = np.asarray(img, dtype=np.float32) * v[..., None]
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")
    img = img.filter(ImageFilter.UnsharpMask(2, 60, 2))
    img.resize((OUT_PX, OUT_PX), Image.LANCZOS).save(out, quality=90, optimize=True)


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "assets", "ui", "heroes")
    os.makedirs(dst, exist_ok=True)
    faces = json.load(open(os.path.join(src, "faces.json")))
    hs = heroes()
    ids = sys.argv[3:] or list(faces)
    for i in ids:
        compose(os.path.join(src, i + ".png"), faces[i], hs[i], os.path.join(dst, i + ".jpg"))
        print(i, "ok")


if __name__ == "__main__":
    main()
