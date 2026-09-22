class_name SkinPack
extends Resource
## 素材包：一套可整体替换的游戏素材。目前只有音效，第 4 步会把贴图、背景、音乐也加进来。
##
## 新建一个素材包：在编辑器里新建 SkinPack 资源（.tres），`fallback` 指向默认包
## （res://skins/default/default_skin.tres），然后只在 `sounds` 里填想替换的事件——
## 没填的事件自动沿用备用包的声音。再把项目设置 game/skin 指向新的 .tres 即可。
## 同一个事件想要多个变体轮流/随机播放，用 AudioStreamRandomizer 当那个声音（默认包的 player_shoot 就是这样）。

## 游戏会发出的全部音效事件，以及什么时候触发。这是素材包的「接口约定」：
## 做素材的人照这个清单准备声音；test_audio.gd 会检查默认包覆盖了这里的每一项，
## 并且每一项都真的会在游戏里被触发。加新事件时两边一起改。
const SOUND_EVENTS := {
	&"player_shoot": "玩家每开一枪",
	&"jump": "玩家起跳",
	&"player_hurt": "玩家掉血（没死）",
	&"player_death": "玩家血量归零",
	&"stamina_exhausted": "玩家体力跑光",
	&"enemy_shoot": "巡逻兵 A/B/C 开枪（每颗子弹一次，B 连发时响多次）",
	&"turret_shoot": "炮台开火",
	&"flyer_shoot": "E 往下开火",
	&"enemy_hit": "敌人被打中但没死",
	&"enemy_death": "敌人被消灭",
	&"enemy_prone": "敌人 C 跟着玩家趴下（炮台不会趴下）",
	&"chaser_alert": "D 发现玩家、开始冲锋",
	&"bullet_impact": "任何子弹撞到墙、地面、矮通道等实心物体",
	&"game_over": "玩家死亡后出现 GAME OVER",
	&"grenade_throw": "玩家扔出一颗手雷",
	&"grenade_bounce": "手雷撞到地面或墙弹起来",
	&"explosion": "手雷爆炸",
	&"weapon_switch": "玩家切换武器",
	&"ultimate_start": "玩家发动终极武器（定格开始）",
	&"ultimate_blast": "终极武器消灭屏幕内的敌人（定格结束）",
	&"boss_appear": "Boss 出场（第一次进入屏幕）",
}

## 全部角色外观的键，以及各是谁。做素材的人照这张表准备外观场景（根节点挂 Appearance 脚本）。
## 自制包只填想替换的；没填的角色用它自己场景里带的默认外观（现在的占位方块）。
const APPEARANCE_KEYS := {
	&"player": "玩家",
	&"walker": "巡逻兵的基础场景（关卡里不直接放，放的是下面三种）",
	&"walker_a": "巡逻兵 A（只打水平）",
	&"walker_b": "巡逻兵 B（连发，会斜射）",
	&"walker_c": "巡逻兵 C（射程远，会斜射、会趴下）",
	&"grenadier": "敌人 F（扔手雷的巡逻兵）",
	&"turret": "炮台",
	&"flyer": "敌人 E（飞行）",
	&"chaser": "敌人 D（追击）",
	&"boss_a": "Boss A",
	# 发射物（外观根节点同样挂 Appearance；子弹会收到 aim(飞行方向)，素材包按方向挑贴图，见 ProjectileAppearance）
	&"player_bullet": "玩家的子弹",
	&"enemy_bullet": "敌人的子弹（巡逻兵）",
	&"boss_bullet": "Boss A 导弹扇形的子弹",
	&"turret_bullet": "炮台的炮弹",
	&"flyer_bullet": "E 往下打的子弹",
	&"player_grenade": "玩家的手雷",
	&"enemy_grenade": "F 打出来的手雷",
	# 地形（平台 platform.tscn 用；外观场景根节点挂 TerrainAppearance 这类有 fit(大小) 的外观）
	&"terrain_ground": "地面",
	&"terrain_ledge": "浮空的单向平台",
	&"terrain_stone": "墙、矮通道顶块这类实心块",
}

## 全部特效的键。没填的用 Fx 节点上配的默认场景。
const EFFECT_KEYS := {
	&"muzzle_flash": "开枪时的枪口闪光",
	&"hit_spark": "子弹打中角色",
	&"impact_spark": "子弹打在墙、地面上",
	&"explosion": "手雷爆炸",
}

## 在编辑器里显示的名字。
@export var display_name := ""
## 事件名 → 声音。
@export var sounds: Dictionary[StringName, AudioStream] = {}
## 角色外观：皮肤键（`APPEARANCE_KEYS`）→ 外观场景，根节点要挂 `Appearance` 脚本。
@export var appearances: Dictionary[StringName, PackedScene] = {}
## 特效：特效键（`EFFECT_KEYS`）→ 场景。
@export var effects: Dictionary[StringName, PackedScene] = {}
## 关卡背景（视差滚动的几层画，纯显示）。留空就没有背景，用项目的清屏色。
@export var backdrop: PackedScene
## HUD 外观（根节点挂 SpriteHud 这类有 show_health / show_stamina / … 的脚本）。留空就用 HUD 自带的占位方块。
@export var hud: PackedScene
## 这个包里没有的东西去哪里找。自制素材包一般指向默认包；默认包自己留空。
@export var fallback: SkinPack


## 找某个事件的声音：先看自己，没有再问备用包，都没有返回 null。
func find_sound(event: StringName) -> AudioStream:
	var stream: AudioStream = sounds.get(event)
	if stream != null:
		return stream
	return fallback.find_sound(event) if fallback != null else null


## 找某个角色的外观场景：先看自己，没有再问备用包，都没有返回 null（= 用角色场景里自带的）。
func find_appearance(key: StringName) -> PackedScene:
	var scene: PackedScene = appearances.get(key)
	if scene != null:
		return scene
	return fallback.find_appearance(key) if fallback != null else null


## 找背景场景：先看自己，没有再问备用包。
func find_backdrop() -> PackedScene:
	if backdrop != null:
		return backdrop
	return fallback.find_backdrop() if fallback != null else null


## 找 HUD 外观：先看自己，没有再问备用包。
func find_hud() -> PackedScene:
	if hud != null:
		return hud
	return fallback.find_hud() if fallback != null else null


## 找某个特效的场景，规则同上。
func find_effect(key: StringName) -> PackedScene:
	var scene: PackedScene = effects.get(key)
	if scene != null:
		return scene
	return fallback.find_effect(key) if fallback != null else null
