extends RefCounted
## 약관 주소(2026-10-12). 문의는 이메일 없이 게임 안 문의 창(inquiry_panel.gd, 2026-10-14). 설정 창 [이용약관]·[개인정보처리방침]·[문의하기]와 로그인 화면 아래 링크가 쓴다.
## 문서를 올리고 주소를 정하는 일은 출시(스토어) 작업 몫 — 여기 상수만 채우면 된다. 비어 있으면 버튼은 "준비 중" 알림만 띄운다.

const Lang := preload("res://scripts/lang.gd")

const TERMS_URL := "https://castlerpg-api.onrender.com/legal/terms"  # 이용약관(서버 server/src/legal.ts가 그린다)
const PRIVACY_URL := "https://castlerpg-api.onrender.com/legal/privacy"  # 개인정보처리방침
const DELETION_URL := "https://castlerpg-api.onrender.com/legal/account-deletion"  # 계정 삭제 안내(Play Console "계정 삭제 요청 웹 주소"용 — 앱에서는 쓰지 않는다)
static var NOT_READY := Lang.t("support_links.not_ready")
