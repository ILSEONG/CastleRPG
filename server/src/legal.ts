// 이용약관·개인정보처리방침·계정 삭제 안내(2026-10-12, Google Play·앱인토스 등록용 공개 주소). 서버가 HTML로 준다:
//   /legal/terms · /legal/privacy · /legal/account-deletion  (예: https://castlerpg-api.onrender.com/legal/privacy)
// 앱은 scripts/support_links.gd의 같은 주소로 연다. 운영자(상호)·사업자등록번호는 main.ts 기본값(일성게임즈, 2026-10-14 사장님이 알려 줌),
// 환경 변수 LEGAL_OPERATOR·LEGAL_BIZ_NO·LEGAL_EMAIL로 바꿀 수 있다(저장소에 개인 연락처를 두지 않는다). 메일이 비면 "등록 예정".
// 문의는 이메일 없이 게임 안 [설정 → 문의하기](inquiry.ts, 2026-10-14)가 기본이고, LEGAL_EMAIL을 넣으면 함께 적는다.

export interface LegalInfo {
  operator: string // 운영자(개인 이름 또는 상호)
  email: string // 문의·개인정보 보호책임자 연락처
  bizNo?: string // 사업자등록번호
}

export const EFFECTIVE = '2026년 10월 12일'
export const GAME = 'CastleRPG'

export const INQUIRY = '게임 안 [설정 → 문의하기]'

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!)

function who(info: LegalInfo) {
  return {
    operator: esc(info.operator || `${GAME} 운영자`),
    biz: info.bizNo ? `<br>사업자등록번호: ${esc(info.bizNo)}` : '',
    email: info.email ? `<a href="mailto:${esc(info.email)}">${esc(info.email)}</a>` : '(연락처 등록 예정)',
    // 문의 창구(2026-10-14): 게임 안 [설정 → 문의하기](inquiry.ts). LEGAL_EMAIL을 넣으면 이메일도 함께 적는다.
    contact: INQUIRY + (info.email ? ` 또는 이메일 <a href="mailto:${esc(info.email)}">${esc(info.email)}</a>` : ''),
  }
}

function page(title: string, body: string): string {
  return `<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${GAME} ${title}</title><style>
body{margin:0;background:#f6f1e6;color:#1f2430;font-family:system-ui,-apple-system,"Apple SD Gothic Neo","Malgun Gothic",sans-serif;line-height:1.7}
main{max-width:760px;margin:0 auto;padding:28px 20px 60px}h1{font-size:24px;margin:0 0 4px}h2{font-size:18px;margin:28px 0 8px}
p,li{font-size:15px}table{border-collapse:collapse;width:100%;font-size:14px}td,th{border:1px solid #cfc6b3;padding:6px 8px;vertical-align:top;text-align:left}
input,select,textarea{box-sizing:border-box}th{background:#ece3cf}.date{color:#5b6478;font-size:14px;margin-bottom:20px}nav a{margin-right:14px;font-size:14px}
</style></head><body><main><nav><a href="/legal/terms">이용약관</a><a href="/legal/privacy">개인정보처리방침</a><a href="/legal/account-deletion">계정 삭제</a></nav>
<h1>${GAME} ${title}</h1><div class="date">시행일: ${EFFECTIVE}</div>${body}</main></body></html>`
}

