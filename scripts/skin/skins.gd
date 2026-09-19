extends Node
## 当前使用的素材包（autoload 单例 Skins）。
## 启动时读取项目设置 game/skin 指定的包；运行中可以用 use() 切换。

signal skin_changed(skin: SkinPack)

const SETTING := "game/skin"
const DEFAULT_SKIN := "res://skins/default/default_skin.tres"

var current: SkinPack


func _ready() -> void:
	use(load(ProjectSettings.get_setting(SETTING, DEFAULT_SKIN)) as SkinPack)


func use(skin: SkinPack) -> void:
	current = skin
	skin_changed.emit(skin)


## 默认包。测试和自制素材包的 fallback 都会用到。
func default_skin() -> SkinPack:
	return load(DEFAULT_SKIN) as SkinPack


func sound(event: StringName) -> AudioStream:
	return current.find_sound(event) if current != null else null
