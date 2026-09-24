class_name Balance
extends Resource
## 成长数值表（资源文件 `progression/balance.tres`）：初始属性、技能点加多少、每级给几点、升级要多少经验。
## 只有数据；运行时的等级、经验、金钱、加点、装备记在 `Progress`（autoload）里。调平衡改这个文件，不用改代码。
##
## 四个属性（键就是下面这几个名字）：
## - `life` 生命：最大血量。
## - `attack` 攻击：伤害倍率的基准，**10 = 原样**（武器发射物的伤害 × attack / 10），每多 1 点多 10% 伤害。
## - `defense` 防御：受到的伤害 × 100 / (100 + defense)，向上取整、至少 1。
## - `speed` 速度：百分比，**100 = 原样**。管两件事：武器冷却 × 100 / speed（枪和手雷都算，终极武器不算），
##   冲刺的体力消耗 × 100 / speed（速度 150 = 能多跑一半的时间）。
##
## **初始值要让 1 级、没装备的玩家和改造前手感一模一样**：120 血、敌人每下 40（还是挨 3 下死），
## 攻击 10、速度 100（伤害、冷却、冲刺时长都是原样）。老测试靠这一点继续守着手感。

const LIFE := &"life"
const ATTACK := &"attack"
const DEFENSE := &"defense"
const SPEED := &"speed"
## 全部属性，按 HUD / 加点界面里的顺序。
const STATS: Array[StringName] = [LIFE, ATTACK, DEFENSE, SPEED]
## 攻击、速度的「原样」值。
const ATTACK_BASE := 10.0
const SPEED_BASE := 100.0

## 1 级、没装备时的属性。
@export var base: Dictionary[StringName, float] = {LIFE: 120.0, ATTACK: 10.0, DEFENSE: 0.0, SPEED: 100.0}
## 每个技能点加多少。
@export var per_point: Dictionary[StringName, float] = {LIFE: 10.0, ATTACK: 1.0, DEFENSE: 5.0, SPEED: 5.0}
## 属性上限（加点、装备加起来也不超过）。**四个都要有上限**，否则装备加成做多少都没意义——
## 防御能堆到 400（伤害除以 5）、生命能上千，商店就没法定价了。
## 点满四个要 88 点，而 30 级满级手上只有 63 点，所以**必须取舍**。
@export var cap: Dictionary[StringName, float] = {
	LIFE: 400.0,      # 28 点
	ATTACK: 30.0,     # 20 点
	DEFENSE: 100.0,   # 20 点（伤害减半）
	SPEED: 200.0,     # 20 点（冷却缩一半、冲刺两倍久）
}
## 每升一级给几个技能点。**2 点**：一周目 23 关打完约 23 级 = 49 点，只够点满 56%。
@export var points_per_level := 2
## 新建角色时先给几个点，让玩家一开始就能捏一下。1 级的属性不受影响——点数不花掉就不加。
@export var starting_points := 5
## 等级上限。23 关一周目大约到 23 级，23 → 30 要靠刷。
@export var max_level := 30
## 升级曲线：`xp_to_next(L) = xp_first_level × L^xp_power`。
## **是次方，不是指数**：原来那条 `100 × 1.5^(L-1)` 到 23 级要 74 万经验，撑不到 23 关。
@export var xp_first_level := 140
@export var xp_power := 1.55


## 从 level 级升到下一级要多少经验。满级之后不再需要（返回 0，`add_xp` 据此停住）。
func xp_to_next(level: int) -> int:
	if level >= max_level:
		return 0
	return roundi(xp_first_level * pow(level, xp_power))


## 攻击力 → 伤害倍率；速度 → 冷却倍率（冲刺的体力消耗也乘它）。
static func damage_scale(attack: float) -> float:
	return attack / ATTACK_BASE


static func cooldown_scale(speed: float) -> float:
	return SPEED_BASE / maxf(speed, 1.0)


## 防御之后实际扣多少血。
static func damage_taken(amount: int, defense: float) -> int:
	if amount <= 0:
		return 0
	return maxi(1, ceili(amount * 100.0 / (100.0 + maxf(defense, 0.0))))
