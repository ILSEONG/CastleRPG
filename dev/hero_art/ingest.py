"""영웅 일러스트 넣기(2026-10-07): 사용자가 ChatGPT로 만든 그림(아무 비율)을 가운데 정사각으로 잘라 640 px JPEG(품질 90)로
assets/ui/heroes/<id>.jpg에 두고, 손실 압축 임포트 설정(.import)을 만든다. 얼굴 위치는 scripts/hero_art.gd FOCUS에 따로 적는다.
실행: python3 -I dev/hero_art/ingest.py <id> <그림> [<id> <그림> ...]   (Pillow)
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "ui", "heroes")
PX = 640
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=1
compress/high_quality=false
compress/lossy_quality=0.85
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""


def ingest(hero_id, path):
    im = Image.open(path).convert("RGB")
    s = min(im.size)
    x, y = (im.width - s) // 2, 0 if im.height > im.width else (im.height - s) // 2  # 세로로 길면 위를 남긴다(얼굴)
    im = im.crop((x, y, x + s, y + s)).resize((PX, PX), Image.LANCZOS)
    out = os.path.join(OUT, hero_id + ".jpg")
    im.save(out, quality=90, optimize=True)
    if not os.path.exists(out + ".import"):
        with open(out + ".import", "w") as f:
            f.write(IMPORT)
    print(hero_id, "ok")


def main():
    args = sys.argv[1:]
    if not args or len(args) % 2:
        raise SystemExit(__doc__)
    os.makedirs(OUT, exist_ok=True)
    for i in range(0, len(args), 2):
        ingest(args[i], args[i + 1])


if __name__ == "__main__":
    main()
