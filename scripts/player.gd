class_name Player
extends CharacterBody2D
## 方块玩家：左右移动、跳跃、射击，有生命值和受伤无敌帧。

signal health_changed(health: int, max_health: int)
signal died
## 血空了但还没真死，正倒在地上等队友来救（只有双人时会发生）。
signal downed
## 被队友拉起来了。
signal revived
signal stamina_changed(stamina: float, max_stamina: float)
## 切换武器（或当前这把被换掉）时发出，HUD 接这个。
signal weapon_switched(index: int, weapon: Weapon)
## 终极武器剩余次数变化，HUD 接这个。
signal ultimate_ammo_changed(ammo: int, max_ammo: int)


@export_group("Health")
## 最大血量：由生命属性算出来（自己那份进度的 stat(life)），这里不再手填。
var max_health := 0
## 受伤后的无敌时间，期间闪烁且不再受任何伤害。
@export var invincible_time := 1.0
## 受伤时被顶开的速度（水平方向背离伤害源）。
@export var hurt_knockback := Vector2(140, -240)

@export_group("Downed")
## 倒地之后还能撑多久（秒）。撑完就真死了。**只在双人时会进这个状态**——
## 一个人玩没人来救，倒地只会变成站着等死。
@export var down_time := 10.0
## 掉进坑里扣掉最大血量的几分之几。
@export var fall_damage_ratio := 1.0 / 3.0
## 掉进坑里捞回来之后给多久无敌（够你看清楚周围再动）。
@export var fall_grace := 1.5
## 队友走到这么近（像素，身体原点之间）就自动把人拉起来。不用按键。
@export var revive_range := 28.0
## 救起来回多少血（占上限的比例），外加一小段无敌免得刚起来又被同一发子弹打倒。
@export var revive_health_ratio := 0.5
@export var revive_grace := 1.0

@export_group("Movement")
@export var move_speed := 180.0
@export var acceleration := 1400.0
@export var friction := 1800.0
@export var air_control := 0.7

@export_group("Jump")
@export var jump_velocity := -560.0
@export var gravity := 1800.0
@export var max_fall_speed := 800.0
## 松开跳跃键时，上升速度乘以这个系数，实现可变跳跃高度。
@export var jump_cut := 0.5
## 离开平台边缘后仍可起跳的时间（土狼时间）。
@export var coyote_time := 0.1
## 落地前提前按下跳跃键仍然有效的时间（跳跃缓冲）。
@export var jump_buffer_time := 0.1

@export_group("Crouch")
## 趴下时的移动速度倍率。
@export var crouch_speed_scale := 0.6

@export_group("Sprint")
## 奔跑时的移动速度倍率。
@export var sprint_speed_scale := 1.5
@export var max_stamina := 100.0
## 奔跑时每秒消耗的体力。满体力大约能连续跑 max_stamina / stamina_drain 秒。
@export var stamina_drain := 35.0
## 停止奔跑后每秒恢复的体力。
@export var stamina_regen := 25.0
## 停止奔跑后隔多久才开始恢复。
@export var stamina_regen_delay := 0.5
## 体力耗尽后，要恢复到这个比例才能再次奔跑。
## 否则一直按着奔跑键时，体力会在 0 附近刚回一点就被用掉，人物一顿一顿地时快时慢。
@export_range(0.0, 1.0) var stamina_recover_ratio := 0.25

@export_group("Weapons")
## 身上的武器，按切换顺序排列（默认 [步枪, 手雷]）。Shift / 手柄 X 切到下一把，J / RT 用当前这把开火，
## 都跟着 8 方向瞄准。换武器 = 换这里的资源文件（weapons/*.tres）。
@export var weapons: Array[Weapon] = []
## 终极武器（K / 手柄 Y，瞬时发动，有次数限制）。不在切换顺序里。默认 weapons/ultimate.tres。
@export var ultimate_weapon: Weapon

