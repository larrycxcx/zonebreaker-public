class_name CameraRig
extends ScreenShake
## 关卡的摄像机：跟着玩家走，并且**不让任何一个玩家被挤出画面**（魂斗罗式）。
##
## 挂在关卡上，不是挂在玩家身上——双人时两个人共用一台摄像机，镜头跟的是**两人的中点**。
## 单人时中点就是那个玩家本人，所以画面和以前一模一样（老测试靠这个继续守着）。
##
## 每一物理帧做两件事，顺序不能反：先把镜头挪到中点（受关卡边界限制），
## 再把还活着的玩家夹回画面里。夹的那一下会把落在后面的人往前拖，这正是魂斗罗的规矩：
## 谁也不能把队友甩出屏幕，想分头走就只能走到画面两边为止。
##
## 这个节点的 `process_physics_priority` 调得很高，好让它在所有玩家都走完之后才跑。
##
## **纵向关（`only_up`）**：画面只往上卷、不往回退（魂斗罗瀑布关那种）。做法是让 `limit_bottom`
## **只降不升**——画面往上走一点，下边界就跟着收紧，引擎自己会把画面夹住，不用另写一套跟随。
## 这时镜头跟的是**爬得最高的那个人**而不是两人中点：领头的往上爬，落后的被甩出底边，
## 掉出底边就按掉坑算（`main.gd` 的判定线跟着画面底边走），捞回到画面里（`Player.fall_out()`）。

## 玩家身体离画面边缘至少留这么远（半个身宽多一点，整个人都看得见）。
const EDGE_MARGIN := 14.0
## 关卡里那台摄像机在这个分组里：玩家捞回、关卡判定掉坑都要问它画面在哪儿。
const GROUP := &"camera_rig"

## 画面只往上卷（纵向关）。横向关留 false，和以前一模一样。
@export var only_up := false


func _ready() -> void:
	super()
	add_to_group(GROUP)
	# 玩家的 _physics_process 跑完之后再跟镜头，否则跟的是上一帧的位置。
	process_physics_priority = 100


## 关卡里那台摄像机（没有就是 null，比如菜单里）。
static func find(tree: SceneTree) -> CameraRig:
	return tree.get_first_node_in_group(GROUP) as CameraRig if tree != null else null


func _physics_process(_delta: float) -> void:
	var players := _targets()
	if players.is_empty():
		return
	global_position = _center_of(players)
	if only_up:
		global_position.y = _highest(players)
		# 画面走到哪儿，下边界就收到哪儿：之后再也回不去了
		limit_bottom = mini(limit_bottom, ceili(view_rect().end.y))
	_keep_players_on_screen(players)


## 镜头要跟谁：活着的玩家；都死了就跟所有玩家（单人死了那一下镜头还停在尸体上，和以前一样）。
func _targets() -> Array[Player]:
	var alive: Array[Player] = []
	var all: Array[Player] = []
	for node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Player
		if player == null:
			continue
		all.append(player)
		if player.is_alive():
			alive.append(player)
	return alive if not alive.is_empty() else all


func _center_of(players: Array[Player]) -> Vector2:
	var sum := Vector2.ZERO
	for player in players:
		sum += player.global_position
	return sum / players.size()


## 爬得最高的那个人的高度（纵向关镜头跟他）。
func _highest(players: Array[Player]) -> float:
	var top := INF
	for player in players:
		top = minf(top, player.global_position.y)
	return top


## 画面在世界里盖住的那块矩形。Camera2D 自己会把画面夹在 limit_* 里面，这里按同样的规则算一遍，
## 因为我们要在**这一帧**就知道边界在哪（真正的画面变换要等摄像机走完才更新）。
func view_rect() -> Rect2:
	var half := get_viewport_rect().size * 0.5 / zoom
	var middle := global_position
	# 关卡比屏幕窄的时候夹不住，那就让画面对着关卡中心
	middle.x = clampf(middle.x, minf(limit_left + half.x, limit_right - half.x), maxf(limit_left + half.x, limit_right - half.x))
	middle.y = clampf(middle.y, minf(limit_top + half.y, limit_bottom - half.y), maxf(limit_top + half.y, limit_bottom - half.y))
	return Rect2(middle - half, half * 2.0)


func _keep_players_on_screen(players: Array[Player]) -> void:
	var view := view_rect()
	for player in players:
		if not player.is_alive():
			continue
		var spot := player.global_position
		spot.x = clampf(spot.x, view.position.x + EDGE_MARGIN, view.end.x - EDGE_MARGIN)
		if spot != player.global_position:
			player.global_position = spot
