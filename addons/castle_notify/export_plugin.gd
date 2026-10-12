@tool
extends EditorPlugin
## 안드로이드 내보내기에 알림 플러그인 AAR(bin/castle_notify-release.aar)을 넣는다. Gradle 빌드(export_presets use_gradle_build)가 필요하다.
## 게임에서는 싱글턴 "CastleNotify"로 보인다(scripts/notify.gd). 웹(앱인토스)·PC 빌드에는 들어가지 않는다.

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = NotifyExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class NotifyExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "CastleNotify"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["castle_notify/bin/castle_notify-release.aar"])