## 瞄准方向（魂斗罗式）。W + 左右 = 边走边斜上，只按 W = 原地正上；
## S + 左右 = 边走边斜下，只按 S：地面上朝前斜下、空中朝正下；W、S 同时按互相抵消；趴下时一律水平。
enum Aim { FORWARD, UP, DIAGONAL_UP, DIAGONAL_DOWN, DOWN }

## 斜向和正下方的出膛点，相对身体中心（朝右时；朝左时 x 取反）。按约定由代码算、不挂在 Visual 下，和外观无关。
## 斜下的枪口不能太低：子弹转 45° 后半高约 3px，站在地面上（脚底在 +8）时出膛点要在 +5 以上，否则一出膛就嵌进地里。
## 各方向的出膛点，相对身体中心（朝右时；朝左 x 取反）。全部由代码算，不挂在 Visual 下面——
## 判定点不能跟着外观走，否则换皮肤、甚至开枪的后坐力位移都会改变子弹从哪飞出去。
const LEVEL_MUZZLE := Vector2(23, -7)
const UP_MUZZLE := Vector2(8, -27)
const DIAGONAL_UP_MUZZLE := Vector2(22, -21)
const DIAGONAL_DOWN_MUZZLE := Vector2(19, 7)
const DOWN_MUZZLE := Vector2(9, 13)

## 站立/蹲下的碰撞体高度。脚底位置不变，只压低头顶。
## 倒地时一秒闪几次：刚倒下慢，快到头了急。
const DOWN_BLINK_SLOW := 1.5
const DOWN_BLINK_FAST := 7.0
## 闪到最暗时多透明。
const DOWN_BLINK_DIM := 0.25

const STAND_HEIGHT := 32.0
## 趴下的碰撞体高度。敌人站着开的枪离地 21~25px（枪举在胸口），趴下必须矮于 21px 才躲得开；
## 取 12 是为了和趴姿贴图（12~14px）差不多高，见 CLAUDE.md「所有人按素材对齐」。
const CROUCH_HEIGHT := 12.0
const HURTBOX_STAND_HEIGHT := 36.0
## 开枪时外观往反方向弹开多少像素（后坐力，纯表现，不动身体和判定）。
const RECOIL_DISTANCE := 4.0
## 后坐力每秒回复多少像素。
const RECOIL_RECOVER := 80.0
## 从单向平台上跳下来时，忽略那块平台多久（秒）。够落下一个身位就行，太长会穿过下一层平台。
const DROP_THROUGH_TIME := 0.25
## 跳下来那一下先给一点向下的速度，好立刻脱离地面。
const DROP_THROUGH_SPEED := 80.0

var facing := 1
## 最近一枪的出膛点和方向（枪口闪光等特效读它，见 fx.gd）。
var last_muzzle_position := Vector2.ZERO
var last_shot_direction := Vector2.RIGHT
var health := 0
var is_crouching := false
var is_sprinting := false
var aim := Aim.FORWARD
var stamina := 0.0

var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
## 主武器槽：冷却和弹药都在里面。
## 当前拿在手上的是第几把。
var current_weapon := 0
## 每把武器一个槽，各自记冷却和弹药：切走再切回来，冷却和弹药都还在。
var _slots: Array[WeaponSlot] = []
var _ultimate := WeaponSlot.new()
var _recoil := Vector2.ZERO
## 正在穿过的那块单向平台（跳下平台时临时忽略它的碰撞）。
var _dropping_platform: Platform
var _drop_timer := 0.0
var _invincible_timer := 0.0
## 不闪烁的无敌（终极武器用）。暂停期间玩家的计时也停着，所以它能覆盖整个定格。
var _shield_timer := 0.0
var _dead := false
## 最后一次**站稳**的地方：掉进坑里就捞回这儿。只在脚踏实地、没在被击退的时候记，
## 所以不会记到半空中，也不会记到正往坑里掉的那一瞬。
var _safe_spot := Vector2.ZERO
## 倒地闪烁走到哪儿了（整数部分 = 闪了几次）。
var _down_blink := 0.0
## 濒死（双人专用）：血空了先倒地，队友走过来就能拉起来，没人来救、倒计时走完才真的死。
var _downed := false
var _down_timer := 0.0
## 身上的异常状态（中毒、麻痹……）。持续伤害走 take_status_damage，不触发无敌、不击退。
var statuses := StatusEffects.new()
## 防御属性（挨打时减伤）。
var _defense := 0.0
## 速度属性让冲刺耗体力变慢（1 = 原样）。
var _stamina_drain_scale := 1.0
var _exhausted := false
var _stamina_regen_timer := 0.0

