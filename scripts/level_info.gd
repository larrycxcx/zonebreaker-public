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

@export_group("强度")
## 这一关的敌人血量 / 伤害 / 奖励各乘多少。**23 关用同一批敌人**，靠这三个数拉开强度，
## 不为每关重做一套敌人场景（见 `Stage`）。
## 规划：血量每关 ×1.10、伤害 ×1.05、奖励 ×1.12——到第 23 关分别是 ×8.1、×2.9、×11。
@export var enemy_health_scale := 1.0
@export var enemy_damage_scale := 1.0
@export var reward_scale := 1.0