export function termsPage(info: LegalInfo): string {
  const w = who(info)
  return page('이용약관', `
<h2>제1조 (목적)</h2>
<p>이 약관은 ${w.operator}(이하 "운영자")가 제공하는 모바일 게임 ${GAME}(Google Play 앱과 토스 앱 안 미니앱을 포함하며, 이하 "게임")의 이용 조건과 절차, 운영자와 이용자의 권리·의무를 정합니다.</p>
<h2>제2조 (약관의 효력과 변경)</h2>
<ol><li>이 약관은 게임 안 설정 화면과 이 페이지에 게시하며, 이용자가 게임에 로그인하면 약관에 동의한 것으로 봅니다.</li>
<li>운영자는 관련 법령을 어기지 않는 범위에서 약관을 바꿀 수 있습니다. 바꿀 때에는 시행일과 바뀌는 내용을 시행 7일 전(이용자에게 불리한 변경은 30일 전)부터 게임 안 공지나 이 페이지로 알립니다.</li>
<li>바뀐 약관에 동의하지 않으면 이용을 그만두고 계정을 삭제할 수 있습니다.</li></ol>
<h2>제3조 (계정)</h2>
<ol><li>게임은 별도 회원가입 없이 Google·카카오·네이버 계정, 토스 계정 또는 게스트(기기)로 시작합니다. 처음 로그인하면 게임 계정이 만들어집니다.</li>
<li>게스트 계정은 기기에만 연결되어 앱을 지우거나 기기를 바꾸면 복구할 수 없습니다. 설정에서 Google·카카오·네이버 계정을 연동하면 진행을 지킬 수 있습니다.</li>
<li>이용자는 자기 계정을 다른 사람에게 팔거나 빌려주거나 넘겨서는 안 됩니다.</li></ol>
<h2>제4조 (서비스의 제공과 변경)</h2>
<ol><li>게임은 연중 24시간 제공을 원칙으로 하지만, 점검·장애·서버 사정이 있으면 잠시 멈출 수 있습니다. 미리 알 수 있는 점검은 게임 안에서 미리 알립니다.</li>
<li>운영자는 게임 내용(캐릭터 능력치, 보상, 이벤트 등)을 운영상·기술상 필요에 따라 바꿀 수 있습니다.</li></ol>
<h2>제5조 (유료 상품과 결제)</h2>
<ol><li>다이아 충전, 월정액, 패키지, 패스 같은 유료 상품은 Google Play 결제(Google Play 앱) 또는 토스 인앱 결제(토스 미니앱)로 삽니다. 가격과 구성은 상점 화면에 표시합니다.</li>
<li>유료 상품은 결제가 확인되면 바로 계정에 지급됩니다. 결제 직후 앱이 꺼지는 등으로 지급되지 않은 결제는 다음 실행 때 다시 확인해 지급합니다.</li>
<li>게임 안 재화(다이아, 골드 등)와 아이템은 게임 안에서만 쓸 수 있고 현금으로 바꾸거나 환급할 수 없습니다. 이용자 사이의 현금 거래는 금지합니다.</li>
<li>확률로 결과가 정해지는 상품(영웅 모집 등)의 확률은 게임 안에 표시합니다.</li></ol>
<h2>제6조 (청약 철회와 환불)</h2>
<ol><li>이용자는 유료 상품을 산 날부터 7일 안에 청약을 철회할 수 있습니다. 다만 다음은 「전자상거래 등에서의 소비자보호에 관한 법률」에 따라 철회가 제한됩니다: 이미 사용했거나 일부를 사용한 상품(지급된 다이아를 쓴 경우 등), 구매 즉시 사용되거나 효과가 나타나는 상품(월정액 첫 지급분, 패키지 즉시 지급분 등). 이런 상품은 구매 화면에 그 사실을 표시합니다.</li>
<li>환불은 결제한 곳의 절차를 따릅니다. Google Play 결제는 Google Play의 환불 절차를, 토스 인앱 결제는 토스 앱의 '환불받기'를 이용합니다. 운영자에게 문의(${w.contact})해도 확인해 돕습니다.</li>
<li>환불된 결제로 받은 재화·아이템은 회수할 수 있으며, 환불을 악용한 경우 이용을 제한할 수 있습니다.</li>
<li>미성년자가 법정대리인의 동의 없이 결제한 경우 본인이나 법정대리인이 취소를 요청할 수 있습니다.</li></ol>
<h2>제7조 (이용자의 의무와 이용 제한)</h2>
<p>이용자는 다음 행위를 해서는 안 됩니다. 이를 어기면 운영자는 경고, 채팅 제한, 일시 정지, 영구 정지 등으로 이용을 제한할 수 있습니다.</p>
<ul><li>버그·해킹 도구·자동 조작 프로그램을 쓰거나 서버·통신을 조작해 부당한 이익을 얻는 행위</li>
<li>다른 사람의 계정을 쓰거나 개인정보를 모으는 행위</li>
<li>채팅에서 욕설, 음란·혐오·차별 표현, 도배, 광고, 사기, 다른 이용자를 괴롭히는 행위</li>
<li>게임 재화·아이템·계정의 현금 거래</li>
<li>법령이나 공공질서에 어긋나는 행위</li></ul>
<h2>제8조 (게시물과 신고)</h2>
<p>채팅 메시지 같은 이용자 게시물의 책임은 작성자에게 있습니다. 다른 이용자의 메시지를 신고할 수 있으며, 운영자는 신고된 내용을 확인해 조치합니다.</p>
<h2>제9조 (계정 삭제와 이용 종료)</h2>
<ol><li>이용자는 언제든지 게임 설정의 [계정 삭제]로 계정을 지울 수 있습니다. 지운 계정과 게임 진행·재화는 되살릴 수 없습니다.</li>
<li>운영자가 게임 서비스를 끝내려면 끝내는 날과 이유를 30일 전부터 게임 안에 알립니다.</li></ol>
<h2>제10조 (책임의 제한)</h2>
<p>운영자는 천재지변, 이용자의 귀책 사유, 통신사·플랫폼(Google, 토스 등)의 장애처럼 운영자가 막을 수 없는 사유로 생긴 손해는 책임지지 않습니다. 다만 운영자의 고의나 과실로 생긴 손해는 관련 법령에 따라 책임집니다.</p>
<h2>제11조 (분쟁 해결과 관할)</h2>
<p>게임 이용과 관련한 분쟁은 운영자와 이용자가 성실히 협의해 해결하며, 소송이 필요하면 민사소송법에 따른 관할 법원으로 합니다. 이 약관은 대한민국 법을 따릅니다.</p>
<h2>문의</h2>
<p>운영자(상호): ${w.operator}${w.biz}<br>문의: ${w.contact}</p>`)
}

