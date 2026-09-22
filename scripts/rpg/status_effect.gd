class_name StatusEffect
extends Resource
## 一种异常状态（资源文件）：中毒、灼烧、麻痹之类。只有数据；角色身上的计时、扣血由 `StatusEffects` 管。
## 以后加一种新状态 = 新建一个这样的资源，不用写代码。
##
## 挂到角色身上的途径：武器带着它（`Weapon.status`），发射出去的子弹 / 手雷打中谁就给谁挂上；
## 敌人的子弹同理（发射物场景上的 `status`）。
## 抗性：装备的 `Equipment.resist[id]`（玩家）或敌人场景里的 `resist[id]`，0..1——
## **持续时间 × (1 - 抗性)**，1 = 完全免疫。每跳的伤害不变。

## 状态名（抗性表、HUD、音效按它认），比如 &"poison" / &"burn" / &"paralysis"。
@export var id := &""
## 持续多久（秒）。
@export var duration := 3.0
## 每隔多久扣一次血、每次扣多少（0 = 不扣血，比如麻痹）。
## 持续伤害**不走普通挨打**：不触发无敌时间、不击退、不吃防御（防它靠抗性）。
@export var tick_interval := 0.5
@export var tick_damage := 0
## 挂着它时移动速度乘多少（1 = 不减速）。
@export_range(0.0, 1.0) var move_scale := 1.0
## 挂着它时能不能行动（移动、开火）。麻痹就是 false。
@export var can_act := true
