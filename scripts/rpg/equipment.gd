class_name Equipment
extends Resource
## 一件装备（资源文件）：装在哪个位置、值多少钱、给哪些属性加成、抗哪些异常状态。只有数据。
## 武器（`Weapon`）也是装备：枪和手雷各占一个位置，种类、外观、属性都可以不同。
## 以后的纯属性装备（护甲、饰品）直接用这个类，不用新写脚本。

## 身上的位置，一个位置同时只能穿一件。**顺序就是设置界面里那 8 个格子的顺序**，别打乱。
## 前两个是武器（枪、手雷），中间五个是护甲的五个部位，最后一个是饰品。
enum Slot {
	GUN,      ## 枪（按住连发 / 单发，玩家的主武器）
	GRENADE,  ## 手雷（榴弹枪）
	HEAD,     ## 头盔
	BODY,     ## 胸甲
	LEGS,     ## 裤子
	FEET,     ## 靴子
	HANDS,    ## 手套
	TRINKET,  ## 饰品
}

## 界面上每个位置怎么称呼（全大写，界面里一律英文，见 CLAUDE.md）。
const SLOT_NAMES := {
	Slot.GUN: "GUN", Slot.GRENADE: "BOMB", Slot.HEAD: "HEAD", Slot.BODY: "BODY",
	Slot.LEGS: "LEGS", Slot.FEET: "FEET", Slot.HANDS: "HANDS", Slot.TRINKET: "TRINKET",
}

## 界面上显示的名字。**英文大写**——素材包的字模没有汉字，写中文会变成一串方块（见 CLAUDE.md）。
@export var display_name := ""
@export var slot := Slot.GUN
## 商店价格。
@export var price := 0
## 要几级才买得起 / 用得了。商店只卖门槛 ≤ 当前等级的（更高的画灰当胡萝卜）。
## **没有门槛的话钱一多就能买到过强的东西**，23 关的曲线就塌了。
@export var min_level := 1
## 属性加成：属性名（`Balance.STATS`）→ 加多少，直接加在属性上（可以是负数：重武器减射速之类）。
@export var bonuses: Dictionary[StringName, float] = {}
## 异常状态抗性：状态名（`StatusEffect.id`）→ 0..1，1 = 完全免疫。多件装备取最大的那个。
@export var resist: Dictionary[StringName, float] = {}
## 商店、背包、人物设置界面里显示的图标（32×32）。留空就画一个空格子。
## **存路径不存贴图**：图标在素材包里，素材包不在（公开版去掉了第三方素材）的话，
## 直接引用会让整个 `.tres` 加载失败、连枪都拿不到；存路径的话只是图标空着。
@export_file("*.png") var icon_path := ""
## 图标本身：路径有文件才加载，没有就是 null（界面画空格子）。也可以直接塞一张（测试用）。
var icon: Texture2D:
	get:
		if _icon == null and not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			_icon = load(icon_path) as Texture2D
		return _icon
	set(value):
		_icon = value
var _icon: Texture2D
