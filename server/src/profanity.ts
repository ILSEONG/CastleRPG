// 채팅 욕설 가리기(2026-10-07 강화). 글을 "뼈대"로 바꿔 금지어를 찾고, 찾은 글자를 원문에서 *로 바꾼다.
// 뼈대: 한글 음절은 자모로 풀고(초성 ㅇ은 소리가 없어 뺀다 — 십알 = 시발), 된소리·비슷한 모음은 하나로(ㅆ→ㅅ, ㅃ→ㅂ, ㅟ·ㅢ→ㅣ, ㅔ→ㅐ),
// 겹받침·ㅄ 같은 겹자음은 둘로 푼다. 영어는 소문자로, 영어 사이 숫자는 비슷한 글자로(f4ck = fack, sh1t = shit). 그 밖의 숫자·공백·기호는
// 뺀다 — 씨1발, 시.발, ㅅ_ㅂ도 잡는다. 한글 자판 그대로 영어로 친 욕(tlqkf = 시발)도 목록에 있다.
// 오탐 줄이기: ① 금지어는 글자의 첫소리에서 시작해야 한다(받침 ㅅ + 다음 초성 ㅂ = "맛보다"는 ㅅㅂ이 아님).
// ② 초성만 쓴 줄임말(ㅅㅂ·ㅂㅅ…)은 낱자모로 친 글자에서만 잡는다. ③ 공백을 사이에 둔 채 걸리면 금지어가 낱말 처음에서 시작할 때만
// ("야 시 발"은 잡고 "다시 발견"은 안 잡는다). ④ 허용 낱말(시발점·등신대 …)에 걸친 곳은 가리지 않는다.
// 흔한 낱말과 겹치는 말(꺼져·닥쳐·보지·자지·애미·새끼 단독·미친 단독·시바·씹·졸라·개년)은 금지어에서 뺐다.

// prettier-ignore
export const BAD_WORDS = [
  // 시발 계열
  '시발', '씨발', '시빨', '씨빨', '씨벌', '시벌', '씨팔', '시팔', '씨펄', '십알', '시부랄', '씨부랄', '시바ㄹ', '썅', '쌍년', '쌍놈',
  // 병신 계열
  '병신', '븅신', '빙신', '병쉰', '병싄', '등신',
  // 좆·존나
  '좆', '좃같', '좇같', '존나', '존니',
  // 개새끼 계열
  '개새끼', '개새기', '개색기', '개색끼', '개세끼', '개쉐끼', '개쉑', '개새', '새끼야', '미친새끼', '호로새끼', '후레자식', '개놈', '개자식',
  // 그 밖
  '미친놈', '미친년', '지랄', '염병', '엠창', '느금', '니애미', '니애비', '니엄마', '애미뒤진', '애비뒤진', '창녀', '걸레년', '섹스', '한남충', '김치녀',
  // 초성 줄임말(낱자모로 쳤을 때만)
  'ㅅㅂ', 'ㅆㅂ', 'ㅂㅅ', 'ㅄ', 'ㅈㄹ', 'ㅁㅊ', 'ㄴㄱㅁ', 'ㅈㄴ',
  // 영어·한글 자판 영어
  'fuck', 'fuk', 'fck', 'fack', 'fvck', 'phuck', 'shit', 'bitch', 'asshole', 'cunt', 'sibal', 'ssibal', 'shibal', 'sival', 'byungsin', 'tlqkf', 'tlbal', 'qudtls', 'whssk', 'wlfkf', 'rotoRl',
]

// 금지어가 이 낱말 안에 있으면 가리지 않는다.
export const ALLOW_WORDS = ['시발점', '시발역', '시발택시', '등신대', '등신불', '개새우']

const L = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ'
const V = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ'
const T = ['', 'ㄱ', 'ㄲ', 'ㄳ', 'ㄴ', 'ㄵ', 'ㄶ', 'ㄷ', 'ㄹ', 'ㄺ', 'ㄻ', 'ㄼ', 'ㄽ', 'ㄾ', 'ㄿ', 'ㅀ', 'ㅁ', 'ㅂ', 'ㅄ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ']
const SPLIT: Record<string, string> = { ㄳ: 'ㄱㅅ', ㄵ: 'ㄴㅈ', ㄶ: 'ㄴㅎ', ㄺ: 'ㄹㄱ', ㄻ: 'ㄹㅁ', ㄼ: 'ㄹㅂ', ㄽ: 'ㄹㅅ', ㄾ: 'ㄹㅌ', ㄿ: 'ㄹㅍ', ㅀ: 'ㄹㅎ', ㅄ: 'ㅂㅅ' }
const SAME: Record<string, string> = { ㄲ: 'ㄱ', ㄸ: 'ㄷ', ㅃ: 'ㅂ', ㅆ: 'ㅅ', ㅉ: 'ㅈ', ㅟ: 'ㅣ', ㅢ: 'ㅣ', ㅔ: 'ㅐ', ㅖ: 'ㅒ' }
const LEET: Record<string, string> = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', '$': 's' }

