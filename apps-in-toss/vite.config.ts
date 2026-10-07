import { defineConfig } from 'vite'

// public/game/ = Godot 웹 내보내기(dev/build-toss.sh가 채운다 — 저장소에는 두지 않는다). 상대 경로로 묶는다.
export default defineConfig({
  base: './',
  build: { outDir: 'dist', assetsInlineLimit: 0, chunkSizeWarningLimit: 2048 },
})