## 第几号玩家（0 = 1 号，1 = 2 号）：决定读哪一套输入（见 act()）、用哪一份成长进度、哪一套 HUD。
@export var player_index := 0

## 自己那一份成长进度（`Progress.of(player_index)`，双人时两个人各一份）。在 `_ready` 里取。
var progress: PlayerProgress

## 外观层。玩法只调它的接口（朝向/姿势/瞄准/受击/闪烁/死亡/后坐力），不碰方块和颜色。
## 外观用素材包里的哪一套（见 Skins.build_appearance）。**出生时会被自己那份进度里的 `look` 覆盖**——
## 外观是角色自己的属性，不是座位的，2 号玩家照样可以选 Biker。
@export var skin_key := &"biker"
@onready var _visual: Appearance = $Visual
@onready var _hurtbox: Area2D = $Hurtbox
@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _hurtbox_shape: CollisionShape2D = $Hurtbox/CollisionShape2D
@onready var _head_check: ShapeCast2D = $HeadCheck


## 这个玩家的输入动作名：1 号就是动作名本身（`shoot`），2 号加前缀（`p2_shoot`）。读输入一律经过它。
func act(action: StringName) -> StringName:
	return action if player_index == 0 else StringName("p%d_%s" % [player_index + 1, action])


## 还活着吗（敌人找目标、摄像机跟随、双人的重开判断都看它）。
## **倒地的也算不活着**：敌人因此不再打他，一种敌人的代码都不用改。
func is_alive() -> bool:
	return not _dead and not _downed


## 正倒在地上等人救（双人专用）。
func is_downed() -> bool:
	return _downed


## 这一局还有人吗：还有人站着、或者有人正倒在地上等救，这一关就还没完（双人）。
## 关卡和 HUD 都要问这件事，所以搁在这儿，别两处各写一遍。
static func anyone_left(tree: SceneTree) -> bool:
	for node in tree.get_nodes_in_group(&"player"):
		var player := node as Player
		if player != null and (player.is_alive() or player.is_downed()):
			return true
	return false


## 还能撑多久（秒）。倒计时走完就真死了。
func down_time_left() -> float:
	return _down_timer


func _ready() -> void:
	# 先拿自己那份进度：长什么样也记在里面（`look`），外观要按它来装
	progress = Progress.of(player_index)
	skin_key = progress.look
	_visual = Skins.build_appearance(self, skin_key)
	# 两个武器位用进度里身上装备的那两把（枪、手雷）；进度里没有就用场景里配的
	var gun := progress.gear(Equipment.Slot.GUN) as Weapon
	var grenade := progress.gear(Equipment.Slot.GRENADE) as Weapon
	if gun != null and grenade != null:
		weapons = [gun, grenade]
	for weapon in weapons:
		_slots.append(WeaponSlot.new(weapon))
	if not _slots.is_empty():
		_visual.hold(current_slot().weapon.look)
	_ultimate.ammo_changed.connect(func(ammo: int, max_ammo: int) -> void: ultimate_ammo_changed.emit(ammo, max_ammo))
	if ultimate_weapon != null:
		_ultimate.equip(ultimate_weapon)
	_apply_stats()
	health = max_health
	# 还没走过一步就掉下去的话，捞回出生点（不设的话会被捞到世界原点去）
	_safe_spot = global_position
	health_changed.emit(health, max_health)
	progress.stats_changed.connect(_apply_stats)
	statuses.on_damage = take_status_damage
	stamina = max_stamina
	stamina_changed.emit(stamina, max_stamina)
	# HeadCheck 正好覆盖「站起来需要多出来的那段空间」：从站立头顶到趴下后的头顶。
	# 按常量算而不是写死在场景里，改下蹲高度时不会不同步。
	var headroom := STAND_HEIGHT - CROUCH_HEIGHT
	(_head_check.shape as RectangleShape2D).size.y = headroom
	_head_check.position.y = -STAND_HEIGHT / 2.0 + headroom / 2.0


