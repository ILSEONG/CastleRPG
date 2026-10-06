"""배경음악 작곡 엔진: 악보(멜로디 문자열·코드 진행)를 MIDI로 만들고 FluidSynth + FluidR3_GM(MIT)으로 렌더링해
끊김 없이 반복되는 OGG를 만든다. 곡은 모두 이 저장소에서 새로 쓴 것(songs.py) — 기존 곡·샘플 루프를 쓰지 않는다.

이음매: 같은 루프를 두 번 이어 렌더링하고 두 번째 루프 구간 [L, 2L)만 잘라 쓴다. 첫 루프의 잔향·여운이 두 번째 루프의
시작에 그대로 겹쳐 있으므로, 잘라 낸 구간을 처음으로 되감아도 소리가 이어진다.
"""
import os
import random
import subprocess

import mido
import numpy as np
from scipy.io import wavfile

SF2 = os.environ.get("SF2", "/usr/share/sounds/sf2/FluidR3_GM.sf2")
SR = 44100
TPB = 480

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
QUAL = {
    "": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10], "maj7": [0, 4, 7, 11],
    "sus4": [0, 5, 7], "sus2": [0, 2, 7], "dim": [0, 3, 6], "5": [0, 7], "add9": [0, 4, 7, 14], "m6": [0, 3, 7, 9],
}


def pc(name):
    """'C#' → 1, 'Bb' → 10"""
    v = NOTE[name[0]]
    for ch in name[1:]:
        v += 1 if ch == "#" else -1 if ch == "b" else 0
    return v % 12


def pitch(s):
    """'C4' → 60, 'F#5' → 78, 'Bb3' → 58"""
    i = 1
    while i < len(s) and s[i] in "#b":
        i += 1
    return pc(s[:i]) + 12 * (int(s[i:]) + 1) + (12 if s[:i] == "B#" else 0) - (12 if s[:i] == "Cb" else 0)


def low_note(pc_, lo):
    """음이름 pc_를 lo..lo+11 안의 MIDI 음으로(팀파니·저음)."""
    return lo + (pc_ - lo) % 12


def chord(name):
    """'Am' → (9, [0,3,7], 9), 'A/C#' → (9, [0,4,7], 1)"""
    bass = None
    if "/" in name:
        name, b = name.split("/")
        bass = pc(b)
    i = 1
    while i < len(name) and name[i] in "#b":
        i += 1
    root = pc(name[:i])
    return root, QUAL[name[i:]], root if bass is None else bass


