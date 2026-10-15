// 게임 문구 다국어 표(texts.ts, 2026-10-14): texts.csv 형식, 시드가 DB texts 표를 채우는지, GET /v1/texts, txt().
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { DATA_DIR, readTextRows, readTables } from '../src/seed.ts'
import { parseQuotedCsv, parseTexts, setTexts, txt, unescapeValue } from '../src/texts.ts'
import { setup } from './helpers.ts'

test('texts.csv: 따옴표 칸(쉼표·""), \\n 줄바꿈, 키 형식·중복·빈 ko는 오류', () => {
  assert.deepEqual(parseQuotedCsv('a,"b,c","d""e"\n1,2,3\n'), [['a', 'b,c', 'd"e'], ['1', '2', '3']])
  assert.equal(unescapeValue('첫 줄\\n둘째 \\\\ 끝'), '첫 줄\n둘째 \\ 끝')
  const errs: string[] = []
  const rows = parseTexts('key,ko,en,ja,zh,note\na.b,"골드, 다이아",,,,x\nBad Key,x,,,,\na.b,중복,,,,\nc.d,,,,,\n', errs)
  assert.deepEqual(rows.map((r) => [r.key, r.ko, r.en]), [['a.b', '골드, 다이아', null]])
  assert.equal(errs.length, 3)
})

test('저장소 texts.csv는 오류가 없고, 기획 표 이름 칸(data.<표>.<id>.<칸>)이 붙는다', async () => {
  const errs: string[] = []
  const csv = parseTexts(readFileSync(join(DATA_DIR, 'texts.csv'), 'utf8'), errs)
  assert.deepEqual(errs, [])
  assert.ok(csv.length > 2000)
  const all = await readTextRows(DATA_DIR, await readTables(DATA_DIR))
  const arteon = all.find((r) => r.key === 'data.heroes.arteon.name')
  assert.equal(arteon?.ko, '아르테온')
  assert.ok(all.find((r) => r.key === 'data.buildings.keep.name'))
})

test('txt(): {이름} 채우기, 없는 키는 키 그대로, 빈 언어 칸은 ko', () => {
  setTexts([{ key: 'g.join', ko: '{name}님이 길드에 가입했습니다', en: '{name} joined', ja: null, zh: null, note: null }])
  assert.equal(txt('g.join', { name: '감자' }), '감자님이 길드에 가입했습니다')
  assert.equal(txt('g.join', { name: 'A' }, 'en'), 'A joined')
  assert.equal(txt('g.join', { name: 'A' }, 'ja'), 'A님이 길드에 가입했습니다')
  assert.equal(txt('no.such'), 'no.such')
})

test('GET /v1/texts: 시드한 DB 표를 언어별로, 같은 버전이면 same', async () => {
  const s = await setup()
  const r = await s.req('GET', '/v1/texts?lang=ko')
  assert.equal(r.status, 200)
  const b = r.json
  assert.equal(b.lang, 'ko')
  assert.equal(b.texts['data.heroes.arteon.name'], '아르테온')
  assert.ok(Object.keys(b.texts).length > 2000)
  const again = (await s.req('GET', `/v1/texts?lang=ko&v=${b.version}`)).json
  assert.deepEqual(again, { version: b.version, lang: 'ko', same: true })
  const en = (await s.req('GET', '/v1/texts?lang=xx')).json
  assert.equal(en.lang, 'ko') // 모르는 언어는 ko
  await s.close()
})