func _physics_process(delta: float) -> void:
	if _dead or _downed:
		_apply_gravity(delta)
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		move_and_slide()
		if _downed:
			_update_downed(delta)
		return

	_apply_gravity(delta)
	statuses.tick(delta)
	_update_drop_through(delta)
	_update_crouch()
	_handle_jump(delta)
	_handle_horizontal(delta)
	move_and_slide()
	_handle_ultimate()
	_handle_switch()
	_handle_shoot(delta)
	_update_recoil(delta)
	_update_invincibility(delta)
	_shield_timer -= delta
	_check_contact_damage()
	_remember_safe_ground()
	_visual.motion(_motion_state())


## 记下最后一次站稳的地方。**要真的站住**：踩在地上、横竖都不在飞，
## 才算一个能把人捞回来的落脚点。
func _remember_safe_ground() -> void:
	if is_on_floor() and absf(velocity.y) < 1.0:
		_safe_spot = global_position


## 这一帧在做什么，交给外观去选动画。趴下不在这里说，它走 `pose()`（见 Appearance.Motion）。
func _motion_state() -> Appearance.Motion:
	if not is_on_floor():
		return Appearance.Motion.FALL if velocity.y > 0.0 else Appearance.Motion.JUMP
	if absf(velocity.x) < 1.0:
		return Appearance.Motion.IDLE
	return Appearance.Motion.RUN if is_sprinting else Appearance.Motion.WALK


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _handle_jump(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer -= delta

	if Input.is_action_just_pressed(act(&"jump")):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer -= delta

	# 魂斗罗式跳下平台：站在单向平台上按住「下」再按跳跃，就直接穿下去，而不是起跳。
	if _jump_buffer_timer > 0.0 and is_on_floor() and Input.is_action_pressed(act(&"aim_down")):
		var platform := _one_way_floor()
		if platform != null:
			_drop_through(platform)
			return

	var can_jump := _jump_buffer_timer > 0.0 and _coyote_timer > 0.0
	if can_jump and is_crouching:
		# 蹲着也能跳，但得先站得起来：头顶被挡住就跳不了。
		if _head_blocked():
			can_jump = false
		else:
			_set_crouching(false)

	if can_jump:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		GameEvents.report(&"jump", self)

	if Input.is_action_just_released(act(&"jump")) and velocity.y < 0.0:
		velocity.y *= jump_cut


## 脚下踩着的单向平台；踩的是实心地面（或者没踩着东西）就返回 null。
## 用上一次 move_and_slide 的碰撞结果判断，所以只有真正站在平台上时才跳得下去。
func _one_way_floor() -> Platform:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		if collision.get_normal().y > -0.7:
			continue # 不是脚下那一面
		var platform := collision.get_collider() as Platform
		if platform != null and platform.one_way:
			return platform
	return null


## 开始穿过这块平台：临时把它排除在碰撞之外，并往下推一点。
func _drop_through(platform: Platform) -> void:
	_dropping_platform = platform
	_drop_timer = DROP_THROUGH_TIME
	add_collision_exception_with(platform)
	velocity.y = maxf(velocity.y, DROP_THROUGH_SPEED)
	# 跳跃缓冲要清掉，否则刚穿下去就又起跳了。
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0


## 时间到就恢复和那块平台的碰撞（这时人已经落到它下面了，不会被顶回去）。
func _update_drop_through(delta: float) -> void:
	if _drop_timer <= 0.0:
		return
	_drop_timer -= delta
	if _drop_timer > 0.0:
		return
	if _dropping_platform != null and is_instance_valid(_dropping_platform):
		remove_collision_exception_with(_dropping_platform)
	_dropping_platform = null


func _handle_horizontal(delta: float) -> void:
	# 手柄摇杆推过死区（0.3）就按全速走，不按推的幅度调速——像素风横版的习惯；键盘本来就只有 0 和 1。
	var direction := signf(Input.get_axis(act(&"move_left"), act(&"move_right")))
	# 麻痹之类的状态：动不了
	if not statuses.can_act():
		direction = 0.0
	_update_sprint(delta, direction)
	var control := 1.0 if is_on_floor() else air_control
	var speed := move_speed * _speed_scale()
	if direction != 0.0:
		facing = signi(direction)
		_visual.face(facing)
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * control * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * control * delta)


