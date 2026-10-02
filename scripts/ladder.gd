@tool
class_name Ladder
extends Node2D
## 梯子（2026-10 加的）：连通上下两层。**节点原点是梯子顶的正中**——也就是上面那一层地板的表面，
## 梯子从这儿往下伸 `height`，底端落在下面那一层的地板上。
##
## - 玩家在梯子前按「上」（或者站在梯子顶上按「下」）就抓住，上下爬，不受重力、**不能开枪**；
##   爬到顶就站上去，爬到底落地就松手；按跳跃是跳下来（带左右方向就往那边跳出去）。见 `Player._climb()`。
## - **梯子顶上自带一小块单向平台**（`cap`）：上面那层地板在梯子这儿留了个洞，
##   不盖住的话走过去就掉下去了；盖成单向的，站在上面按「下」才顺着梯子下去。
##   它是看不见的——画面上就是梯子顶，盖子只是规则。
## - 敌人不爬梯子（它们巡逻时梯子不算墙，直接走过去）。
## - 纯规则在本体上（`grab_rect()`、`top_y()`、`bottom_y()`），长什么样交给 `Visual`（`LadderAppearance`）。

const GROUP := &"ladders"
## 盖子多宽（就是上面那层地板留的洞）：比人宽（24）一点，人顺着梯子能穿过去。
const CAP_WIDTH := 32.0
const CAP_THICK := 16.0

@export var height := 96.0:
	set(value):
		height = value
		_apply()
## 梯子多宽（判定）：人的身体中心离梯子中线这么近才抓得住。
@export var width := 24.0
@export var skin_key := &"ladder"
## 顶上要不要盖子（梯子顶伸出地面、上面不是一层地板的话就不用）。
@export var cap := true

var _visual: Node
var _cap: Platform


func _ready() -> void:
	add_to_group(GROUP)
	if not Engine.is_editor_hint():
		_visual = Skins.build_appearance(self, skin_key)
		if cap:
			_cap = (load("res://scenes/platform.tscn") as PackedScene).instantiate() as Platform
			_cap.name = "Cap"
			_cap.one_way = true
			_cap.size = Vector2(CAP_WIDTH, CAP_THICK)
			_cap.position = Vector2(-CAP_WIDTH / 2.0, 0.0)
			_cap.visible = false
			add_child(_cap)
	_apply()


func _apply() -> void:
	if not is_node_ready():
		return
	var visual := _visual if _visual != null else get_node_or_null("Visual")
	if visual != null and visual.has_method(&"fit"):
		visual.call(&"fit", Vector2(width, height))


## 顶上那一块盖子（人顺着梯子穿过它时要临时忽略碰撞）。
func cap_body() -> Platform:
	return _cap


func top_y() -> float:
	return global_position.y


func bottom_y() -> float:
	return global_position.y + height


## 抓得住的范围（世界坐标）：中线左右各一半宽，从顶到底。
func grab_rect() -> Rect2:
	return Rect2(global_position.x - width / 2.0, top_y(), width, height)
