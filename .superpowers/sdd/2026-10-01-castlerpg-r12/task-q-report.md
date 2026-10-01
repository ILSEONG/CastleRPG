# Task Q report: gold-only hero level-up and idle invincibility

Branch: worktree-agent-a540fc73ddcc33fb7 (worktree C:\CastleRPG\.claude\worktrees\agent-a540fc73ddcc33fb7), based on c619240. Three commits (last 9bf43c4).

## Done
1. Gold only
   - data/config.csv: levelup_food_* removed (seed deletes absent keys, no migration).
   - server: seed.ts lists/validation, rules.ts levelupCost returns { gold }, app.ts /v1/hero/levelup no food check/charge, 409 code `not_enough_gold`, log detail without food. Tests: levelup, seed, concurrency, api (config key count 35 to 32), new "level-up with 0 food works".
   - app: GameData.levelup_cost returns {gold}; key lists updated; Economy.levelup_block gives only "골드 부족"; level_up charges gold only; online failure map uses not_enough_gold; hero_panel cost buttons show gold only.
   - tests: run_tests, input_check, online_check updated (food unchanged by level-up).
2. Idle invincibility
   - GameState.damage_gate / damage_castle return when mode == IDLE; Hero.take_damage returns first when IDLE (before dodge/thorns/numbers). COUNTDOWN/RESULT/STAGE unchanged.
   - HUD: title row with stage label + shield icon + "방치 · 무적", visible only in IDLE. icons.gd got a "shield" shape (not in KINDS).
   - ai_check: whole run now starts in STAGE (existing cases need damage; mode set directly), IDLE for (y) and level-up cases; new (I) case: idle = gates/castle/heroes unchanged after 5 s with 12 epic bosses at gates, monsters alive (12, below cap), direct damage calls do nothing; stage mode = same monsters do damage.

## Verification (headless, in the worktree)
- run_tests ALL PASSED; input_check INPUT ALL PASSED; ai_check AI ALL PASSED; E2E auto-stage [cleared] 1 then mode 1 stage=2 (and stage 3), no SCRIPT ERROR; server npm test 64 pass 0 fail; dev/online-check.sh ONLINE ALL PASSED (port 8790, not left listening).
- Proof: removed the IDLE guard from damage_gate, ai_check failed the two (I) idle checks; restored.

## Notes / concerns
- Likely trivial merge conflicts with B1: api.test.ts config key count (recompute after both merges), ai_check mode lines.
- ai_check sets GameState.mode directly without mode_changed (spawner is disabled there).
- Economy.FOOD const left (now unused by level-up).
- HUD badge not visually captured (web capture is the controller's job).
- The shared report path was blocked for writing; this copy is in the worktree at the same relative path.
