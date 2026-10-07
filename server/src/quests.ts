// 가이드 미션·반복 퀘스트 완료 판정(통합 테스트 2026-10-07: 서버가 앱의 완료 주장을 믿지 않게). 앱 scripts/tutorial.gd _done과 같은 규칙을
// 서버가 가진 상태로 본다. 사건 수(처치·수집·판매·모집)는 미션 상태의 서버 누적(missions.ts Counters.t)으로 — 미션이 된 뒤가 아니라 누적이라 앱보다 느슨하다.
// 건물·레벨 미션은 quests.csv needs로 따로 본다(app.ts).

import type { Counters } from './missions.ts'

export interface QuestFacts {
  stage: number // 다음에 할 라운드(지금까지 stage − 1까지 클리어)
  heroLevels: number[] // 보유 영웅 레벨
  heroIds: string[] // 보유 영웅 id
  starters: string[]
  deploy: unknown[]
  upgrades: Record<string, number>
  trainingOrSoldiers: boolean // 훈련 중이거나 병사가 있다
  dungeonBest: Record<string, number> // 던전 종류 → 최고 단계
  equipped: number // 장착한 장비 수
  soldierDeployed: number
  research: boolean // 연구 중이거나 연구한 적이 있다
  guild: boolean
  pvp: boolean // PVP를 한 판이라도 했다
  admin: boolean
  c: Counters
}

const t = (f: QuestFacts, k: string) => f.c.t[k] ?? 0

// 가이드 미션 id → 서버가 본 완료 여부. 모르는 id(건물 미션 등 needs로 보는 것)는 true.
export function tutorialDone(id: string, f: QuestFacts): boolean {
  let m: RegExpExecArray | null
  if ((m = /^kill_(\d+)$/.exec(id))) return t(f, 'kill') >= Number(m[1])
  if ((m = /^stage_(\d+)_(\d+)$/.exec(id))) {
    const round = (Number(m[1]) - 1) * 25 + Number(m[2])
    return f.stage > round || f.admin
  }
  if ((m = /^hero_lv(\d+)_(\d+)$/.exec(id))) return f.heroLevels.filter((lv) => lv >= Number(m![2])).length >= Number(m[1])
  if ((m = /^(atk|hp)_(\d+)$/.exec(id))) return (f.upgrades[m[1]] ?? 0) >= Number(m[2])
  if ((m = /^dungeon_(\w+)$/.exec(id))) return (f.dungeonBest[m[1]] ?? 0) >= 1
  switch (id) {
    case 'collect': return t(f, 'collect') >= 1
    case 'sell': return t(f, 'sell') >= 1
    case 'hero_level': return f.heroLevels.some((lv) => lv >= 2)
    case 'growth': return Object.values(f.upgrades).some((v) => v > 0)
    case 'gacha': return t(f, 'gacha') >= 10 || f.heroIds.some((h) => !f.starters.includes(h))
    case 'deploy_new': return f.deploy.some((h) => typeof h === 'string' && f.heroIds.includes(h) && !f.starters.includes(h))
    case 'train': return f.trainingOrSoldiers
    case 'equip': return f.equipped > 0
    case 'soldier_deploy': return f.soldierDeployed > 0
    case 'research': return f.research
    case 'guild': return f.guild
    case 'pvp': return f.pvp
  }
  return true
}

// 반복 퀘스트(가이드 카드, 앱 Tutorial.REPEATS 순서 = quests.csv 반복 행 순서): 사건, 첫 목표, 바퀴마다 늘어나는 목표.
export const REPEATS: Record<string, { ev: string; base: number; step: number }> = {
  rep_kill: { ev: 'kill', base: 100, step: 50 },
  rep_collect: { ev: 'collect', base: 3, step: 1 },
  rep_stage: { ev: 'stage', base: 2, step: 0 }, // 받을 때의 라운드에서 두 라운드 더(앱: 다음 라운드 + 1을 클리어)
  rep_growth_up: { ev: 'growth', base: 3, step: 1 },
  rep_sell: { ev: 'sell', base: 1, step: 0 },
  rep_hero_up: { ev: 'hero_level', base: 5, step: 2 },
  rep_gacha: { ev: 'gacha', base: 10, step: 0 },
  rep_dungeon_win: { ev: 'dungeon_win', base: 1, step: 0 },
  rep_build_up: { ev: 'build_up', base: 1, step: 0 },
}

// 반복 퀘스트 완료: 마지막 반복 퀘스트를 받은 뒤(qs, 없으면 이 기능이 생긴 뒤) 센 사건이 목표 이상. 라운드는 받을 때 라운드 + 2 이상.
export function repeatDone(id: string, cycle: number, stage: number, c: Counters): boolean {
  const r = REPEATS[id]
  if (!r) return true
  if (r.ev === 'stage') return c.qs?.stage === undefined || stage >= c.qs.stage + r.base
  return (c.t[r.ev] ?? 0) - (c.qs?.[r.ev] ?? 0) >= r.base + r.step * cycle
}

// 반복 퀘스트를 받은(또는 가이드를 끝낸) 때의 기준값
export const snapshot = (c: Counters, stage: number) => ({ ...c.t, stage })