func _speed_scale() -> float:
	var status := statuses.move_scale()
	if is_crouching:
		return crouch_speed_scale * status
	if is_sprinting:
		return sprint_speed_scale * status
	return status


## 按住奔跑键且正在移动时加速并消耗体力；不跑的时候隔一小段时间开始回体力。
## 原地按着奔跑键不算奔跑，也不耗体力；趴着不能奔跑。
func _update_sprint(delta: float, direction: float) -> void:
	var wants := Input.is_action_pressed(act(&"sprint")) and direction != 0.0 and not is_crouching
	is_sprinting = wants and not _exhausted and stamina > 0.0

	# 先更新 _exhausted 再改体力：stamina_changed 发出时状态已经是最新的，HUD 据此变色。
	if is_sprinting:
		var drained := stamina - stamina_drain * _stamina_drain_scale * delta
		if drained <= 0.0:
			_exhausted = true
			GameEvents.report(&"stamina_exhausted", self)
		_set_stamina(drained)
		_stamina_regen_timer = stamina_regen_delay
	elif _stamina_regen_timer > 0.0:
		_stamina_regen_timer -= delta
	else:
		var regained := stamina + stamina_regen * delta
		if _exhausted and regained >= max_stamina * stamina_recover_ratio:
			_exhausted = false
		_set_stamina(regained)


## 体力耗尽、还没恢复到能重新起跑的程度。
func is_exhausted() -> bool:
	return _exhausted


func _set_stamina(value: float) -> void:
	var clamped := clampf(value, 0.0, max_stamina)
	if clamped == stamina:
		return
	stamina = clamped
	stamina_changed.emit(stamina, max_stamina)


func _update_crouch() -> void:
	# 只能在地面上主动蹲；空中松开蹲键会自动站起来。
	var wants := Input.is_action_pressed(act(&"crouch")) and is_on_floor()
	if wants == is_crouching:
		return
	if wants:
		_set_crouching(true)
	elif not _head_blocked():
		_set_crouching(false)


func _set_crouching(value: bool) -> void:
	is_crouching = value
	var height := CROUCH_HEIGHT if value else STAND_HEIGHT
	var lowered := (STAND_HEIGHT - height) / 2.0
	# 碰撞体和受击框同时压低，并整体下移，保证脚底位置不变。
	(_shape.shape as RectangleShape2D).size.y = height
	_shape.position.y = lowered
	(_hurtbox_shape.shape as RectangleShape2D).size.y = HURTBOX_STAND_HEIGHT - (STAND_HEIGHT - height)
	_hurtbox_shape.position.y = lowered
	_visual.pose(height / STAND_HEIGHT, lowered)


## 碰撞体中心的世界坐标。趴下时比 global_position 低 6px，敌人的视线要瞄这里。
func body_center() -> Vector2:
	return _shape.global_position


## 头顶上方是否有东西挡着，挡着就站不起来。
func _head_blocked() -> bool:
	_head_check.force_shapecast_update()
	for i in _head_check.get_collision_count():
		var collider := _head_check.get_collider(i)
		# 单向平台可以从下面穿过去，不算挡头。
		if collider is Platform and (collider as Platform).one_way:
			continue
		return true
	return false


