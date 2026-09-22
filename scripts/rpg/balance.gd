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
## 属性上限（加点、装备加起来也不超过）。速度封顶：冷却最多缩到一半、冲刺最多跑两倍久，免得和敌人的节奏差太远。
@export var cap: Dictionary[StringName, float] = {SPEED: 200.0}
## 每升一级给几个技能点。
@export var points_per_level := 3
## 从 1 级升到 2 级要多少经验，之后每级乘 xp_growth。
@export var xp_first_level := 100
@export var xp_growth := 1.5


## 从 level 级升到下一级要多少经验。
func xp_to_next(level: int) -> int:
	return roundi(xp_first_level * pow(xp_growth, level - 1))


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