export function privacyPage(info: LegalInfo): string {
  const w = who(info)
  return page('개인정보처리방침', `
<p>${w.operator}(이하 "운영자")는 「개인정보 보호법」에 따라 이용자의 개인정보를 보호하고, 관련 고충을 빠르게 처리하기 위해 다음과 같이 개인정보처리방침을 둡니다.</p>
<h2>1. 처리하는 개인정보 항목</h2>
<table><tr><th>구분</th><th>항목</th></tr>
<tr><td>게스트 로그인</td><td>앱이 만든 무작위 기기 식별값</td></tr>
<tr><td>Google 로그인</td><td>Google 계정 고유 식별자, 확인된 이메일 주소</td></tr>
<tr><td>카카오·네이버 로그인</td><td>각 서비스의 계정 고유 식별자(이름·이메일은 받지 않음)</td></tr>
<tr><td>토스(앱인토스) 로그인</td><td>토스가 이 게임 전용으로 발급하는 사용자 식별키(원문은 저장하지 않고 단방향 암호화 값만 저장)</td></tr>
<tr><td>게임 이용</td><td>자동 생성 닉네임, 게임 진행·재화·아이템 기록, 친구·길드 관계, 랭킹 기록</td></tr>
<tr><td>채팅</td><td>보낸 메시지와 시각, 신고 내용(신고된 메시지와 앞뒤 대화)</td></tr>
<tr><td>결제</td><td>주문 번호, 상품, 결제 시각(카드번호 등 결제 수단 정보는 Google·토스가 처리하며 운영자는 받지 않음)</td></tr>
<tr><td>자동 수집</td><td>접속 IP 주소, 접속 시각, 서버 오류 기록</td></tr></table>
<h2>2. 처리 목적</h2>
<ul><li>계정 생성·로그인과 게임 진행 저장, 기기 변경 시 진행 이어가기</li>
<li>유료 상품 결제 확인과 지급, 환불 처리, 부정 결제 방지</li>
<li>채팅·친구·길드·랭킹 같은 이용자 간 기능 제공, 신고 처리와 부정 이용 제재</li>
<li>서비스 장애 대응, 보안, 통계적 분석을 통한 게임 개선</li></ul>
<h2>3. 보유 기간</h2>
<ul><li>계정 정보와 게임 기록: 계정을 삭제할 때까지. 삭제하면 바로 파기합니다.</li>
<li>결제 기록(주문 번호·상품·시각): 「전자상거래 등에서의 소비자보호에 관한 법률」에 따라 5년</li>
<li>채팅 신고 기록: 신고 처리와 분쟁 대응을 위해 1년</li>
<li>접속 기록(IP·시각): 「통신비밀보호법」에 따라 3개월</li>
<li>1년 동안 접속하지 않은 계정은 미리 알린 뒤 개인정보를 분리 보관하거나 파기할 수 있습니다.</li></ul>
<h2>4. 제3자 제공</h2>
<p>운영자는 이용자의 개인정보를 제3자에게 제공하지 않습니다. 다만 법령에 따라 수사기관이 적법한 절차로 요청하는 경우는 예외입니다.</p>
<h2>5. 처리 위탁과 국외 이전</h2>
<table><tr><th>받는 곳</th><th>위탁 업무</th><th>이전 국가·방법</th><th>항목·기간</th></tr>
<tr><td>Render Services, Inc.</td><td>게임 서버 운영</td><td>싱가포르 데이터센터, 이용 시 네트워크로 전송</td><td>1번의 전체 항목, 위탁 계약 종료 또는 보유 기간 끝까지</td></tr>
<tr><td>Neon, Inc.(Databricks)</td><td>게임 데이터베이스 보관</td><td>싱가포르(ap-southeast-1) 데이터센터, 네트워크로 전송</td><td>1번의 전체 항목, 위탁 계약 종료 또는 보유 기간 끝까지</td></tr>
<tr><td>Google LLC</td><td>Google 로그인, Google Play 결제</td><td>미국 등, 로그인·결제 때 전송</td><td>계정 식별자·이메일·주문 정보, Google 정책에 따름</td></tr>
<tr><td>(주)카카오, 네이버(주)</td><td>소셜 로그인</td><td>대한민국</td><td>계정 식별자, 각 회사 정책에 따름</td></tr>
<tr><td>(주)비바리퍼블리카(토스)</td><td>토스 로그인, 토스 인앱 결제</td><td>대한민국</td><td>사용자 식별키·주문 정보, 토스 정책에 따름</td></tr></table>
<p>국외 이전을 원하지 않으면 계정을 삭제해 이전을 멈출 수 있습니다. 다만 게임 서버가 국외에 있어 게임을 이용할 수 없게 됩니다.</p>
<h2>6. 파기 절차와 방법</h2>
<p>보유 기간이 끝나거나 계정을 삭제하면 데이터베이스에서 지체 없이 지웁니다. 법령에 따라 보관하는 결제 기록은 다른 정보와 분리해 보관한 뒤 기간이 끝나면 지웁니다.</p>
<h2>7. 이용자의 권리</h2>
<p>이용자는 언제든지 자기 개인정보의 열람, 정정, 삭제, 처리 정지를 요구할 수 있습니다. 게임 설정의 [계정 삭제]로 바로 삭제할 수 있고, 그 밖의 요구는 아래 문의 창구로 하면 10일 안에 처리합니다. 만 14세 미만 아동의 법정대리인도 같은 권리를 가집니다.</p>
<h2>8. 안전성 확보 조치</h2>
<ul><li>모든 통신은 HTTPS(TLS)로 암호화합니다.</li>
<li>자동 로그인 비밀값과 토스 식별키는 원문 대신 단방향 암호화(SHA-256) 값만 저장합니다.</li>
<li>데이터베이스 접근은 운영자에게만 허용하고 접속 정보는 암호화된 환경 변수로 관리합니다.</li></ul>
<h2>9. 자동 수집 장치</h2>
<p>게임은 쿠키나 광고 식별자를 쓰지 않습니다. 기기 안에는 로그인 상태와 설정(소리, 화면 흔들림 등)만 저장합니다.</p>
<h2>10. 만 14세 미만 아동</h2>
<p>게임은 만 14세 미만 아동의 개인정보를 일부러 수집하지 않습니다. 만 14세 미만 아동이 가입한 사실을 알게 되면 법정대리인의 동의를 받거나 그 정보를 지웁니다.</p>
<h2>11. 개인정보 보호책임자</h2>
<p>개인정보처리자(상호): ${w.operator}${w.biz}<br>개인정보 보호책임자: ${w.operator}<br>문의: ${w.contact}</p>
<p>개인정보 침해 신고·상담: 개인정보침해신고센터(privacy.kisa.or.kr, 국번 없이 118), 개인정보 분쟁조정위원회(www.kopico.go.kr, 1833-6972), 대검찰청 사이버수사과(www.spo.go.kr, 1301), 경찰청 사이버수사국(ecrm.police.go.kr, 182)</p>
<h2>12. 방침의 변경</h2>
<p>이 방침을 바꾸면 시행 7일 전부터 이 페이지와 게임 안에 알립니다.</p>`)
}

