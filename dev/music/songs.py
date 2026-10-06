"""CastleRPG 배경음악 10곡 — 모두 이 저장소에서 새로 작곡한 곡(멜로디·화성·편곡). engine.py가 렌더링한다.
실행: python3 dev/music/songs.py [곡이름 ...]  → assets/audio/music/<곡>.ogg (+ 미리듣기 MP3는 PREVIEW_DIR가 있으면)

GM 악기 번호(0부터): 8 첼레스타 9 글로켄슈필 13 실로폰 14 튜블러벨 19 교회 오르간 32 어쿠스틱 베이스 33 핑거 베이스
40 바이올린 42 첼로 43 콘트라베이스 44 트레몰로 현 45 피치카토 46 하프 47 팀파니 48·49 현악 합주 52 합창 아 53 보이스 우
56 트럼펫 57 트롬본 58 튜바 60 호른 61 브라스 섹션 68 오보에 70 바순 71 클라리넷 73 플루트 75 팬플루트 108 칼림바 116 타이코
"""
import os
import sys

from engine import Song, low_note

KICK, SNARE, RIM, CHH, PHH, OHH, CRASH, RIDE, TAMB, TRI = 36, 38, 37, 42, 44, 46, 49, 51, 54, 81
TOM_L, TOM_M, TOM_H, FLOOR = 45, 47, 50, 41
WOOD_H, WOOD_L, SHAKER = 76, 77, 70


def title():
    """타이틀·로딩 — '성의 서막'. D장조, 느긋하고 웅장하게. 호른이 주제를 부르고 바이올린이 이어받는다."""
    s = Song("title", 84, 16, seed=11)
    s.set_chords("| D | A/C# | Bm | G | D | A | G | A | Bm | G | D | A | G | A/C# | D | Asus4 A |")
    s.part("strings", 49, vol=88, pan=58, rev=80)
    s.part("harp", 46, vol=84, pan=78, rev=70)
    s.part("horn", 60, vol=104, pan=50, rev=70)
    s.part("violin", 48, vol=100, pan=70, rev=75)
    s.part("bass", 43, vol=92, pan=64, rev=50)
    s.part("timp", 47, vol=90, pan=64, rev=60)
    s.part("bells", 9, vol=62, pan=84, rev=90)
    s.pad("strings", center=62, voices=4, vel=64)
    s.arp("harp", [0, 1, 2, 3, 4, 3, 2, 1], step=0.5, low=50, vel=62)
    s.bass("bass", [(0, 2, "R"), (2, 2, "R")], octave=38, vel=78)
    s.melody("horn", "F#4:1.5 A4:.5 D5:2 C#5:1 B4:.5 A4:.5 E4:2 F#4:1.5 B4:.5 D5:1 C#5:1 B4:3 A4:1 "
                     "F#4:1.5 A4:.5 D5:1.5 E5:.5 F#5:1 E5:1 C#5:2 D5:1 B4:1 G5:1.5 F#5:.5 E5:4", bar=0, vel=88)
    mel2 = ("F#5:1.5 E5:.5 D5:1 B4:1 D5:1.5 C#5:.5 B4:2 A4:1 D5:1 F#5:1 A5:1 G5:1.5 F#5:.5 E5:2 "
            "B5:1.5 A5:.5 G5:1 F#5:1 E5:1 F#5:.5 G5:.5 A5:2 F#5:1.5 E5:.5 D5:2 E5:2 r:2")
    s.melody("violin", mel2, bar=8, vel=90)
    s.melody("horn", mel2, bar=8, transpose=-12, vel=70)
    for b in (0, 4, 8, 12):
        s.note("timp", b * 4, 1, 38 if b % 8 == 0 else 45, 84)
    for b in (7, 15):
        s.roll("timp", 45, b * 4 + 2, 2, 40, 96)
    s.melody("bells", "D6:2 r:14 A5:2 r:14", bar=8, vel=60)
    return s


