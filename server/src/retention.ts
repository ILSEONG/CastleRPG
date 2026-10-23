// 이탈 기록(2026-10-23, 마이그레이션 053): 접속한 날(player_days)과 가이드 단계(player_state.tut_step)로 본 간단한 지표.
// GameAnalytics·Firebase의 기본 지표와 같은 뜻: 가입한 날(D0) 기준으로 정확히 하루 뒤(D1)·7일 뒤(D7)에 한 번이라도 접속했는지(클래식 리텐션).
// 날짜는 KST(일일 미션 리셋과 같은 00:00 KST).
//
// 기록: 인증된 요청마다 dayRecorder(id, now) — 서버 메모리에 (플레이어, 날)을 기억해 하루 첫 요청만 DB에 넣는다.
// 관리자:
//  GET /v1/admin/retention → {server_now, today, players, dau, wau, d1: {rate, n, back}, d7: {…},
//    cohorts: [{day, date, n, d1, d7}] (최근 COHORT_DAYS일, 새것 먼저. 아직 그날이 안 온 칸은 null),
//    guide: {total, done, active, steps: [{i, id, reached, here, away}]} (가이드를 받은 플레이어만 — skipped 제외.
//      here = 지금 이 미션에서 멈춰 있는 수, away = 그중 AWAY_DAYS일 넘게 안 들어온 수 = 이 단계에서 이탈),
//    daily: [{day, date, n}] (최근 COHORT_DAYS일 날마다 접속한 사람 수, 새것 먼저),
//    stages: [{from, to, n, away}] (다음에 할 라운드를 STAGE_BUCKET개씩 묶은 분포 — 사람이 있는 칸만, 낮은 라운드 먼저)}
import type { Context, Hono, Next } from 'hono'

type Any = any

export const KST_SEC = 9 * 3600
export const COHORT_DAYS = 14 // 날짜별 표에 보이는 가입일 수
export const AVG_DAYS = 30 // 평균 D1·D7을 낼 때 보는 가입일 범위
export const AWAY_DAYS = 3 // 마지막 접속이 이만큼(일) 지나면 이탈로 본다
export const STAGE_BUCKET = 5 // 라운드 분포 한 칸의 라운드 수
export const CACHE_MAX = 100_000

export const kstDay = (t: number) => Math.floor((t + KST_SEC) / 86400)
// 날 번호 → "2026-10-23"
export const dayDate = (day: number) => new Date(day * 86400 * 1000).toISOString().slice(0, 10)

// 하루 첫 인증 요청에 접속한 날을 넣는다. 실패해도 요청은 막지 않는다(기록만 빠진다).
export function dayRecorder(query: (sql: string, params?: unknown[]) => Promise<Any[]>) {
  const seen = new Set<string>()
  let seenDay = -1
  return async (id: string, now: number) => {
    const day = kstDay(now)
    if (day !== seenDay || seen.size >= CACHE_MAX) {
      seen.clear()
      seenDay = day
    }
    const key = `${id}:${day}`
    if (seen.has(key)) return
    seen.add(key)
    await query('insert into player_days (player_id, day) values ($1, $2) on conflict do nothing', [id, day]).catch(() => seen.delete(key))
  }
}

const rate = (back: number, n: number) => (n > 0 ? Math.round((back / n) * 1000) / 10 : null)

export function registerRetention(app: Hono<Any>, d: Any) {
  const { query, auth, clock, ApiError, isAdmin } = d

  async function admin(c: Context, next: Next) {
    if (!(await isAdmin(c.get('playerId') as string))) throw new ApiError(403, 'not_admin', 'admins only')
    await next()
  }

  app.get('/v1/admin/retention', auth, admin, async (c: Context) => {
    const now = clock()
    const today = kstDay(now)
    const from = today - Math.max(COHORT_DAYS, AVG_DAYS) + 1
    const [counts] = await query(`select (select count(*)::int from players) as players,
        (select count(*)::int from player_days where day = $1) as dau,
        (select count(distinct player_id)::int from player_days where day > $1 - 7) as wau`, [today])
    const cohortRows = await query(`with c as (select id, floor((extract(epoch from created_at) + ${KST_SEC}) / 86400)::int as d0 from players)
      select c.d0, count(*)::int as n,
        count(*) filter (where exists (select 1 from player_days x where x.player_id = c.id and x.day = c.d0 + 1))::int as d1,
        count(*) filter (where exists (select 1 from player_days x where x.player_id = c.id and x.day = c.d0 + 7))::int as d7
      from c where c.d0 >= $1 group by c.d0 order by c.d0 desc`, [from])
    const cohorts = cohortRows.map((r: Any) => {
      const day = Number(r.d0)
      return { day, date: dayDate(day), n: Number(r.n), d1: day + 1 <= today ? Number(r.d1) : null, d7: day + 7 <= today ? Number(r.d7) : null }
    })
    const avg = (k: 'd1' | 'd7', gap: number) => {
      const done = cohorts.filter((x: Any) => x.day + gap <= today && x.day > today - AVG_DAYS - gap)
      const n = done.reduce((s: number, x: Any) => s + x.n, 0)
      const back = done.reduce((s: number, x: Any) => s + (x[k] ?? 0), 0)
      return { rate: rate(back, n), n, back }
    }

    const daily = (await query(`select day, count(*)::int as n from player_days where day > $1 group by day order by day desc`, [today - COHORT_DAYS]))
      .map((r: Any) => ({ day: Number(r.day), date: dayDate(Number(r.day)), n: Number(r.n) }))
    const stages = (await query(`select (s.stage - 1) / ${STAGE_BUCKET} as b, count(*)::int as n,
        count(*) filter (where p.last_seen < to_timestamp($1::float8))::int as away
      from player_state s join players p on p.id = s.player_id group by 1 order by 1`, [now - AWAY_DAYS * 86400]))
      .map((r: Any) => ({ from: Number(r.b) * STAGE_BUCKET + 1, to: (Number(r.b) + 1) * STAGE_BUCKET, n: Number(r.n), away: Number(r.away) }))

    const ids = (await query("select id from quest_defs where type = 'tutorial' order by ord")).map((r: Any) => String(r.id))
    const rows = await query(`select s.tut_state as state, s.tut_step as step, count(*)::int as n,
        count(*) filter (where p.last_seen < to_timestamp($1::float8))::int as away
      from player_state s join players p on p.id = s.player_id where s.tut_state <> 'skipped' group by 1, 2`, [now - AWAY_DAYS * 86400])
    let done = 0
    let active = 0
    const here = new Array(ids.length).fill(0)
    const away = new Array(ids.length).fill(0)
    for (const r of rows) {
      const step = Number(r.step)
      if (r.state === 'done' || step >= ids.length) done += Number(r.n)
      else {
        active += Number(r.n)
        here[step] += Number(r.n)
        away[step] += Number(r.away)
      }
    }
    let reached = done + active
    const steps = ids.map((id: string, i: number) => {
      const row = { i, id, reached, here: here[i], away: away[i] }
      reached -= here[i]
      return row
    })

    return c.json({ server_now: now, today, date: dayDate(today), players: Number(counts.players), dau: Number(counts.dau), wau: Number(counts.wau),
      d1: avg('d1', 1), d7: avg('d7', 7), cohorts: cohorts.slice(0, COHORT_DAYS), away_days: AWAY_DAYS, daily, stages,
      guide: { total: done + active, done, active, steps } })
  })
}