## J 用当前武器朝当前瞄准方向开火（瞄准规则见 Aim）。趴着不动只能水平开枪（子弹贴地飞），趴着爬行时不能开枪。
func _handle_shoot(delta: float) -> void:
	# 所有武器的冷却都在走：切走的那把也会冷却好。
	for slot in _slots:
		slot.tick(delta)
	var moving := Input.get_axis(act(&"move_left"), act(&"move_right")) != 0.0
	_update_aim(moving)
	var pressed := Input.is_action_pressed(act(&"shoot")) if current_slot().weapon.automatic else Input.is_action_just_pressed(act(&"shoot"))
	# 趴下时一律不能开火：步枪、手雷都不行，不管在不在爬行。想开枪先站起来。
	# （终极武器不走这里，任何状态都能发动。）
	if is_crouching or not pressed or not current_slot().is_ready() or not statuses.can_act():
		return
	_shoot(aim_vector())


func _update_aim(moving: bool) -> void:
	var up := Input.is_action_pressed(act(&"aim_up"))
	var down := Input.is_action_pressed(act(&"aim_down"))
	if is_crouching or up == down:
		aim = Aim.FORWARD
	elif up:
		aim = Aim.DIAGONAL_UP if moving else Aim.UP
	elif moving or is_on_floor():
		aim = Aim.DIAGONAL_DOWN
	else:
		aim = Aim.DOWN
	# 占位美术：按瞄准方向显示对应的那根枪。
	_visual.aim(aim_vector())


## 当前瞄准方向对应的子弹方向（单位向量）。
func aim_vector() -> Vector2:
	match aim:
		Aim.UP:
			return Vector2.UP
		Aim.DIAGONAL_UP:
			return Vector2(facing, -1).normalized()
		Aim.DIAGONAL_DOWN:
			return Vector2(facing, 1).normalized()
		Aim.DOWN:
			return Vector2.DOWN
	return Vector2(facing, 0)


## K / 手柄 Y 发动终极武器。任何状态（趴着、爬行、空中）都能用；效果见 Ultimate。
func _handle_ultimate() -> void:
	if _ultimate.weapon == null or not Input.is_action_just_pressed(act(&"ultimate")) or not _ultimate.is_ready():
		return
	_ultimate.fire(get_parent(), global_position, Vector2(facing, 0), self)


## 终极武器还剩几次。
func ultimate_ammo() -> int:
	return _ultimate.ammo


## 不闪烁的无敌 seconds 秒（已有更长的就保留更长的）。
func grant_invincibility(seconds: float) -> void:
	_shield_timer = maxf(_shield_timer, seconds)


func is_invincible() -> bool:
	return _invincible_timer > 0.0 or _shield_timer > 0.0


func _handle_switch() -> void:
	if Input.is_action_just_pressed(act(&"switch_weapon")):
		switch_weapon()


## 切到下一把武器（最后一把之后回到第一把）。
func switch_weapon() -> void:
	if _slots.size() < 2:
		return
	current_weapon = (current_weapon + 1) % _slots.size()
	_visual.hold(current_slot().weapon.look)
	weapon_switched.emit(current_weapon, current_slot().weapon)
	GameEvents.report(&"weapon_switch", self)


func current_slot() -> WeaponSlot:
	return _slots[current_weapon]


## 把第 index 把武器换成 weapon（以后拾取武器升级就调这个）：冷却清零、弹药补满。
func equip_weapon(index: int, weapon: Weapon) -> void:
	weapons[index] = weapon
	_slots[index].equip(weapon)
	_apply_stats()
	if index == current_weapon:
		_visual.hold(weapon.look)
		weapon_switched.emit(current_weapon, weapon)


## 用当前武器朝 direction 开一次火（不看冷却；_handle_shoot 先检查过了，测试也直接调它）。
## 所有武器都从同一套枪口出膛（见 _muzzle_position）。
func _shoot(direction: Vector2) -> void:
	last_muzzle_position = _muzzle_position(direction)
	last_shot_direction = direction
	_recoil = -direction * RECOIL_DISTANCE
	_visual.kick(_recoil)
	current_slot().fire(get_parent(), last_muzzle_position, direction, self)