def idle():
    """방치 모드 — '성 아래 마을'. G장조 3/4 왈츠. 피치카토 쿵짝짝 위에 플루트, 후반은 클라리넷·글로켄."""
    s = Song("idle", 104, 24, beats=3, seed=12)
    s.set_chords("| G | D/F# | Em | C | G | Am | D | D7 | G | D/F# | Em | C | Am | D | G | G |"
                 " C | D | Bm | Em | Am | D | G | D7 |")
    s.part("pizz_bass", 45, vol=96, pan=56, rev=40)
    s.part("pizz", 45, vol=82, pan=74, rev=45)
    s.part("pad", 49, vol=60, pan=64, rev=80)
    s.part("flute", 73, vol=100, pan=60, rev=60)
    s.part("clar", 71, vol=86, pan=44, rev=60)
    s.part("harp", 46, vol=74, pan=86, rev=70)
    s.part("glock", 9, vol=58, pan=80, rev=80)
    s.part("perc", 0, vol=70, drum=True, rev=50)
    s.bass("pizz_bass", [(0, 1, "R")], octave=43, vel=84)
    s.pad("pizz", center=64, voices=3, vel=58, rhythm=[(1, 0.5), (2, 0.5)])
    s.pad("pad", center=60, voices=3, vel=46)
    mel = ("D5:2 B4:1 A4:2 F#4:1 G4:1 B4:1 E5:1 E5:2 D5:1 D5:1 B4:1 G4:1 C5:2 E5:1 D5:1.5 C5:.5 A4:1 A4:2 r:1 "
           "D5:2 G5:1 F#5:2 D5:1 E5:1 G5:1 B5:1 A5:2 G5:1 E5:1 C5:1 A4:1 F#4:1 A4:1 D5:1 B4:2 A4:1 G4:3 "
           "E5:1 G5:1 E5:1 F#5:2 D5:1 D5:1 F#5:1 B5:1 G5:2 E5:1 C5:1 E5:1 A5:1 G5:1 F#5:1 E5:1 D5:2 B4:1 C5:1 A4:1 F#4:1")
    s.melody("flute", mel, vel=86)
    s.melody("clar", "B4:2 G4:1 F#4:2 D4:1 E4:3 G4:3 C5:3 A4:3 G4:3 D4:3 "
                     "G4:3 A4:3 F#4:3 E4:3 E4:3 F#4:3 D4:3 C5:3", bar=8, vel=70, legato=1.0)
    s.arp("harp", [0, 2, 4, 5, 4, 2], step=0.5, low=55, vel=56, bars=range(16, 24))
    s.melody("glock", "r:3 " * 16 + "E6:1 r:2 F#6:1 r:2 D6:1 r:2 B5:1 r:2 C6:1 r:2 A5:1 r:2 B5:1 r:2 A5:1 r:2", vel=52)
    s.drums("perc", {TRI: "x...........", SHAKER: "..-.-.-.-.-."}, bars=range(8, 24), step=0.25)
    return s


def fever():
    """FEVER — '피버 타임'. F장조 150BPM, 트럼펫+실로폰 주제, 브라스 스탭, 4비트 드럼."""
    s = Song("fever", 150, 16, seed=13)
    s.set_chords("| F | C | Dm | Bb | F | C | Bb | C | Dm | Bb | F | C | Dm | Bb | Gm7 | C7 |")
    s.part("bass", 33, vol=100, pan=64, rev=20)
    s.part("strings", 48, vol=80, pan=40, rev=50)
    s.part("brass", 61, vol=92, pan=84, rev=40)
    s.part("tpt", 56, vol=104, pan=58, rev=45)
    s.part("xylo", 13, vol=78, pan=76, rev=50)
    s.part("drums", 0, vol=100, drum=True, rev=30)
    s.bass("bass", [(0, .5, "r"), (.5, .5, "8"), (1, .5, "r"), (1.5, .5, "8"), (2, .5, "r"), (2.5, .5, "8"), (3, .5, "5"), (3.5, .5, "8")],
           octave=34, vel=88, legato=0.8)
    s.arp("strings", [0, 1, 2, 1], step=0.25, low=60, vel=56, legato=0.7, accent=8)
    s.pad("brass", center=65, voices=3, vel=80, rhythm=[(0, .4), (1.5, .4), (2.5, .4)], legato=1.0)
    mel = ("C5:.5 F5:.5 A5:1 G5:.5 F5:.5 C5:1 E5:.5 G5:.5 C6:1 Bb5:.5 G5:.5 E5:1 F5:.5 A5:.5 D6:1 C6:.5 A5:.5 F5:1 "
           "D5:1 F5:1 Bb5:1.5 A5:.5 A5:1.5 G5:.5 F5:1 C5:1 E5:1 G5:1 C6:2 D6:.5 C6:.5 Bb5:1 F5:1 D5:1 E5:1 F5:.5 G5:.5 C5:2 "
           "A5:1.5 F5:.5 D5:1 A5:1 Bb5:1.5 A5:.5 F5:2 C6:1 A5:1 F5:1 A5:1 G5:3 r:1 "
           "D6:.5 C6:.5 A5:1 D6:.5 C6:.5 A5:1 D6:1 Bb5:1 F5:2 G5:.5 A5:.5 Bb5:.5 C6:.5 D6:1 Bb5:1 C6:2 Bb5:.5 G5:.5 E5:1")
    s.melody("tpt", mel, vel=92, legato=0.85)
    s.melody("xylo", mel, transpose=12, vel=70, legato=0.5)
    s.drums("drums", {KICK: "x...x...x...x...", SNARE: "....x.......x...", CHH: "-.o.-.o.-.o.-.o.", TAMB: "..-...-...-...-."})
    s.drums("drums", {CRASH: "x..............."}, bars=[0, 8])
    s.drums("drums", {SNARE: "....x.......x.oo", TOM_H: "..........x.....", TOM_M: "...........x...."}, bars=[7, 15])
    return s


