class_name VisualFlip
extends RefCounted
## 外观左右翻转的共用做法：**不要用负的 `scale`**。
##
## 负 scale 会让 `Visual` 下的 Control（占位美术用的 ColorRect）算出错误的绘制矩形
## （`get_global_rect()` 的位置整整偏出一个身宽、高度是负的），引擎按这个矩形做屏幕剔除，
## 于是在某些位置整块外观会被当成「在屏幕外」直接不画——表现为 Boss A 跳到空中时偶尔整个消失。
## 每个角色都是这么翻转的，只是 Boss A 体积最大、跳得最高，才把问题暴露出来。
##
## 这里改成保持 scale 为正，把 `Visual` 下每个子节点的横向位置镜像过去：
## 方块（Control）按 `-x - 宽度` 镜像（镜像的是整块矩形），枪口之类的点（Node2D）按 `-x` 镜像。
## 场景里一律按**朝右**的摆法来摆。


## 记下 Visual 下每个子节点的原始横向位置，在翻转之前调用一次（一般在 _ready 里）。
static func capture(visual: Node2D) -> Dictionary:
	var bases := {}
	for child in visual.get_children():
		if child is Control:
			bases[child] = (child as Control).position.x
		elif child is Node2D:
			bases[child] = (child as Node2D).position.x
	return bases


## 按朝向摆放：facing = 1 用原始位置，facing = -1 镜像。
static func apply(bases: Dictionary, facing: int) -> void:
	for child in bases:
		var base: float = bases[child]
		if child is Control:
			var rect := child as Control
			rect.position.x = base if facing > 0 else -base - rect.size.x
		else:
			(child as Node2D).position.x = base if facing > 0 else -base


## 把会转动的枪管（占位美术）指向 direction。
## 枪管场景里按「朝右、从身体伸出去」摆；转动中心取靠身体那一端，朝左时它在矩形的右边。
static func aim_gun(gun: Control, facing: int, direction: Vector2) -> void:
	gun.pivot_offset = Vector2(0.0 if facing > 0 else gun.size.x, gun.size.y / 2.0)
	# 朝左时矩形本身已经镜像过去了（自身的 +x 指向身体），所以要多转半圈。
	gun.rotation = direction.angle() - (0.0 if facing > 0 else PI)
