# 효과음 (2026-10-07)

버튼, 평타·타격·처치, 스킬, 보상·성장, 모집, 승패에 효과음이 난다. 코드: `scripts/sfx.gd`(오토로드 `SoundFx`, 부르는 쪽은
`const Sfx := preload("res://scripts/sfx.gd")`의 정적 함수). 설정 창 **[효과음]** 켬/끔과 **[효과음 음량]**(폰에 저장, 기본 켬·100%).

- 소리 파일: `assets/audio/sfx/<id>_<n>.ogg` 46종 88개(약 0.65 MB, 모노 32 kHz Vorbis).
- 만들기: `python3 dev/sfx/build_sfx.py <묶음 폴더>` — 아래 묶음에서 골라 앞뒤 무음을 자르고 크기를 맞추고, 일부는 두 소리를 겹친다.
  천둥(`sk_thunder`)은 노이즈로 직접 합성한다. 소리 이름·개수는 `scripts/sfx.gd` `SOUNDS`와 같아야 한다(`tests/run_tests.gd` `test_sfx`).
- 언제 나나: 버튼은 트리에 들어오는 모든 버튼에 스스로 붙는다(토글 = `tab`, 메타 `sfx_off`로 뺀다). 타격은 `DamageNumbers.pop`
  (숫자 표시를 꺼도 난다), 평타는 `hero.gd _release`, 스킬은 발동 순간(`hero_skills.gd`, `Sfx.SKILL`이 스킬 → 소리 무리), 처치·보스 등장은
  `monster.gd`, 보상·성장·승패는 오토로드 신호. 월드 소리는 화면 밖이면 내지 않고, 같은 소리는 정해진 간격 안에 겹치지 않는다.
- 검사: `godot --headless --path . res://tests/sfx_check.tscn` (실제 성 전투 25초: 소리 종류, 초당 횟수 상한, 끄기).

## 출처·라이선스

모두 **CC0(퍼블릭 도메인)** 이다. 상업적 사용·수정·배포에 조건이 없고 출처 표기도 의무가 아니지만, 고마움의 뜻으로 적어 둔다.

| 묶음 | 만든 사람 | 주소 | 쓴 소리 |
|---|---|---|---|
| Interface Sounds | Kenney | https://kenney.nl/assets/interface-sounds | 버튼, 탭, 오류, 확인 |
| Impact Sounds | Kenney | https://kenney.nl/assets/impact-sounds | 타격, 치명타, 피격, 성문 파괴, 대지 스킬 |
| Casino Audio | Kenney | https://kenney.nl/assets/casino-audio | 모집 카드 |
| Music Jingles | Kenney | https://kenney.nl/assets/music-jingles | 승리, 패배, 레벨업, 승급, 건설·연구 완료, SSR |
| 80 CC0 RPG SFX | rubberduck | https://opengameart.org/content/80-cc0-rpg-sfx | 동전, 보석, 칼날, 몬스터, 불 마법 |
| 100 CC0 SFX | rubberduck | https://opengameart.org/content/100-cc0-sfx | 징, 종 |
| 25 CC0 bang / firework SFX | rubberduck | https://opengameart.org/content/25-cc0-bang-firework-sfx | 폭발, 대포 |
| RPG Sound Pack | artisticdude | https://opengameart.org/content/rpg-sound-pack | 휘두르기, 마법 |
| Swishes Sound Pack | artisticdude | https://opengameart.org/content/swishes-sound-pack | 화살, 던지기, 바람 |
| Freeze Spell | artisticdude | https://opengameart.org/content/freeze-spell-0 | 얼음 |
| Cure Magic | someoneman | https://opengameart.org/content/cure-magic | 회복, 신성, 소환 |
| Catching fire | themightyglider | https://opengameart.org/content/catching-fire | 불 |