type Kind = 'L' | 'V' | 'T' | 'J' | 'A' // 초성 · 중성 · 받침 · 낱자모 · 영어
interface Unit { ch: string; at: number; kind: Kind } // at = 원문 글자(코드 포인트) 위치

const isLatin = (c: string) => /^[a-z]$/i.test(c)

function jamo(s: string): string {
  return [...s].map((c) => SPLIT[c] ?? c).join('').split('').map((c) => SAME[c] ?? c).join('')
}

// 원문 → 뼈대 단위 목록.
export function skeleton(text: string): Unit[] {
  const chars = [...text]
  const out: Unit[] = []
  const push = (s: string, at: number, kind: Kind) => {
    for (const c of jamo(s)) out.push({ ch: c, at, kind })
  }
  chars.forEach((c, i) => {
    const code = c.codePointAt(0)!
    if (code >= 0xac00 && code <= 0xd7a3) {
      const n = code - 0xac00
      const l = L[Math.floor(n / 588)]
      if (l !== 'ㅇ') push(l, i, 'L')
      push(V[Math.floor((n % 588) / 28)], i, 'V')
      const t = T[n % 28]
      if (t) push(t, i, 'T')
    } else if (code >= 0x3131 && code <= 0x3163) {
      push(c, i, 'J')
    } else if (isLatin(c)) {
      out.push({ ch: c.toLowerCase(), at: i, kind: 'A' })
    } else if (LEET[c] && (isLatin(chars[i - 1] ?? '') || isLatin(chars[i + 1] ?? ''))) {
      out.push({ ch: LEET[c], at: i, kind: 'A' })
    }
  })
  return out
}

interface Pattern { s: string; initials: boolean } // initials = 초성 줄임말(낱자모로만)
const toPattern = (w: string): Pattern => {
  const u = skeleton(w)
  return { s: u.map((x) => x.ch).join(''), initials: u.every((x) => x.kind === 'J') }
}
const BAD = BAD_WORDS.map(toPattern)
const ALLOW = ALLOW_WORDS.map(toPattern)

const isSpace = (c: string | undefined) => c === undefined || /\s/u.test(c)

// 찾은 금지어 자리(원문 글자 위치, 끝 포함) 목록.
export function findBad(text: string): [number, number][] {
  const chars = [...text]
  const units = skeleton(text)
  const sk = units.map((u) => u.ch).join('')
  const allowed = new Set<number>() // 허용 낱말에 든 뼈대 단위
  for (const a of ALLOW) {
    for (let i = sk.indexOf(a.s); i >= 0; i = sk.indexOf(a.s, i + 1)) for (let k = i; k < i + a.s.length; k++) allowed.add(k)
  }
  const hits: [number, number][] = []
  for (const p of BAD) {
    for (let i = sk.indexOf(p.s); i >= 0; i = sk.indexOf(p.s, i + 1)) {
      const us = units.slice(i, i + p.s.length)
      const first = i === 0 || units[i - 1].at !== us[0].at // 그 글자의 첫 단위(초성, 초성 ㅇ을 뺀 중성, 낱자모, 영어)
      if (p.initials ? !us.every((u) => u.kind === 'J') : !first) continue
      if (us.some((_, k) => allowed.has(i + k))) continue
      const a = us[0].at
      const b = us[us.length - 1].at
      const spaced = chars.slice(a, b + 1).some((c) => isSpace(c))
      if (spaced && !isSpace(chars[a - 1])) continue // "다시 발견": 낱말 중간에서 시작해 공백을 넘었다
      hits.push([a, b])
    }
  }
  return hits
}

// 금지어 글자를 *로(공백은 그대로).
export function mask(text: string): string {
  const chars = [...text]
  for (const [a, b] of findBad(text)) for (let i = a; i <= b; i++) if (!isSpace(chars[i])) chars[i] = '*'
  return chars.join('')
}
