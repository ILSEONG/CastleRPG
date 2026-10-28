# Upstream

[epoko77-ai/im-not-ai](https://github.com/epoko77-ai/im-not-ai) v2.3.2 (commit `b37e020`), MIT — `LICENSE` 참조.

클라우드 세션은 매번 새 컨테이너에서 시작해 마켓플레이스 플러그인이 설치되지 않으므로,
`install.sh --claude-only --copy`와 같은 배치로 저장소에 복사해 두었다.

- `skills/{humanize-korean,humanize,humanize-scan,humanize-redo}` → `.claude/skills/`
- 런타임 스크립트 9종(`scripts/`) → `.claude/skills/humanize-korean/scripts/`
- 런타임 에이전트 3종(monolith·diagnostician·finalizer) → `.claude/agents/`

갱신할 때는 upstream을 받아 위 파일만 다시 복사한다.
