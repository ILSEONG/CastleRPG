@tool
extends EditorPlugin
## 안드로이드 내보내기(그래들 빌드)에 CastleBilling 플러그인 AAR과 Google Play 결제 라이브러리를 넣는다.
## AAR 소스: android_plugins/castle_billing (빌드: android_plugins/castle_billing/build.sh).

var _export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	const PLUGIN_NAME := "CastleBilling"
	## res://addons/ 기준 경로. 디버그·출시 모두 같은 AAR을 쓴다.
	const AAR_PATH := "castle_billing/bin/castle_billing-release.aar"
	## android_plugins/castle_billing/build.gradle 의 billingVersion 과 맞출 것.
	const BILLING_DEP := "com.android.billingclient:billing:8.3.0"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([AAR_PATH])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray([BILLING_DEP])

	## 소셜 로그인 복귀 링크(2026-10-15): 브라우저 로그인이 끝나면 서버가 castlerpg://oauth(intent://)로 보내 게임 앱을 앞으로 부른다
	## (server/src/oauth.ts appReturnUrl). GodotApp은 exported=false라 별칭으로 연다 — singleInstancePerTask라 켜져 있던 게임으로 돌아간다.
	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return """<activity-alias android:name="com.godot.game.OAuthReturn" android:targetActivity="com.godot.game.GodotApp" android:exported="true">
	<intent-filter>
		<action android:name="android.intent.action.VIEW" />
		<category android:name="android.intent.category.DEFAULT" />
		<category android:name="android.intent.category.BROWSABLE" />
		<data android:scheme="castlerpg" android:host="oauth" />
	</intent-filter>
</activity-alias>
"""

	func _get_name() -> String:
		return PLUGIN_NAME
