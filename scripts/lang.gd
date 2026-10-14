extends RefCounted
## 게임 문구(다국어). Lang.t("키") → 지금 언어의 문장. 쓰는 쪽은 `const Lang := preload("res://scripts/lang.gd")`.
## 원본은 DB texts 표(키 · ko · en · ja · zh) — 서버 GET /v1/texts로 받는다(Net). 앱에는 같은 내용의 data/texts.csv가 들어 있어
## 서버에 닿기 전(로딩·오프라인·느린 서버)에도 키가 화면에 나오지 않는다. 마지막으로 받은 표는 user://에 두어 다음 실행이 처음부터 쓴다.
## 그 언어 칸이 비면 한국어(ko). 표에 없는 키는 키 그대로(빠진 문구가 바로 보이게).
## 조회는 사전 한 번(매 프레임 불러도 된다). 새 문구 넣는 법: docs/TEXTS.md

const PATH := "res://data/texts.csv"
const CACHE_PATH := "user://texts_cache.json"
const LANGS := ["ko", "en", "ja", "zh"]
const DEFAULT_LANG := "ko"

static var lang := DEFAULT_LANG
static var version := ""  # 마지막으로 받은 서버 표 버전("" = 앱에 든 표)
static var _map: Dictionary = {}
static var _loaded := false


## 키 → 문장. 형식 문자열("골드 %d")은 그대로 돌려준다 — 부르는 쪽이 % 로 채운다.
static func t(key: String) -> String:
	if not _loaded:
		_load()
	var v = _map.get(key)
	return key if v == null else v


static func has(key: String) -> bool:
	if not _loaded:
		_load()
	return _map.has(key)


## 서버 /v1/texts 응답 {version, lang, texts: {키: 문장}}을 덮어쓴다(빠진 키는 앱 표 값을 그대로 둔다). 다음 실행용으로 저장.
static func apply_remote(data: Dictionary) -> bool:
	var texts = data.get("texts")
	if not (texts is Dictionary) or str(data.get("lang", lang)) != lang:
		return false
	if not _loaded:
		_load()
	for k in texts:
		if texts[k] is String:
			_map[str(k)] = texts[k]
	version = str(data.get("version", ""))
	var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": version, "lang": lang, "texts": texts}))
	return true


static func _load() -> void:
	_loaded = true
	_map = read_csv(PATH, lang)
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var cached = JSON.parse_string(FileAccess.get_file_as_string(CACHE_PATH))
	if cached is Dictionary and str(cached.get("lang", "")) == lang and cached.get("texts") is Dictionary:
		for k in cached.texts:
			if cached.texts[k] is String:
				_map[str(k)] = cached.texts[k]
		version = str(cached.get("version", ""))


## data/texts.csv → {키: 그 언어 문장(비면 ko)}. 값의 \n = 줄바꿈, \\ = 역슬래시.
static func read_csv(path: String, want: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("texts: cannot open " + path)
		return out
	var head := f.get_csv_line()
	var ki := head.find("key")
	var ko := head.find(DEFAULT_LANG)
	var li := head.find(want)
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() <= maxi(ki, ko) or row[ki].is_empty():
			continue
		var v := row[li] if li >= 0 and li < row.size() and not row[li].is_empty() else row[ko]
		out[row[ki]] = unescape(v)
	return out


static func unescape(s: String) -> String:
	if s.find("\\") < 0:
		return s
	var out := ""
	var i := 0
	while i < s.length():
		var c := s[i]
		if c == "\\" and i + 1 < s.length():
			var n := s[i + 1]
			match n:
				"n": out += "\n"
				"t": out += "\t"
				"r": out += "\r"
				"\\": out += "\\"
				_: out += c + n
			i += 2
		else:
			out += c
			i += 1
	return out