// 앱 없이 삭제 요청 양식(2026-10-14): POST /legal/account-deletion → 문의 표(category 'delete', inquiry.ts)에 쌓이고
// 관리자가 운영 관리 [문의] 탭에서 확인한 뒤 [계정 삭제]로 지운다(자동 삭제 없음). website 칸은 자동 입력 막기용(사람에게 안 보임).
function deletionForm(error: string): string {
  const opt = (v: string, t: string) => `<option value="${v}">${t}</option>`
  return `<form method="post" action="/legal/account-deletion" style="background:#fffaf0;border:1px solid #cfc6b3;border-radius:10px;padding:14px 16px">
${error ? `<p style="color:#b03a2e;margin-top:0">${esc(error)}</p>` : ''}
<p style="margin-top:0"><label>친구 코드(설정 화면에 보이는 8자리)<br><input name="code" maxlength="8" autocomplete="off" style="width:100%;font-size:16px;padding:6px"></label></p>
<p><label>로그인 방식<br><select name="login" style="width:100%;font-size:16px;padding:6px">${opt('', '선택')}${opt('google', 'Google')}${opt('kakao', '카카오')}${opt('naver', '네이버')}${opt('toss', '토스')}${opt('guest', '게스트')}</select></label></p>
<p><label>Google 로그인 이메일(Google로 로그인했다면, 본인 확인용)<br><input name="email" type="email" maxlength="120" style="width:100%;font-size:16px;padding:6px"></label></p>
<p><label>삭제 사유(선택)<br><textarea name="reason" maxlength="500" rows="3" style="width:100%;font-size:15px;padding:6px"></textarea></label></p>
<p style="display:none"><label>website<input name="website" tabindex="-1" autocomplete="off"></label></p>
<p style="font-size:13px;color:#5b6478">친구 코드나 Google 이메일 중 하나는 꼭 적어 주세요. 적은 내용은 삭제 요청 확인에만 쓰고, 처리가 끝나면 삭제 처리 기록으로만 남깁니다.</p>
<button type="submit" style="font-size:16px;padding:8px 18px">삭제 요청 보내기</button></form>`
}