def stage():
    """스테이지(라운드 전투) — '성벽 방어전'. A단조 132BPM. 현 8분 오스티나토, 호른 주제, 팀파니·스네어."""
    s = Song("stage", 132, 24, seed=14)
    s.set_chords("| Am | F | G | Am | Am | F | G | E | F | G | Em | Am | F | G | E | E |"
                 " Dm | Am | Dm | E | F | G | Am | E |")
    s.part("cello", 42, vol=96, pan=52, rev=40)
    s.part("bass", 43, vol=96, pan=64, rev=40)
    s.part("strings", 48, vol=82, pan=76, rev=60)
    s.part("horn", 60, vol=106, pan=50, rev=60)
    s.part("tbn", 57, vol=88, pan=70, rev=50)
    s.part("timp", 47, vol=96, pan=64, rev=50)
    s.part("drums", 0, vol=96, drum=True, rev=40)
    s.arp("cello", [0, 0, 2, 0, 1, 0, 2, 1], step=0.5, low=45, vel=74, span=1, legato=0.6, accent=12)
    s.bass("bass", [(0, .5, "r"), (.5, .5, "r"), (1.5, .5, "r"), (2, .5, "r"), (3, .5, "5"), (3.5, .5, "r")], octave=33, vel=82, legato=0.6)
    s.pad("strings", center=67, voices=4, vel=58)
    s.pad("tbn", center=55, voices=3, vel=78, rhythm=[(0, 1.5), (2.5, 1.5)], bars=range(8, 24))
    mel = ("A4:1.5 B4:.5 C5:1 E5:1 F5:1.5 E5:.5 C5:2 D5:1.5 C5:.5 B4:1 G4:1 A4:3 r:1 "
           "A4:1.5 B4:.5 C5:1 E5:1 A5:1.5 G5:.5 F5:1 C5:1 B4:1 D5:1 G5:1 F5:1 E5:3 G#4:1 "
           "A4:1 C5:1 F5:2 G5:1 F5:.5 E5:.5 D5:2 E5:1 G5:1 B5:2 A5:1.5 G5:.5 E5:2 "
           "F5:1 A5:1 C6:1.5 B5:.5 B5:1 G5:1 D5:2 E5:1 F5:.5 E5:.5 D5:1 B4:1 G#4:2 B4:2 "
           "D5:1.5 E5:.5 F5:1 A5:1 E5:2 C5:1 A4:1 F5:1.5 G5:.5 A5:1 D6:1 B5:2 G#5:2 "
           "A5:1.5 G5:.5 F5:1 E5:1 D5:1.5 E5:.5 F5:1 G5:1 E5:1 C5:1 A4:2 B4:1 C5:.5 B4:.5 G#4:2")
    s.melody("horn", mel, vel=90, legato=0.9)
    for b in range(24):
        r = s.chord_at(b * 4)[0]
        s.note("timp", b * 4, 1, low_note(r, 38), 92)
        s.note("timp", b * 4 + 2.5, .5, low_note(r, 38), 70)
    s.drums("drums", {KICK: "x.....x.x.......", CHH: "o.-.o.-.o.-.o.-."}, bars=range(0, 8))
    s.drums("drums", {KICK: "x.....x.x.....x.", SNARE: "....x.......x...", CHH: "o.-.o.-.o.-.o.-."}, bars=range(8, 24))
    s.drums("drums", {CRASH: "x..............."}, bars=[8, 16])
    for b in (7, 15, 23):
        s.drums("drums", {SNARE: "........x.o.x.xx", TOM_H: "..........x.....", FLOOR: "..............x."}, bars=[b])
    return s


