class_name Weapon
extends Equipment
## 一把武器的参数（资源文件，放在 weapons/ 下）。角色的武器槽（WeaponSlot）拿着它，换武器 = 换这个文件。
## 这里只有数据；运行时的冷却和剩余弹药记在 WeaponSlot 里——同一个资源文件可能被好几个角色同时用。
## 武器也是装备（`Equipment`）：`slot` 是 GUN 或 GRENADE，可以带属性加成、价格。

## 发射物场景。它的根节点脚本要有 launch(direction: Vector2)，在加入场景树之前被调用（子弹、手雷都有）。
@export var projectile: PackedScene
## 两次发射之间的最短间隔（秒）。玩家的速度属性会按比例缩短它（见 Balance.cooldown_scale）。
@export var cooldown := 0.15
## 伤害倍率：发射物场景里的伤害 × power × 玩家攻击力的倍率。同一种子弹做出强弱不同的枪就改它。
@export var power := 1.0
## 打中时挂的异常状态（留空就没有）：发射时填进发射物的 `status`，比如燃烧弹、毒弹。
@export var status: StatusEffect
## 按住开火键就连发（步枪）；关掉则每次都要重新按一下（手雷）。
@export var automatic := true
## 弹药上限，-1 表示无限。
@export var max_ammo := -1
## 发射时报告的事件名，素材包按它找声音（见 SkinPack.SOUND_EVENTS）。
@export var fire_event := &"player_shoot"
## 拿在手里长什么样：外观层按这个键挑枪的贴图（赛博朋克包里 rifle = 步枪、launcher = 榴弹枪）。
## 只是个名字，和玩法无关——出膛点、射速、发射物都不看它。素材包里没有这个键的贴图就用默认那把，留空同理。
@export var look := &""
## HUD 上表示这把武器的小色块（占位美术，第 4 步换成图标）。
@export var hud_color := Color(0.7, 0.7, 0.75)
