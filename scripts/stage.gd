class_name Stage
extends RefCounted
## 「现在打的是哪一关」——敌人按它缩放强度，奖励按它缩放。
##
## 23 关用的是**同一批敌人**，靠每关一组倍率拉开强度（`LevelInfo` 里的三个 scale），
## 不为每关重做一套敌人场景。所以难度 DLC 也很便宜：同样的场景，另一套 `LevelInfo` 换倍率就行。
##
## **是个静态变量，不是 autoload**：它只是一份数据，没有信号也不进场景树。
## 关卡加载之前由 `MainMenu`（或测试）设好；没设就是 null，所有倍率都是 1——
## 测试关（`main.tscn`）跑的就是这一档，老测试因此一条都不用改。

## 正在打的那一关。null = 没设（测试关、或者直接加载场景调试）。
static var current: LevelInfo


## 换一关（**关卡加载之前**调）。这一关配了素材包就顺手换上：
## 地砖、背景、音乐、敌人贴图都从包里来，而敌人和平台在各自的 `_ready` 里就要问包要外观，
## 所以必须赶在场景实例化之前换好。没配包就不动（用项目设置里那个）。
static func use(level: LevelInfo) -> void:
	current = level
	if level != null and level.skin != null:
		Skins.use(level.skin)


## 回到「没有关卡」的状态：所有倍率都是 1。
static func clear() -> void:
	current = null


static func health_scale() -> float:
	return current.enemy_health_scale if current != null else 1.0


static func damage_scale() -> float:
	return current.enemy_damage_scale if current != null else 1.0


static func reward_scale() -> float:
	return current.reward_scale if current != null else 1.0