def boss():
    """보스 라운드(라운드 25) — '성문 앞의 거인'. D단조 144BPM. 저음 리프, 합창, 브라스 주제, 팀파니·타이코."""
    s = Song("boss", 144, 24, seed=15)
    s.set_chords("| Dm | Dm | Bb | A | Dm | Dm | Gm | A | Bb | C | Dm | Dm | Bb | Gm | Eb | A |"
                 " Gm | Dm | Gm | A | Bb | Gm | Eb | A |")
    s.part("low", 57, vol=96, pan=60, rev=40)
    s.part("cello", 42, vol=96, pan=50, rev=40)
    s.part("trem", 44, vol=80, pan=80, rev=60)
    s.part("choir", 52, vol=88, pan=64, rev=90)
    s.part("brass", 61, vol=108, pan=56, rev=60)
    s.part("timp", 47, vol=100, pan=64, rev=50)
    s.part("taiko", 116, vol=96, pan=64, rev=50)
    s.part("drums", 0, vol=92, drum=True, rev=40)
    riff = [(0, .5, "r"), (.5, .5, "r"), (1, .5, "8"), (1.5, .5, "r"), (2, .5, "5"), (2.5, .5, "r"), (3, .5, "8"), (3.5, .5, "5")]
    s.bass("cello", riff, octave=38, vel=82, legato=0.7)
    s.bass("low", riff, octave=26, vel=80, legato=0.6, bars=range(4, 24))
    s.pad("trem", center=65, voices=4, vel=62, bars=range(4, 24))
    s.pad("choir", center=62, voices=4, vel=76)
    mel = ("D5:2 F5:1 E5:1 D5:1 A4:1 D5:2 G5:1.5 F5:.5 E5:1 D5:1 E5:2 C#5:2 "
           "F5:2 D5:1 Bb4:1 C5:1 E5:1 G5:2 A5:2 F5:1 D5:1 E5:1 F5:1 A5:2 "
           "D6:2 Bb5:1 F5:1 G5:1 Bb5:1 D6:2 Eb6:1.5 D6:.5 Bb5:1 G5:1 A5:2 G5:1 E5:1 "
           "D5:1 G5:1 Bb5:2 A5:2 F5:2 G5:1.5 A5:.5 Bb5:1 D6:1 C#6:2 A5:2 "
           "D6:1.5 C6:.5 Bb5:1 F5:1 G5:1 F5:1 D5:2 Eb5:1 G5:1 Bb5:1 G5:1 A5:2 C#5:1 E5:1")
    s.melody("brass", mel, bar=4, vel=94, legato=0.9)
    for b in range(24):
        r = s.chord_at(b * 4)[0]
        tp = low_note(r, 38)
        s.note("timp", b * 4, 1, tp, 100)
        s.note("timp", b * 4 + 2, 1, tp, 80)
        s.note("taiko", b * 4 + 1.5, .5, 48, 80)
        s.note("taiko", b * 4 + 3, .5, 48, 96)
        s.note("taiko", b * 4 + 3.5, .5, 48, 70)
    s.drums("drums", {KICK: "x.......x.x.....", SNARE: "....x.......x..."}, bars=range(4, 24))
    s.drums("drums", {CRASH: "x..............."}, bars=[4, 12, 16])
    s.roll("timp", 45, 3 * 4, 4, 40, 110)
    for b in (11, 15, 23):
        s.drums("drums", {SNARE: "........x.x.xxxx", TOM_M: "............x...", FLOOR: "..............x."}, bars=[b])
    return s