## 出膛点：身体原点（= 站立碰撞体的中心）+ 该方向的常量偏移，朝左时 x 取反。
## 趴下时不能开火，所以不需要「趴下的出膛点」——玩家这边的高度规则只看站姿。
func _muzzle_position(direction: Vector2) -> Vector2:
	var offset := LEVEL_MUZZLE
	if direction == Vector2.UP:
		offset = UP_MUZZLE
	elif direction == Vector2.DOWN:
		offset = DOWN_MUZZLE
	elif direction.y != 0.0:
		offset = DIAGONAL_UP_MUZZLE if direction.y < 0.0 else DIAGONAL_DOWN_MUZZLE
	return global_position + Vector2(offset.x * facing, offset.y)


## 后坐力：开枪那一下外观往反方向弹开，然后弹回原位。
## 只改 Visual 的位置，身体、碰撞体、枪口、子弹全都不受影响。
func _update_recoil(delta: float) -> void:
	if _recoil == Vector2.ZERO:
		return
	_recoil = _recoil.move_toward(Vector2.ZERO, RECOIL_RECOVER * delta)
	_visual.kick(_recoil)


func _update_invincibility(delta: float) -> void:
	if _invincible_timer <= 0.0:
		return
	_invincible_timer -= delta
	if _invincible_timer <= 0.0:
		_visual.blink(1.0)
	else:
		# 每 0.05 秒切换一次显隐，做出闪烁效果。
		_visual.blink(0.3 if int(_invincible_timer / 0.05) % 2 == 0 else 1.0)


## 站在/贴着敌人身上时持续判定，无敌帧结束后会再次受伤。
func _check_contact_damage() -> void:
	if is_invincible():
		return
	for body in _hurtbox.get_overlapping_bodies():
		if body is Enemy:
			var enemy := body as Enemy
			take_damage(enemy.contact_damage, enemy.global_position)
			# 撞上了也告诉它一声：会追人的 D 会往后弹开，不然它一直贴着，无敌帧一过又扣一次血
			enemy.bounced_off(global_position)
			return


## 从进度里读属性：生命 → 血量上限（上限加了多少就补多少血），攻击 → 伤害倍率，
## 速度 → 冷却倍率和冲刺的体力消耗倍率，防御留着挨打时用。
## 出生时读一次，之后属性一变（升级加点、换装备）就重读。
func _apply_stats() -> void:
	var life := int(progress.stat(Balance.LIFE))
	if max_health > 0 and life > max_health and not _dead:
		health += life - max_health
	max_health = life
	health = mini(health, max_health)
	_defense = progress.stat(Balance.DEFENSE)
	var damage := Balance.damage_scale(progress.stat(Balance.ATTACK))
	var cooldown := Balance.cooldown_scale(progress.stat(Balance.SPEED))
	_stamina_drain_scale = cooldown
	for slot in _slots:
		slot.damage_scale = damage
		slot.cooldown_scale = cooldown
	health_changed.emit(health, max_health)


## 挂一个异常状态（子弹、手雷打中时调）。抗性来自身上的装备（自己那份进度的 resistance）。
func apply_status(effect: StatusEffect) -> void:
	if _dead or _downed or effect == null:
		return
	statuses.apply(effect, progress.resistance(effect.id))


## 异常状态的持续伤害：不吃防御、不触发无敌时间、不击退（防它靠抗性）。
func take_status_damage(amount: int) -> void:
	if _dead or _downed or amount <= 0:
		return
	health -= amount
	health_changed.emit(health, max_health)
	if health <= 0:
		_die()