export function deletionFormPage(info: LegalInfo, error: string): string {
  const w = who(info)
  return page('계정 삭제 요청', `${deletionForm(error)}<p>운영자(상호): ${w.operator}${w.biz}</p>`)
}

export function deletionDonePage(info: LegalInfo): string {
  const w = who(info)
  return page('계정 삭제 요청', `<p><b>삭제 요청을 받았어요.</b></p>
<p>운영자가 본인 계정인지 확인한 뒤 10일 안에 삭제합니다. 삭제되면 같은 로그인으로 들어갔을 때 새 계정으로 시작됩니다.</p>
<p><a href="/legal/account-deletion">계정 삭제 안내로 돌아가기</a></p><p>운영자(상호): ${w.operator}${w.biz}</p>`)
}

export function deletionPage(info: LegalInfo): string {
  const w = who(info)
  return page('계정 삭제 안내', `
<h2>게임 안에서 바로 삭제하기</h2>
<ol><li>${GAME}를 열고 오른쪽 아래 [메뉴] → [설정]으로 갑니다.</li>
<li>[계정] 칸의 [계정 삭제]를 누르고, "한 번 더 누르면 계정이 삭제됩니다"가 보이면 한 번 더 누릅니다.</li>
<li>계정과 게임 진행, 재화, 아이템, 친구·길드 관계, 채팅 기록이 바로 지워지며 되살릴 수 없습니다.</li></ol>
<h2>앱 없이 삭제 요청하기</h2>
<p>앱을 지웠거나 열 수 없으면 아래 양식으로 요청해 주세요. 운영자가 본인 계정인지 확인한 뒤 10일 안에 삭제합니다. 삭제되면 같은 로그인으로 들어갔을 때 새 계정으로 시작됩니다.</p>
${deletionForm('')}
<h2>지워지는 것과 남는 것</h2>
<ul><li>지워지는 것: 계정 식별 정보(로그인 연결, 이메일, 기기 식별값), 게임 진행·재화·아이템, 친구·길드, 채팅 메시지, 랭킹 기록</li>
<li>법령에 따라 남는 것: 결제 기록(주문 번호·상품·시각) 5년, 채팅 신고 기록 1년, 접속 기록 3개월. 기간이 끝나면 지웁니다.</li>
<li>앱 없이 보낸 삭제 요청은 처리 기록(요청 내용·처리 시각)으로 1년 보관한 뒤 지웁니다.</li></ul>
<p>운영자(상호): ${w.operator}${w.biz}</p>`)
}