def dungeon_gold():
    """골드 던전(고블린 들판) — '고블린 들판'. C장조 120BPM, 통통 튀는 클라리넷·바순·피치카토, 실로폰 대답, 우드블록."""
    s = Song("dungeon_gold", 120, 24, seed=16)
    s.set_chords("| C | C | F | G | C | Am | D7 | G | Am | Em | F | C | Dm | G | E7 | Am |"
                 " F | G | Em | Am | Dm | G | C | G7 |")
    s.part("bassoon", 70, vol=96, pan=50, rev=40)
    s.part("pizz", 45, vol=84, pan=78, rev=45)
    s.part("clar", 71, vol=104, pan=58, rev=50)
    s.part("xylo", 13, vol=84, pan=82, rev=50)
    s.part("strings", 48, vol=62, pan=40, rev=70)
    s.part("perc", 0, vol=88, drum=True, rev=40)
    s.bass("bassoon", [(0, .5, "R"), (1, .5, "5"), (2, .5, "R"), (3, .5, "5")], octave=36, vel=86, legato=0.7)
    s.pad("pizz", center=64, voices=3, vel=62, rhythm=[(.5, .25), (1.5, .25), (2.5, .25), (3.5, .25)])
    s.pad("strings", center=60, voices=3, vel=48, bars=range(8, 24))
    mel = ("G4:.5 C5:.5 E5:.5 G5:.5 E5:1 C5:1 D5:.5 E5:.5 D5:.5 C5:.5 G4:2 A4:.5 C5:.5 F5:.5 A5:.5 G5:1 F5:1 "
           "E5:.5 F5:.5 E5:.5 D5:.5 B4:2 G4:.5 C5:.5 E5:.5 G5:.5 C6:1 G5:1 A5:1 E5:.5 C5:.5 A4:2 "
           "F#5:.5 A5:.5 F#5:.5 D5:.5 C5:1 A4:1 B4:.5 D5:.5 G5:1 r:2 "
           "E5:1 A5:1 G5:.5 F5:.5 E5:1 D5:.5 E5:.5 B4:1 G4:2 C5:1 F5:1 E5:.5 D5:.5 C5:1 E5:1.5 D5:.5 C5:2 "
           "D5:.5 F5:.5 A5:.5 F5:.5 D5:1 A4:1 B4:.5 D5:.5 G5:.5 F5:.5 D5:2 G#4:.5 B4:.5 D5:.5 E5:.5 G#5:1 E5:1 A5:2 r:2 "
           "A5:.5 G5:.5 F5:.5 E5:.5 F5:1 C5:1 D5:.5 E5:.5 F5:.5 G5:.5 B4:2 G5:.5 F#5:.5 E5:.5 D5:.5 E5:1 B4:1 "
           "C5:.5 D5:.5 E5:.5 A5:.5 E5:2 F5:1 A5:1 D6:1 A5:1 G5:1 F5:.5 E5:.5 D5:2 "
           "E5:.5 G5:.5 C6:1 G5:1 E5:1 F5:.5 E5:.5 D5:.5 B4:.5 G4:2")
    s.melody("clar", mel, vel=88, legato=0.6)
    s.arp("xylo", [None, None, None, None, None, 5, 4, 2], step=0.5, low=67, vel=74, bars=range(1, 24, 2), legato=0.5, accent=0)
    s.drums("perc", {WOOD_H: "x...-...x...-.-.", WOOD_L: "..x.......x.....", SHAKER: "-.-.-.-.-.-.-.-."})
    s.drums("perc", {KICK: "x.......x.......", TAMB: "....x.......x..."}, bars=range(8, 24))
    return s


