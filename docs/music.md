# 배경음악 (2026-10-06)

장면(테마)마다 다른 곡이 끊김 없이 반복되고, 장면이 바뀌면 1.2초 동안 크로스페이드한다. 코드: `scripts/music.gd`(오토로드 `Music`).
오른쪽 아래 메뉴 **[음악]** 으로 켜고 끈다(폰에 저장, 기본 켬).

| 테마 | 파일 | 곡 | 언제 |
|---|---|---|---|
| title | `assets/audio/music/title.ogg` | 성의 서막 (D장조 84BPM) | 로그인·로딩 화면 |
| idle | `idle.ogg` | 성 아래 마을 (G장조 3/4 왈츠) | 방치 모드 |
| fever | `fever.ogg` | 피버 타임 (F장조 150BPM) | 방치 중 FEVER |
| stage | `stage.ogg` | 성벽 방어전 (A단조 132BPM) | 스테이지 전투·결과·카운트다운 |
| boss | `boss.ogg` | 성문 앞의 거인 (D단조 144BPM) | 보스 라운드(라운드 25) |
| dungeon_gold | `dungeon_gold.ogg` | 고블린 들판 (C장조 120BPM) | 골드 던전 |
| dungeon_equip | `dungeon_equip.ogg` | 망자의 성채 (C단조 92BPM) | 장비 던전 |
| dungeon_ticket | `dungeon_ticket.ogg` | 돌의 사원 (D 도리안 100BPM) | 모집권 던전 |
| dragon | `dragon.ogg` | 화염의 비룡 (E단조 138BPM) | 길드 보스(드래곤) |
| guild_war | `guild_war.ogg` | 공성전 (G단조 112BPM 행진곡) | 길드전 |

## 저작권·라이선스

- **작곡·편곡**: 모든 곡의 멜로디·화성·편곡은 이 프로젝트를 위해 새로 쓴 것이다(`dev/music/songs.py`에 악보가 그대로 있다).
  기존 곡·멜로디·샘플 루프·AI 음악 생성기를 쓰지 않았다. 이 게임의 저작물이다.
- **악기 소리**: MIDI를 [FluidSynth](https://www.fluidsynth.org/)(LGPL-2.1, 렌더링 도구로만 사용 — 게임에 포함되지 않음)로
  **FluidR3_GM 사운드폰트**(Frank Wen, **MIT 라이선스**)로 렌더링했다. MIT는 상업적 사용·배포·수정을 허용하며,
  아래 저작권 고지를 남기는 것 외에 조건이 없다. 렌더링한 오디오에는 사운드폰트 자체가 들어가지 않는다.

```
FluidR3_GM — Copyright (c) 2000-2002, 2008 Frank Wen
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
(the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions: The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## 다시 만들기

```
apt-get install fluidsynth fluid-soundfont-gm ffmpeg   # FluidR3_GM.sf2 → /usr/share/sounds/sf2/
pip install mido scipy numpy
python3 dev/music/songs.py            # 전부 → assets/audio/music/*.ogg
python3 dev/music/songs.py boss       # 한 곡만
PREVIEW_DIR=/tmp/preview python3 dev/music/songs.py   # 들어 보기용 MP3도
```

- 반복 이음매: 루프를 두 번 이어 렌더링해 두 번째 루프만 잘라 쓰고(첫 루프의 잔향이 시작에 겹쳐 있다), 끝 2048샘플을 첫 루프 끝과 교차한다.
- 음량: 곡마다 RMS −17 dBFS로 맞추고 부드럽게 제한. OGG Vorbis q3(곡당 0.3~0.7MB, 전체 약 5MB). `.import`는 `loop=true`.
- 테스트: `tests/music_check.tscn`(헤드리스) — 테마 고르기·크로스페이드·켬/끔·던전 진입/퇴장·곡 길이.
