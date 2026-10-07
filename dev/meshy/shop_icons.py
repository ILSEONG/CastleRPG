"""상점 아이콘(2026-10-07 디자인 보강 6번): Meshy 그림(nano-banana-pro, 4:3) 3장 = 3×2 칸 그림 18개를 잘라 assets/ui/shop/<이름>.png
(128×128, 투명 배경)로 만든다. 자르기는 장비 아이콘(item_icons.py cut)과 같다. scripts/shop_panel.gd draw_item_icon이 이 그림을 쓴다(없으면 벡터 그림).
실행: python3 -I dev/meshy/shop_icons.py <그림 폴더>   (diamonds_sheet.png·rewards_sheet.png·keys_sheet.png, numpy·scipy·Pillow 필요)
원본 그림과 프롬프트: /mnt/project-files/design/shop/
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "ui", "shop")
SHEETS = {  # 칸 순서: 위 줄 왼→오, 아래 줄 왼→오
    "diamonds": ["dia_1", "dia_2", "dia_3", "dia_4", "dia_5", "dia_6"],
    "rewards": ["gift", "gift_big", "crown", "ticket", "tickets", "chest_equip"],
    "keys": ["key_gold", "key_equip", "key_ticket", "pouch_gold", "pouch_res", "res_pile"],
}


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    spec = importlib.util.spec_from_file_location("item_icons", os.path.join(HERE, "item_icons.py"))
    item_icons = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(item_icons)
    os.makedirs(OUT, exist_ok=True)
    for sheet, names in SHEETS.items():
        for name, img in zip(names, item_icons.cut(os.path.join(sys.argv[1], sheet + "_sheet.png"))):
            img.save(os.path.join(OUT, name + ".png"), optimize=True)
        print(sheet, "ok")


if __name__ == "__main__":
    main()