def dungeon_equip():
    """장비 던전(죽음의 기사, 폐허 성) — '망자의 성채'. C단조 92BPM. 첼로 8분, 합창 우, 오르간, 오보에 주제, 종소리."""
    s = Song("dungeon_equip", 92, 16, seed=17)
    s.set_chords("| Cm | Cm | Ab | G | Cm | Fm | Ab | G | Fm | Cm | Db | G | Ab | Fm | G | G7 |")
    s.part("cello", 42, vol=94, pan=50, rev=60)
    s.part("bass", 43, vol=90, pan=64, rev=60)
    s.part("choir", 53, vol=84, pan=70, rev=100)
    s.part("organ", 19, vol=60, pan=60, rev=100)
    s.part("oboe", 68, vol=100, pan=54, rev=80)
    s.part("bell", 14, vol=80, pan=76, rev=110)
    s.part("timp", 47, vol=86, pan=64, rev=70)
    s.part("celesta", 8, vol=66, pan=84, rev=100)
    s.arp("cello", [0, 2, 1, 2], step=0.5, low=36, vel=70, span=1, legato=0.85)
    s.bass("bass", [(0, 4, "R")], octave=28, vel=74)
    s.pad("choir", center=60, voices=4, vel=66)
    s.pad("organ", center=55, voices=3, vel=50, bars=range(8, 16))
    mel = ("C5:2 Eb5:1 D5:1 C5:1 G4:3 Ab4:1 C5:1 Eb5:1.5 D5:.5 D5:3 B4:1 "
           "C5:1.5 D5:.5 Eb5:1 G5:1 Ab5:2 G5:1 F5:1 Eb5:1.5 F5:.5 Eb5:1 C5:1 B4:4 "
           "F5:2 Ab5:1 G5:1 Eb5:2 C5:2 Db5:1.5 F5:.5 Ab5:1 F5:1 G5:2 D5:1 B4:1 "
           "C5:1 Eb5:1 Ab5:2 F5:1 Ab5:1 C6:2 B5:2 G5:1 F5:1 D5:2 B4:2")
    s.melody("oboe", mel, vel=84, legato=0.95)
    s.melody("celesta", "r:32 C6:.5 Eb6:.5 G6:.5 r:2.5 Ab5:.5 C6:.5 Eb6:.5 r:2.5 F5:.5 Ab5:.5 C6:.5 r:2.5 G5:.5 B5:.5 D6:.5 r:2.5 "
                        "r:16", vel=58, legato=1.0)
    for b in (0, 4, 8, 12):
        s.note("bell", b * 4, 4, 60 if b != 8 else 53, 84)
    for b in range(16):
        r = s.chord_at(b * 4)[0]
        s.note("timp", b * 4, 1, low_note(r, 36), 64 + (16 if b % 4 == 0 else 0))
    s.roll("timp", 43, 15 * 4, 4, 30, 90)
    return s


def dungeon_ticket():
    """모집권 던전(돌의 사원, 골렘) — '돌의 사원'. D 도리안 100BPM. 칼림바 오스티나토, 팬플루트 주제, 타이코 리듬."""
    s = Song("dungeon_ticket", 100, 16, seed=18)
    s.set_chords("| Dm | C | Dm | G | Dm | Am | Bb | C | Dm | C | G | Dm | F | C | G | Am |")
    s.part("kalimba", 108, vol=88, pan=76, rev=70)
    s.part("bass", 32, vol=94, pan=60, rev=40)
    s.part("pad", 49, vol=70, pan=50, rev=90)
    s.part("pan", 75, vol=104, pan=58, rev=80)
    s.part("taiko", 116, vol=100, pan=64, rev=50)
    s.part("drums", 0, vol=82, drum=True, rev=50)
    s.arp("kalimba", [0, 2, 1, 3, 2, 4, 3, 2], step=0.5, low=62, vel=66, span=2, legato=1.0, accent=6)
    s.bass("bass", [(0, 1.5, "R"), (1.5, 1, "5"), (2.5, 1.5, "8")], octave=38, vel=80, legato=0.85)
    s.pad("pad", center=57, voices=3, vel=52)
    mel = ("A4:1.5 C5:.5 D5:2 E5:1 D5:.5 C5:.5 G4:2 A4:1 D5:1 F5:1 E5:1 D5:2 B4:2 "
           "A4:1.5 C5:.5 D5:1 F5:1 E5:2 C5:1 A4:1 D5:1.5 C5:.5 Bb4:1 F4:1 G4:3 r:1 "
           "D5:1.5 E5:.5 F5:1 A5:1 G5:2 E5:1 C5:1 B4:1 D5:1 G5:1.5 F5:.5 F5:1 E5:1 D5:2 "
           "C5:1 F5:1 A5:1.5 G5:.5 G5:1 E5:1 C5:2 D5:1 G5:1 B5:1 A5:1 A5:2 E5:1 C5:1")
    s.melody("pan", mel, bar=0, vel=84, legato=0.92)
    for b in range(16):
        s.note("taiko", b * 4, .5, 41, 104)
        s.note("taiko", b * 4 + 1.5, .5, 41, 70)
        s.note("taiko", b * 4 + 2, .5, 45, 86)
        s.note("taiko", b * 4 + 3, .5, 41, 76 if b % 2 == 0 else 96)
        if b % 2 == 1:
            s.note("taiko", b * 4 + 3.5, .5, 45, 80)
    s.drums("drums", {SHAKER: "-.o.-.o.-.o.-.o.", 75: "x..x..x...x..x.."}, bars=range(4, 16))
    s.drums("drums", {TRI: "x..............."}, bars=[0, 8])
    return s


