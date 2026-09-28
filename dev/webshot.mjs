// 헤드리스 Chromium으로 웹 빌드를 열어 스크린샷을 저장한다. 창을 띄우지 않는다.
// 사용: node dev/webshot.mjs --out shot.png [--url http://localhost:8060/] [--wait 5000] [--size 360x640]
//                            [--click x,y[,ms]]... [--drag x1,y1,x2,y2[,ms]]... [--wheel x,y,dy[,ms]]... [--dragback x,y,dx,dy[,ms]]...
//                            [--until TEXT[,ms]]...
// 좌표는 CSS 픽셀(뷰포트 기준). 동작은 인자 순서대로 실행하고, 각 동작 뒤 ms(기본 500) 대기.
// --until TEXT[,ms]: 페이지 콘솔에 TEXT를 포함한 메시지가 (페이지 로드 이후) 뜰 때까지 최대 240초 기다린 뒤 ms(기본 500) 더 대기한다.
//                    타임아웃이면 에러 메시지를 찍고 0이 아닌 코드로 종료한다. 대기 시각을 추측하지 않고 실제 게임 로그로 확정하기 위한 용도.
// 페이지 콘솔 로그와 에러를 stdout에 출력한다.
import { chromium } from 'playwright';

const args = process.argv.slice(2);
const opt = { url: 'http://localhost:8060/', out: 'shot.png', wait: 5000, size: '360x640', actions: [] };
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  const v = args[i + 1];
  if (a === '--url') { opt.url = v; i++; }
  else if (a === '--out') { opt.out = v; i++; }
  else if (a === '--wait') { opt.wait = Number(v); i++; }
  else if (a === '--size') { opt.size = v; i++; }
  else if (a === '--click') { opt.actions.push({ type: 'click', nums: v.split(',').map(Number) }); i++; }
  else if (a === '--drag') { opt.actions.push({ type: 'drag', nums: v.split(',').map(Number) }); i++; }
  else if (a === '--wheel') { opt.actions.push({ type: 'wheel', nums: v.split(',').map(Number) }); i++; }
  else if (a === '--dragback') { opt.actions.push({ type: 'dragback', nums: v.split(',').map(Number) }); i++; }
  else if (a === '--until') {
    const parts = v.split(',');
    let ms = 500, text = v;
    if (parts.length > 1 && /^\d+$/.test(parts[parts.length - 1])) {
      ms = Number(parts.pop());
      text = parts.join(',');
    }
    opt.actions.push({ type: 'until', text, ms });
    i++;
  }
  else { console.error(`unknown arg: ${a}`); process.exit(2); }
}

const [width, height] = opt.size.split('x').map(Number);
const browser = await chromium.launch({
  headless: true,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 2 });
const logs = [];
page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
await page.goto(opt.url);
await page.waitForTimeout(opt.wait);
for (const act of opt.actions) {
  if (act.type === 'click') {
    const [x, y, ms = 500] = act.nums;
    await page.mouse.click(x, y);
    await page.waitForTimeout(ms);
  } else if (act.type === 'drag') {
    const [x1, y1, x2, y2, ms = 500] = act.nums;
    await page.mouse.move(x1, y1);
    await page.mouse.down();
    await page.mouse.move(x2, y2, { steps: 12 });
    await page.mouse.up();
    await page.waitForTimeout(ms);
  } else if (act.type === 'wheel') {
    const [x, y, dy, ms = 500] = act.nums;
    await page.mouse.move(x, y);
    await page.mouse.wheel(0, dy);
    await page.waitForTimeout(ms);
  } else if (act.type === 'dragback') {
    // 한 번 누른 채 (dx,dy)만큼 갔다가 제자리로 돌아와 뗀다 — 탭으로 오인되면 안 되는 동작
    const [x, y, dx, dy, ms = 500] = act.nums;
    await page.mouse.move(x, y);
    await page.mouse.down();
    await page.mouse.move(x + dx, y + dy, { steps: 8 });
    await page.mouse.move(x, y, { steps: 8 });
    await page.mouse.up();
    await page.waitForTimeout(ms);
  } else if (act.type === 'until') {
    const deadlineMs = 240000;
    const start = Date.now();
    while (!logs.some((l) => l.includes(act.text))) {
      if (Date.now() - start > deadlineMs) {
        console.error(`--until timeout: no console message containing "${act.text}" within ${deadlineMs}ms`);
        await browser.close();
        process.exit(1);
      }
      await page.waitForTimeout(200);
    }
    await page.waitForTimeout(act.ms);
  }
}
await page.screenshot({ path: opt.out });
console.log(logs.join('\n'));
await browser.close();
