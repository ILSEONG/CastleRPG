// 같은 등급 전투력 맞춤(2026-11-02 사용자 "같은 등급의 영웅들의 레벨이나 성급이 동일하다고 하면 전투력의 차이는 최대 10이야"): rules.powerAt.
import assert from 'node:assert/strict'
import { after, before, test } from 'node:test'
import * as R from '../src/rules.ts'
import { setup } from './helpers.ts'
import type { Setup } from './helpers.ts'

let S: Setup
before(async () => { S = await setup() })
after(async () => { await S.close() })

test('같은 등급·레벨·승급이면 전투력 차이는 10 이하(R·SR·SSR·UR, Lv 1~200, 승급 0~5), 장비는 같은 등급이면 같은 만큼, 등급 표에 없는 영웅은 예전 식', async () => {
  const heroes = (await S.db.query('select * from heroes')) as Record<string, any>[]
  const cfgRows = (await S.db.query('select key, value from game_config')) as { key: string; value: string }[]
  const config = Object.fromEntries(cfgRows.map((x) => [x.key, x.value]))
  R.indexPower(heroes)
  for (const g of ['R', 'SR', 'SSR', 'UR']) {
    for (const [lv, pr] of [[1, 0], [10, 2], [120, 3], [200, 5]]) {
      const ps = heroes.filter((h) => h.grade === g).map((h) => R.heroPower(h, lv, pr, { hp: 0, atk: 0 }, config))
      assert.ok(Math.max(...ps) - Math.min(...ps) <= 10, `${g} Lv${lv} ★${pr}: ${ps}`)
    }
  }
  const r = heroes.filter((h) => h.grade === 'R')
  const eq = { hp: 100, atk: 12 }
  const d = r.map((h) => R.heroPower(h, 1, 0, eq, config) - R.heroPower(h, 1, 0, { hp: 0, atk: 0 }, config))
  assert.ok(Math.max(...d) - Math.min(...d) <= 1 && Math.min(...d) > 10, `equipment ${d}`)
  const odd = { id: 'zz', grade: 'R', role: 'melee', hp: 100, atk: 10, atk_interval: 1 }
  assert.equal(R.heroPower(odd, 1, 0, { hp: 0, atk: 0 }, config), R.powerOf(odd, 100, 10))
})
