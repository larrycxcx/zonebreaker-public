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
	&"enemy_prone": "敌人（C、炮台）跟着玩家趴下",
	&"chaser_alert": "D 发现玩家、开始冲锋",
	&"bullet_impact": "任何子弹撞到墙、地面、矮通道等实心物体",
	&"game_over": "玩家死亡后出现 GAME OVER",
}

## 在编辑器里显示的名字。
@export var display_name := ""
## 事件名 → 声音。
@export var sounds: Dictionary[StringName, AudioStream] = {}
## 这个包里没有的声音去哪里找。自制素材包一般指向默认包；默认包自己留空。
@export var fallback: SkinPack


## 找某个事件的声音：先看自己，没有再问备用包，都没有返回 null。
func find_sound(event: StringName) -> AudioStream:
	var stream: AudioStream = sounds.get(event)
	if stream != null:
		return stream
	return fallback.find_sound(event) if fallback != null else null
