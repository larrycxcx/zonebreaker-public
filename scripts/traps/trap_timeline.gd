class_name TrapTimeline
extends RefCounted
## 机关（液压机、闸门）的时间轴：8 帧，每帧停多久写在一张表里，循环播。
##
## **规则和画面用的是同一个帧号**：判定按这一帧的形状（从贴图量出来的表）算，外观只管把这一帧画出来，
## 所以换皮肤（占位色块 ↔ 素材贴图）规则一点不变。
## `phase` 让并排的几台错开节奏——一排液压机同时砸下来就只是一堵墙，错开了才是「看准空当冲过去」。


## 第 `time` 秒（加上错开的 `phase`）是第几帧。
static func frame_at(time: float, durations: Array[float], phase: float) -> int:
	var total := 0.0
	for d in durations:
		total += d
	var t := fposmod(time + phase, total)
	for i in durations.size():
		if t < durations[i]:
			return i
		t -= durations[i]
	return durations.size() - 1