def dragon():
    """길드 보스(드래곤) — '화염의 비룡'. E단조 138BPM. 트레몰로 현 16분, 합창, 브라스 주제, 팀파니·타이코·심벌."""
    s = Song("dragon", 138, 24, seed=19)
    s.set_chords("| Em | Em | C | D | Em | Em | C | B | Am | Em | C | D | Am | Em | C | B |"
                 " G | D | Em | C | Am | D | B | B |")
    s.part("strings", 48, vol=86, pan=76, rev=55)
    s.part("low", 58, vol=90, pan=60, rev=40)
    s.part("cello", 42, vol=94, pan=48, rev=40)
    s.part("choir", 52, vol=90, pan=64, rev=90)
    s.part("brass", 61, vol=110, pan=56, rev=60)
    s.part("horn", 60, vol=90, pan=40, rev=60)
    s.part("timp", 47, vol=100, pan=64, rev=50)
    s.part("drums", 0, vol=92, drum=True, rev=40)
    s.arp("strings", [0, 1, 2, 1], step=0.25, low=64, vel=58, span=1, legato=0.7, accent=8)
    riff = [(0, .5, "r"), (.5, .25, "r"), (.75, .25, "r"), (1, .5, "8"), (1.5, .5, "r"), (2, .5, "r"), (2.5, .5, "5"), (3, .5, "8"), (3.5, .5, "7")]
    s.bass("cello", riff, octave=40, vel=84, legato=0.65)
    s.bass("low", [(0, 1.5, "r"), (2, 1.5, "r")], octave=28, vel=82, bars=range(4, 24))
    s.pad("choir", center=64, voices=4, vel=74)
    s.pad("horn", center=60, voices=3, vel=72, rhythm=[(0, 1.5), (1.5, .5), (2, 2)], bars=range(16, 24))
    mel = ("E5:2 G5:1 F#5:1 E5:1 B4:1 E5:2 G5:1.5 F#5:.5 E5:1 C5:1 D#5:2 F#5:2 "
           "A5:2 G5:1 E5:1 G5:1.5 F#5:.5 E5:2 E5:1 G5:1 C6:1 B5:1 A5:2 F#5:1 D5:1 "
           "C6:2 B5:1 A5:1 B5:1.5 A5:.5 G5:1 E5:1 G5:1 A5:1 B5:1 C6:1 B5:2 F#5:1 D#5:1 "
           "D6:2 B5:1 G5:1 A5:2 F#5:1 D5:1 E5:1 G5:1 B5:2 C6:1.5 B5:.5 G5:1 E5:1 "
           "A5:1 C6:1 E6:2 D6:1.5 C6:.5 A5:1 F#5:1 B5:2 A5:1 F#5:1 D#5:1 E5:.5 F#5:.5 B4:2")
    s.melody("brass", mel, bar=4, vel=96, legato=0.9)
    for b in range(24):
        r = s.chord_at(b * 4)[0]
        tp = low_note(r, 38)
        s.note("timp", b * 4, 1, tp, 104)
        s.note("timp", b * 4 + 1.5, .5, tp, 74)
        s.note("timp", b * 4 + 2.5, .5, tp, 84)
    s.drums("drums", {KICK: "x..x....x..x....", SNARE: "....x.......x..."}, bars=range(4, 24))
    s.drums("drums", {CRASH: "x..............."}, bars=[0, 4, 8, 16])
    s.roll("timp", 40, 3 * 4, 4, 40, 112)
    for b in (7, 15, 23):
        s.drums("drums", {SNARE: "........xxx.x.xx", TOM_H: "...........x....", TOM_M: ".............x..", FLOOR: "..............x."}, bars=[b])
    return s


