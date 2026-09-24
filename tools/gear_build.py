"""生成商店里卖的装备资源，输出到 armor/ 和 weapons/。

    python tools/gear_build.py

**为什么用脚本生成**：一件装备就是一小段数据（价格、等级门槛、属性加成），
而价格和加成是**一起算出来的**——定价 `60 × 门槛等级^1.9`、加成按档位递增，
散在二十个 `.tres` 里手改根本对不齐。这里一张表看全，改平衡只动这张表再重跑。
和 `level_build.py`、`skin_build.py` 是一个路子：规则写在脚本里，产物进仓库。

图标来自 `art_in/default/armor/Icon24_NN.png`（**每套 5 件，头/身/腿/脚/手**，一套一个配色）
和 `2 Guns/Icon15_NN.png`，由 `tools/ui_build.py` 抠进 `skins/cyberpunk/ui/`。

饰品（TRINKET）这一批没有——素材包里没有合适的图标，那一页先空着。
"""
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
ICONS = "res://skins/cyberpunk/ui"

## 定价：`60 × 门槛等级^1.9`（见 CLAUDE.md 的「数值怎么来的」）。
## 全程「当前买得起三四件」，八个部位全配顶级 = 一周目收入的 174%，一周目配不齐。
def price_at(level):
	return int(round(60 * level ** 1.9 / 10.0)) * 10


## 防具三档：一档一套配色、一个门槛等级。
## 加成对着属性上限定（生命 400 / 攻击 30 / 防御 100 / 速度 200）：
## 顶档全身 = 防御 +36、生命 +130、速度 +36、攻击 +5，明显变强但远没到顶，
## 剩下的留给加点和以后的档位。
ARMOR_TIERS = [
	("SCRAP", 1, 3, {                     # 一档：蓝金那套，3 级
		"HEAD": {"defense": 5.0},
		"BODY": {"life": 30.0},
		"LEGS": {"defense": 3.0, "speed": 3.0},
		"FEET": {"speed": 8.0},
		"HANDS": {"attack": 1.0},
	}),
	("COMBAT", 2, 8, {                    # 二档：红粉那套，8 级
		"HEAD": {"defense": 12.0},
		"BODY": {"life": 70.0},
		"LEGS": {"defense": 8.0, "speed": 6.0},
		"FEET": {"speed": 16.0},
		"HANDS": {"attack": 3.0},
	}),
	("TITAN", 3, 14, {                    # 三档：紫色那套，14 级
		"HEAD": {"defense": 22.0},
		"BODY": {"life": 130.0, "speed": -6.0},   # 重甲拖慢你：取舍，不是白给
		"LEGS": {"defense": 14.0, "speed": 10.0},
		"FEET": {"speed": 26.0},
		"HANDS": {"attack": 5.0},
	}),
]
## 部位 → (Equipment.Slot 的序号, 套里排第几, 界面上叫什么)
PARTS = [
	("HEAD", 2, 0, "HELM"),
	("BODY", 3, 1, "VEST"),
	("LEGS", 4, 2, "PANTS"),
	("FEET", 5, 3, "BOOTS"),
	("HANDS", 6, 4, "GLOVES"),
]

## 枪和手雷：**复用现成的发射物**，只是更狠、更快。
## 新的发射物要配贴图和场景，那是另一摊事；`power` 和 `cooldown` 已经足够拉开档次。
WEAPONS = [
	# (文件名, 显示名, 门槛等级, 发射物, 冷却, 连发, 威力, look, 槽位, 图标)
	("rifle_mk2", "RIFLE MK2", 5, "res://scenes/bullet.tscn", 0.13, True, 1.5,
		"rifle", 0, "gear_rifle_mk2"),
	("plasma_rifle", "PLASMA RIFLE", 12, "res://scenes/bullet.tscn", 0.11, True, 2.4,
		"rifle", 0, "gear_plasma_rifle"),
	("cluster_bomb", "CLUSTER BOMB", 9, "res://scenes/grenade.tscn", 0.45, False, 1.8,
		"launcher", 1, "gear_cluster_bomb"),
]


def write(path, text):
	full = os.path.join(ROOT, path)
	os.makedirs(os.path.dirname(full), exist_ok=True)
	with open(full, "w", newline="\n", encoding="utf-8") as f:
		f.write(text)


def bonus_block(bonuses):
	inner = ", ".join('&"%s": %.1f' % (k, v) for k, v in bonuses.items())
	return "bonuses = Dictionary[StringName, float]({%s})" % inner


def build_armor():
	made = []
	for name, tier, level, parts in ARMOR_TIERS:
		for part, slot, offset, label in PARTS:
			icon = "gear_%s_%s" % (name.lower(), part.lower())
			body = "\n".join([
				'[gd_resource type="Resource" script_class="Equipment" format=3]',
				"",
				'[ext_resource type="Script" path="res://scripts/rpg/equipment.gd" id="1"]',
				'[ext_resource type="Texture2D" path="%s/%s.png" id="icon"]' % (ICONS, icon),
				"",
				"[resource]",
				'script = ExtResource("1")',
				'display_name = "%s %s"' % (name, label),
				"slot = %d" % slot,
				"price = %d" % price_at(level),
				"min_level = %d" % level,
				bonus_block(parts[part]),
				'icon = ExtResource("icon")',
				"",
			])
			file = "armor/%s_%s.tres" % (name.lower(), part.lower())
			write(file, body)
			made.append((file, price_at(level), level))
	return made


def build_weapons():
	made = []
	for file, label, level, projectile, cooldown, automatic, power, look, slot, icon in WEAPONS:
		lines = [
			'[gd_resource type="Resource" script_class="Weapon" format=3]',
			"",
			'[ext_resource type="Script" path="res://scripts/weapons/weapon.gd" id="1"]',
			'[ext_resource type="PackedScene" path="%s" id="2"]' % projectile,
			'[ext_resource type="Texture2D" path="%s/%s.png" id="icon"]' % (ICONS, icon),
			"",
			"[resource]",
			'script = ExtResource("1")',
			'display_name = "%s"' % label,
			'projectile = ExtResource("2")',
			"cooldown = %s" % cooldown,
			"automatic = %s" % ("true" if automatic else "false"),
			"max_ammo = -1",
			'fire_event = &"%s"' % ("player_shoot" if slot == 0 else "grenade_throw"),
			'look = &"%s"' % look,
			"slot = %d" % slot,
			"power = %s" % power,
			"price = %d" % price_at(level),
			"min_level = %d" % level,
			'icon = ExtResource("icon")',
			"",
		]
		if slot == 1:
			lines.insert(-2, "hud_color = Color(0.45, 0.65, 0.3, 1)")
		path = "weapons/%s.tres" % file
		write(path, "\n".join(lines))
		made.append((path, price_at(level), level))
	return made


def main():
	rows = build_armor() + build_weapons()
	rows.sort(key=lambda r: r[1])
	print("商店货单：%d 件" % len(rows))
	for path, price, level in rows:
		print("  %-34s %6d   %d 级起" % (path, price, level))


if __name__ == "__main__":
	main()
