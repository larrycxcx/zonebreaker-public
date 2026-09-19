extends Node
## 游戏事件总线（autoload 单例 GameEvents）。
## 玩法代码只在这里报告「发生了什么」（GameEvents.report(&"jump", self)），不管声音、特效怎么表现；
## 音效播放器 Sfx 监听它，第 3 步的命中特效、屏幕抖动也可以接在这里。
## 事件名见 SkinPack.SOUND_EVENTS。

signal event_happened(event: StringName, source: Node)
## Boss 出场（第一次进入屏幕）。HUD 靠它在右上角显示头像和血条；Boss 可能是关卡进行中才生成的，所以走总线。
signal boss_appeared(boss: Node2D)


func report(event: StringName, source: Node = null) -> void:
	event_happened.emit(event, source)