def guild_war():
    """길드전(공성) — '공성전'. G단조 112BPM 행진곡. 스네어 행진 리듬, 트럼펫 팡파르, 호른 대선율, 트롬본 저음."""
    s = Song("guild_war", 112, 16, seed=20)
    s.set_chords("| Gm | Gm | Eb | F | Gm | Cm | D | D | Eb | F | Bb | Gm | Cm | Gm | D | D7 |")
    s.part("tbn", 57, vol=96, pan=60, rev=40)
    s.part("tuba", 58, vol=90, pan=64, rev=40)
    s.part("strings", 48, vol=80, pan=78, rev=60)
    s.part("tpt", 56, vol=106, pan=54, rev=55)
    s.part("horn", 60, vol=94, pan=40, rev=60)
    s.part("timp", 47, vol=94, pan=64, rev=50)
    s.part("drums", 0, vol=98, drum=True, rev=40)
    s.bass("tuba", [(0, 1, "r"), (1, 1, "5"), (2, 1, "r"), (3, 1, "5")], octave=31, vel=82, legato=0.7)
    s.pad("tbn", center=55, voices=3, vel=76, rhythm=[(0, .75), (.75, .25), (1, 1), (2, .75), (2.75, .25), (3, 1)], legato=0.8)
    s.pad("strings", center=67, voices=4, vel=58)
    mel = ("D5:.75 D5:.25 G5:1 D5:1 Bb4:1 G4:.75 Bb4:.25 D5:1 G5:2 G5:.75 F5:.25 Eb5:1 Bb4:1 G4:1 A4:.75 C5:.25 F5:1 C5:1 A4:1 "
           "D5:.75 D5:.25 G5:1 A5:1 Bb5:1 C6:1.5 Bb5:.5 G5:1 Eb5:1 D5:.75 F#5:.25 A5:1 D6:1 A5:1 F#5:3 r:1 "
           "G5:.75 G5:.25 Bb5:1 G5:1 Eb5:1 F5:.75 F5:.25 A5:1 C6:2 D6:1.5 C6:.5 Bb5:1 F5:1 G5:2 D5:2 "
           "Eb5:.75 Eb5:.25 G5:1 C6:1 G5:1 Bb5:1.5 A5:.5 G5:1 D5:1 F#5:.75 G5:.25 A5:1 C6:1 A5:1 F#5:1 A5:.5 F#5:.5 D5:2")
    s.melody("tpt", mel, vel=94, legato=0.85)
    s.melody("horn", "Bb4:2 D5:2 G4:4 G4:2 Bb4:2 C5:4 Bb4:4 Eb5:4 F#4:4 A4:4 "
                     "Bb4:4 C5:4 F5:4 D5:4 Eb5:4 D5:4 C5:4 C5:4", vel=72, legato=0.95)
    for b in range(16):
        r = s.chord_at(b * 4)[0]
        tp = low_note(r, 38)
        s.note("timp", b * 4, 1, tp, 96)
        s.note("timp", b * 4 + 2, 1, tp, 80)
    s.drums("drums", {SNARE: "x..ox.o.x.oox.o.", KICK: "x.......x......."})
    s.drums("drums", {SNARE: "x.oox.oox.ooxxxx"}, bars=[7, 15])
    s.drums("drums", {CRASH: "x..............."}, bars=[0, 8])
    return s


SONGS = {f.__name__: f for f in (title, idle, fever, stage, boss, dungeon_gold, dungeon_equip, dungeon_ticket, dragon, guild_war)}

if __name__ == "__main__":
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    out = os.path.join(root, "assets", "audio", "music")
    work = os.environ.get("WORK_DIR", "/tmp/castlerpg-music")
    preview = os.environ.get("PREVIEW_DIR")
    names = sys.argv[1:] or list(SONGS)
    total = 0
    for n in names:
        song = SONGS[n]()
        ogg, sec, size = song.render(out, work, preview_dir=preview)
        total += size
        print(f"{n:16s} {sec:5.1f}s {size / 1024:7.1f} KB")
    print(f"total {total / 1024 / 1024:.2f} MB")
