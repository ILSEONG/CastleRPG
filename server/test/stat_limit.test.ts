// 2026-10-07 능력치 상한: PVP·길드전 수비 능력치 상한(R.statLimit + W.capStats)과 드래곤 피해 상한(G.teamDps)에 장비·연구·길드가 들어간다.
import assert from 'node:assert/strict'
import { test } from 'node:test'
import * as G from '../src/guild.ts'
import * as R from '../src/rules.ts'
import * as W from '../src/guild_war.ts'

const cfg = (k: string) => ({ hero_level_stat: 0.042, hero_level_stat_melee: 0.0315, promote_mult: 1.3 } as Record<string, number>)[k]
const kyle = { id: 'kyle', role: 'melee', hp: 576, atk: 61, atk_interval: 0.64, grade: 'SSR' }
const upgrades = [{ id: 'atk', per_level: 0.5, max_level: 200 }, { id: 'hp', per_level: 0.5, max_level: 200 }] as R.UpgradeDef[]
const research = [{ id: 'hero_weapon', effect: 'hero_atk_pct', per_level: 3, max_level: 10 }, { id: 'legend_weapon', effect: 'hero_atk_pct', per_level: 4, max_level: 10 },
  { id: 'hero_armor', effect: 'hero_hp_pct', per_level: 3, max_level: 10 }, { id: 'legend_armor', effect: 'hero_hp_pct', per_level: 4, max_level: 10 }] as R.ResearchDef[]
const lr = (id: number, slot: string) => ({ id, slot, weapon_kind: slot === 'weapon' ? 'dagger' : null, grade: 'LR', rolls: { [slot === 'weapon' || slot === 'gloves' ? 'atk' : 'hp']: 115 } })

test('statLimit: 성장·연구 최대 + 길드 Lv 20이면 기본의 4배를 넘어도 앱이 보낸 값 그대로 받는다', () => {
  const pl = { upgrades: { atk: 200, hp: 200 }, research: { hero_weapon: 10, legend_weapon: 10, hero_armor: 10, legend_armor: 10 }, items: [], equipment: [] }
  const lim = R.statLimit(pl, { upgrades, research }, G.buffPct(20))
  assert.ok(Math.abs(lim.atk - 2 * 1.7 * 1.2) < 1e-9)
  const base = W.heroStats(kyle, 30, 3, cfg)
  const sent = { hp: Math.round(base.hp * lim.hp), atk: Math.round(base.atk * lim.atk * 10) / 10 }
  assert.ok(sent.atk > base.atk * W.STAT_CAP, 'legit value is above the old ×4 cap')
  const s = W.capStats(kyle, 30, 3, sent.hp, sent.atk, cfg, lim)
  assert.deepEqual(s, sent)
  const old = W.capStats(kyle, 30, 3, sent.hp, sent.atk, cfg)
  assert.ok(old.atk < sent.atk, 'without a limit the old ×4 cap still applies')
  const cheat = W.capStats(kyle, 30, 3, sent.hp * 2, sent.atk * 2, cfg, lim)
  assert.ok(cheat.atk <= (base.atk * lim.atk) * W.STAT_SLACK + 0.1 && cheat.hp <= base.hp * lim.hp * W.STAT_SLACK + 1)
})

test('statLimit: 1레벨 영웅의 LR 장비 몫은 성장 전에도 기본의 4배를 넘는다 — 장비 몫까지 받는다', () => {
  const pl = { upgrades: {}, research: {}, items: [lr(1, 'weapon'), lr(2, 'gloves')], equipment: [{ hero_id: 'kyle', item_id: 1 }, { hero_id: 'kyle', item_id: 2 }] }
  const lim = R.statLimit(pl, { upgrades, research }, 0)
  assert.deepEqual(lim.equip.kyle, { hp: 0, atk: 150 + 60 })
  const s = W.capStats(kyle, 1, 0, 576, 61 + 210, cfg, lim)
  assert.equal(s.atk, 271)
  assert.ok(W.capStats(kyle, 1, 0, 576, 271, cfg).atk < 271, 'old cap cut it')
})

test('teamDps: 장비 공격과 연구 공격 %가 들어간다', () => {
  const heroes = { kyle: { level: 1, promotion: 0 } }
  const before = G.teamDps(['kyle'], heroes, [kyle], cfg, 0, 0, 0)
  assert.ok(Math.abs(before - 61 / 0.64) < 1e-9)
  const after = G.teamDps(['kyle'], heroes, [kyle], cfg, 0, 0, 0, { kyle: { hp: 0, atk: 39 } }, 50)
  assert.ok(Math.abs(after - (100 * 1.5) / 0.64) < 1e-9)
})
