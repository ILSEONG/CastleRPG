@tool
extends EditorPlugin
## 안드로이드 내보내기(그래들 빌드)에 CastleAds 플러그인 AAR, Google Mobile Ads SDK, 광고 앱 ID를 넣는다.
## AAR 소스: android_plugins/castle_ads (빌드: android_plugins/castle_ads/build.sh). 광고 ID: scripts/ad_config.gd.

var _export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	const PLUGIN_NAME := "CastleAds"
	const AdConfig := preload("res://scripts/ad_config.gd")
	## res://addons/ 기준 경로. 디버그·출시 모두 같은 AAR을 쓴다.
	const AAR_PATH := "castle_ads/bin/castle_ads-release.aar"
	## android_plugins/castle_ads/build.gradle 의 adsVersion 과 맞출 것.
	const ADS_DEP := "com.google.android.gms:play-services-ads:24.5.0"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([AAR_PATH])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([ADS_DEP])

	## AdMob SDK는 앱 ID 메타데이터가 없으면 시작하자마자 앱을 멈춘다 — 꼭 넣는다.
	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return '<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="%s" />\n' % AdConfig.ANDROID_APP_ID

	func _get_name() -> String:
		return PLUGIN_NAME