class Song:
    def __init__(self, name, bpm, bars, beats=4, seed=1):
        self.name, self.bpm, self.bars, self.beats = name, bpm, bars, beats
        self.parts = {}
        self.order = []
        self.rng = random.Random(seed)
        self.chords = []  # 마디별 [(시작 박, 길이, 코드)]

    @property
    def length(self):
        return self.bars * self.beats

    def seconds(self):
        return self.length * 60.0 / self.bpm

    def set_chords(self, text):
        """'| C | G | Am F | ...' — 마디 안 여러 코드는 박을 똑같이 나눈다."""
        bars = [b.split() for b in text.strip().strip("|").split("|")]
        assert len(bars) == self.bars, f"{self.name}: chords {len(bars)} != bars {self.bars}"
        self.chords = []
        for i, names in enumerate(bars):
            d = self.beats / len(names)
            self.chords.append([(i * self.beats + j * d, d, chord(n)) for j, n in enumerate(names)])

    def chord_at(self, t):
        bar = self.chords[int(t // self.beats) % self.bars]
        for s, d, c in bar:
            if s <= t % self.length < s + d + 1e-6:
                return c
        return bar[-1][2]

    def part(self, name, program, vol=100, pan=64, rev=50, chorus=0, drum=False):
        self.parts[name] = dict(program=program, vol=vol, pan=pan, rev=rev, chorus=chorus, drum=drum, notes=[])
        self.order.append(name)

    def note(self, part, t, dur, p, vel, jitter=True):
        if jitter and not self.parts[part]["drum"]:
            t += self.rng.uniform(-0.012, 0.012)
            vel += self.rng.randint(-5, 5)
        elif jitter:
            vel += self.rng.randint(-4, 4)
        self.parts[part]["notes"].append((max(0.0, t), dur, p, int(max(1, min(127, vel)))))

    # --- 쓰기 도우미 ---

    def melody(self, part, text, bar=0, transpose=0, vel=96, legato=0.95, accent=True):
        """'E5:1 D5:.5 r:.5 ...' 를 bar(0부터)에서 이어 놓는다. 'C5+E5:1' 은 화음."""
        t = bar * self.beats
        for tok in text.split():
            n, d = tok.split(":")
            d = float(d)
            if n != "r":
                v = vel + (6 if accent and abs(t % self.beats) < 1e-6 else 0) + (4 if d >= 1.5 else 0)
                for k in n.split("+"):
                    self.note(part, t, d * legato, pitch(k) + transpose, v)
            t += d
        return t

    def voicing(self, c, center, voices, prev):
        root, ints, _ = c
        pcs = {(root + i) % 12 for i in ints}
        cands = [p for p in range(center - 14, center + 15) if p % 12 in pcs]
        target = center if prev is None else 0.6 * prev + 0.4 * center
        best, bv = None, 1e9
        for i in range(len(cands) - voices + 1):
            w = cands[i:i + voices]
            if len({p % 12 for p in w}) < min(len(pcs), voices):
                continue
            v = abs(sum(w) / voices - target)
            if v < bv:
                best, bv = w, v
        return best

    def pad(self, part, center=60, voices=4, vel=70, bars=None, rhythm=None, legato=1.0):
        """코드마다 화음을 길게(rhythm = 코드 안 [(오프셋, 길이)] 이면 그 리듬으로)."""
        prev = None
        for bi, bar in enumerate(self.chords):
            if bars and bi not in bars:
                continue
            for s, d, c in bar:
                v = self.voicing(c, center, voices, prev)
                prev = sum(v) / len(v)
                hits = rhythm or [(0, d)]
                for o, l in hits:
                    if o >= d - 1e-6:
                        continue
                    for p in v:
                        self.note(part, s + o, min(l, d - o) * legato, p, vel)

    def arp(self, part, pattern, step=0.5, low=55, vel=70, bars=None, span=2, legato=0.9, accent=10):
        """코드 구성음(low 이상, span 옥타브)을 pattern 순서대로 step 박마다."""
        for bi, bar in enumerate(self.chords):
            if bars and bi not in bars:
                continue
            for s, d, c in bar:
                root, ints, _ = c
                tones = sorted(p for p in range(low, low + 12 * span + 1) if (p - root) % 12 in [i % 12 for i in ints])
                n = int(round(d / step))
                for k in range(n):
                    idx = pattern[k % len(pattern)]
                    if idx is None:
                        continue
                    p = tones[min(idx, len(tones) - 1)]
                    self.note(part, s + k * step, step * legato, p, vel + (accent if k % int(round(1 / step) or 1) == 0 else 0))

    def bass(self, part, rhythm, octave=36, vel=90, bars=None, legato=0.9):
        """rhythm = 코드 안 [(오프셋, 길이, 'R'|'5'|'8'|'3'|'7'|'-5')]. 'R' = 슬래시 베이스(없으면 근음)."""
        for bi, bar in enumerate(self.chords):
            if bars and bi not in bars:
                continue
            for s, d, c in bar:
                root, ints, bass = c
                base = octave + ((bass - octave) % 12)
                rbase = octave + ((root - octave) % 12)
                third = ints[1] if len(ints) > 1 and ints[1] in (3, 4) else 4
                for o, l, deg in rhythm:
                    if o >= d - 1e-6:
                        continue
                    p = {"R": base, "r": rbase, "5": rbase + 7, "8": rbase + 12, "3": rbase + third,
                         "7": rbase + (ints[3] if len(ints) > 3 else 10), "-5": rbase - 5}[deg]
                    self.note(part, s + o, min(l, d - o) * legato, p, vel + (8 if o == 0 else 0))

    def drums(self, part, pats, bars=None, step=0.25):
        """pats = {GM 타악기 번호: '16칸 문자열'} — x 강, o 중간, - 약, . 쉼. 문자열 길이가 마디 칸 수보다 길면 여러 마디."""
        vels = {"x": 112, "o": 86, "-": 58}
        for bi in range(self.bars):
            if bars and bi not in bars:
                continue
            for p, pat in pats.items():
                per = int(round(self.beats / step))
                pat = pat.replace(" ", "")
                seg = pat[(bi * per) % len(pat):][:per] if len(pat) > per else pat
                for k, ch in enumerate(seg):
                    if ch in vels:
                        self.note(part, bi * self.beats + k * step, step, p, vels[ch])

    def roll(self, part, p, start, dur, v0=50, v1=110, rate=0.125):
        n = int(dur / rate)
        for k in range(n):
            self.note(part, start + k * rate, rate, p, int(v0 + (v1 - v0) * k / max(1, n - 1)))

    # --- 출력 ---

    def midi(self, loops=2):
        mid = mido.MidiFile(ticks_per_beat=TPB)
        meta = mido.MidiTrack()
        meta.append(mido.MetaMessage("set_tempo", tempo=int(60_000_000 / self.bpm), time=0))
        meta.append(mido.MetaMessage("time_signature", numerator=self.beats, denominator=4, time=0))
        mid.tracks.append(meta)
        ch_free = [c for c in range(16) if c != 9]
        for name in self.order:
            P = self.parts[name]
            ch = 9 if P["drum"] else ch_free.pop(0)
            tr = mido.MidiTrack()
            ev = []
            if not P["drum"]:
                ev.append((0, 0, mido.Message("program_change", channel=ch, program=P["program"])))
            for cc, val in ((7, P["vol"]), (10, P["pan"]), (91, P["rev"]), (93, P["chorus"])):
                ev.append((0, 0, mido.Message("control_change", channel=ch, control=cc, value=val)))
            for L in range(loops):
                off = L * self.length
                for t, d, p, v in P["notes"]:
                    on = int(round((t + off) * TPB))
                    offt = int(round((t + off + max(d, 0.05)) * TPB))
                    ev.append((on, 2, mido.Message("note_on", channel=ch, note=p, velocity=v)))
                    ev.append((offt, 1, mido.Message("note_off", channel=ch, note=p, velocity=0)))
            # 끝 표시(렌더러가 2루프 뒤 한 박까지 돌게)
            ev.append((int((loops * self.length + self.beats) * TPB), 3, mido.Message("control_change", channel=ch, control=7, value=P["vol"])))
            ev.sort(key=lambda e: (e[0], e[1]))
            last = 0
            for tick, _, m in ev:
                tr.append(m.copy(time=tick - last))
                last = tick
            mid.tracks.append(tr)
        return mid

    def render(self, out_dir, work_dir, quality=3, target_rms_db=-17.0, preview_dir=None):
        os.makedirs(out_dir, exist_ok=True)
        os.makedirs(work_dir, exist_ok=True)
        mid_path = os.path.join(work_dir, self.name + ".mid")
        wav_path = os.path.join(work_dir, self.name + "_raw.wav")
        self.midi(2).save(mid_path)
        subprocess.run(["fluidsynth", "-ni", "-q", "-g", "0.5", "-r", str(SR), "-F", wav_path, SF2, mid_path],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        sr, x = wavfile.read(wav_path)
        x = x.astype(np.float64) / 32768.0
        L = int(round(self.seconds() * sr))
        seg = x[L:2 * L].copy()
        assert len(seg) == L, f"{self.name}: render too short"
        # 이음매: 끝 XF 샘플을 첫 루프의 끝(= 이 구간 처음 바로 앞 소리)으로 교차 — 렌더러의 블록 단위 타이밍 차이로 생길 딸깍 소리를 없앤다
        XF = 2048
        w = np.linspace(0.0, 1.0, XF)[:, None]
        seg[-XF:] = seg[-XF:] * (1 - w) + x[L - XF:L] * w
        rms = np.sqrt(np.mean(seg ** 2))
        seg = seg * (10 ** (target_rms_db / 20) / max(rms, 1e-9))
        seg = np.where(np.abs(seg) > 0.7, np.sign(seg) * (0.7 + 0.28 * np.tanh((np.abs(seg) - 0.7) / 0.28)), seg)
        loop_wav = os.path.join(work_dir, self.name + ".wav")
        wavfile.write(loop_wav, sr, (seg * 32767).astype(np.int16))
        ogg = os.path.join(out_dir, self.name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", loop_wav, "-c:a", "libvorbis", "-q:a", str(quality), ogg], check=True)
        if preview_dir:  # 들어 보기용 MP3: 한 바퀴 + 다시 처음 4초(이음매가 이어지는지 들린다)에서 페이드아웃
            os.makedirs(preview_dir, exist_ok=True)
            two = np.concatenate([seg, seg[: int(4 * sr)]])
            fade = np.linspace(1, 0, int(4 * sr))[:, None]
            two[-len(fade):] *= fade
            pv = os.path.join(work_dir, self.name + "_preview.wav")
            wavfile.write(pv, sr, (two * 32767).astype(np.int16))
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", pv, "-c:a", "libmp3lame", "-b:a", "160k",
                            os.path.join(preview_dir, self.name + ".mp3")], check=True)
        return ogg, self.seconds(), os.path.getsize(ogg)