## 被敌人子弹或接触伤害调用。`source_position` 用来决定击退方向。防御按 Balance.damage_taken 减伤。
## `from` 是打人的那一方，玩家这边用不上（敌人用它记奖励算谁的），但签名要和敌人的一模一样——
## `Bullet` 是靠 `has_method("take_damage")` 找目标的，两边必须同名同签名。
func take_damage(amount: int, source_position := Vector2.INF, _from: Node = null) -> void:
	# 倒地的人打不动：敌人本来就不瞄他（is_alive 是 false），但流弹和贴身伤害还是会撞上来，
	# 不拦的话倒计时会被一次次刷新。
	if _dead or _downed or is_invincible():
		return
	health -= Balance.damage_taken(amount, _defense)
	health_changed.emit(health, max_health)
	if health <= 0:
		_go_down()
		return
	GameEvents.report(&"player_hurt", self)
	_invincible_timer = invincible_time
	var away := 1.0 if source_position == Vector2.INF else signf(global_position.x - source_position.x)
	if away == 0.0:
		away = 1.0
	velocity = Vector2(hurt_knockback.x * away, hurt_knockback.y)


## 血空了：双人时先倒地等人救，单人直接死。
func _go_down() -> void:
	if Session.player_count < 2:
		_die()
		return
	_downed = true
	health = 0
	_down_timer = down_time
	_down_blink = 0.0
	velocity.x = 0.0
	if is_crouching:
		_set_crouching(false)
	_visual.show_dead()
	downed.emit()
	GameEvents.report(&"player_down", self)


## 倒地时每帧：队友走到跟前就自动拉起来，没人来就倒计时，撑完真死。
func _update_downed(delta: float) -> void:
	for node in get_tree().get_nodes_in_group(&"player"):
		var mate := node as Player
		if mate != null and mate != self and mate.is_alive() 				and global_position.distance_to(mate.global_position) <= revive_range:
			revive()
			return
	_down_timer -= delta
	_blink_while_down(delta)
	if _down_timer <= 0.0:
		_die()


## 倒地的人**身上越闪越快**——时间还剩得多就慢慢闪，快到头了闪得急，
## 队友一眼就看得出还来不来得及。比在 HUD 上写个数字直观：眼睛本来就盯着人。
func _blink_while_down(delta: float) -> void:
	var left := clampf(_down_timer / maxf(down_time, 0.001), 0.0, 1.0)
	_down_blink += delta * lerpf(DOWN_BLINK_FAST, DOWN_BLINK_SLOW, left)
	_visual.blink(DOWN_BLINK_DIM if fmod(_down_blink, 1.0) < 0.5 else 1.0)


## 被队友拉起来：回一半血，给一小段无敌，接着打。
func revive() -> void:
	if not _downed:
		return
	_downed = false
	_down_timer = 0.0
	_down_blink = 0.0
	_visual.blink(1.0)
	health = maxi(1, int(max_health * revive_health_ratio))
	health_changed.emit(health, max_health)
	_visual.revive()
	grant_invincibility(revive_grace)
	revived.emit()
	GameEvents.report(&"player_revive", self)


## 掉出关卡（踩空掉进坑里）：**扣掉三分之一的血，捞回最后站稳的地方**，再给一小段无敌，
## 不是直接判死。坑在这一关里到处都是，一脚踩空就重来一整关太狠了。
## 扣完血还剩得下才捞人；扣没了就照常走死亡那条路（双人时是倒地等人救）。
## **不吃无敌帧**：刚挨完打的那一秒不该让你在坑里飘着。
func fall_out() -> void:
	if _dead:
		return
	if _downed:
		# 倒地的人掉下去：已经没血可扣了，捞回来接着等队友
		_respawn_at_safe_ground()
		return
	health -= maxi(1, ceili(max_health * fall_damage_ratio))
	health_changed.emit(health, max_health)
	if health <= 0:
		health = 0
		_go_down()
		return
	GameEvents.report(&"player_hurt", self)
	_respawn_at_safe_ground()


## 捞回最后一次站稳的地方，站定、给一小段无敌。
func _respawn_at_safe_ground() -> void:
	global_position = _safe_spot
	velocity = Vector2.ZERO
	grant_invincibility(fall_grace)


func _die() -> void:
	_dead = true
	_downed = false
	health = 0
	_visual.show_dead()
	died.emit()
	GameEvents.report(&"player_death", self)
