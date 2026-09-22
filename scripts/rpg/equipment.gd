class_name Equipment
extends Resource
## 一件装备（资源文件）：装在哪个位置、值多少钱、给哪些属性加成、抗哪些异常状态。只有数据。
## 武器（`Weapon`）也是装备：枪和手雷各占一个位置，种类、外观、属性都可以不同。
## 以后的纯属性装备（护甲、饰品）直接用这个类，不用新写脚本。

enum Slot {
	GUN,        ## 枪（按住连发 / 单发，玩家的主武器）
	GRENADE,    ## 手雷（榴弹枪）
	ARMOR,      ## 护甲（预留）
	ACCESSORY,  ## 饰品（预留）
}

@export var display_name := ""
@export var slot := Slot.GUN
## 商店价格。
@export var price := 0
## 属性加成：属性名（`Balance.STATS`）→ 加多少，直接加在属性上（可以是负数：重武器减射速之类）。
@export var bonuses: Dictionary[StringName, float] = {}
## 异常状态抗性：状态名（`StatusEffect.id`）→ 0..1，1 = 完全免疫。多件装备取最大的那个。
@export var resist: Dictionary[StringName, float] = {}
