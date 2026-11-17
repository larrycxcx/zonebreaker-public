class_name LevelInfo
extends Resource
## 一个关卡的名片：场景在哪、叫什么、排第几。
##
## 关卡清单是**扫 `levels/` 目录**得来的（见 `Catalog`），所以加一关 = 往那儿丢一个 `.tres`
## 加一个场景，主程序一行都不用改——DLC 也走同一条路。
##
## 以后要加的字段（推荐等级、通关奖励、下一关是谁）也加在这里，不要再散回代码里。

## 关卡场景的路径。**存路径不存 PackedScene**：存资源的话这个 `.tres` 会把整关拖进内存，
## 而菜单只是想知道有哪些关。
@export_file("*.tscn") var scene_path := ""
## 界面上怎么称呼它（一律英文大写，素材包的字模没有汉字）。
@export var display_name := ""
## 排第几。**不按文件名排**：按文件名排的话 DLC 加一关会插到中间去。
@export var order := 0
## 推荐等级：低于它进来会很吃力。界面上给玩家看，规则上不拦人。
@export var recommended_level := 1

## 这一关用哪套素材：地砖、背景、关卡音乐、Boss 音乐、这一关敌人的贴图，全在里面。
## **每关一个包**——23 关的场景、敌人、Boss、音乐各不相同，共用一个包的话只能共用一张背景。
## 包之间用 `SkinPack.fallback` 串起来：`zone_02` 里没填的（角色、子弹、特效、HUD、界面）
## 自动去公共包找，所以每关的包只装「这一关独有的」。
## 留空 = 不换，用项目设置里那个（测试关就是这一档）。
## **存路径不存资源**：包是第三方素材，公开版里没有。直接引用的话这个 `.tres` 整个读不出来、
## 选关页上这一关就没了；存路径的话包不在时 `skin` 是 null，关卡照样能玩（用占位的默认皮肤）。
@export_file("*.tres") var skin_path := ""
## 包本身：路径有文件才加载。也可以直接塞一个（测试用）。
var skin: SkinPack:
	get:
		if _skin == null and not skin_path.is_empty() and ResourceLoader.exists(skin_path):
			_skin = load(skin_path) as SkinPack
		return _skin
	set(value):
		_skin = value
var _skin: SkinPack

@export_group("强度")
## 这一关的敌人血量 / 伤害 / 奖励各乘多少。**23 关用同一批敌人**，靠这三个数拉开强度，
## 不为每关重做一套敌人场景（见 `Stage`）。
## **正式关卡默认都是 1.0**：每关的敌人本来就不一样，血量伤害直接写在各自的敌人场景里。
## 这三个数是给**难度 DLC** 用的——同一关、同样的素材、同一批敌人，只把倍率调高，
## 玩家拿现有角色重打一遍（Hard、Hell）。那种 DLC 只有一堆几 KB 的 `.tres`，贴图一张都不用重发。
@export var enemy_health_scale := 1.0
@export var enemy_damage_scale := 1.0
@export var reward_scale := 1.0
