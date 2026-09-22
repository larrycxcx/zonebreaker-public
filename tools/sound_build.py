"""从音效包生成赛博朋克皮肤包的音效和音乐，输出到 skins/cyberpunk/sfx/ 和 skins/cyberpunk/music/。

    python tools/sound_build.py            # 全部重新生成
    python tools/sound_build.py --check    # 只检查，不写文件

素材来源：CraftPix 的音效包（art_in/default/sound/，不进仓库）：29 个音效（44.1kHz 16bit 立体声 WAV）+ 5 首音乐。
包里不少音效和这个游戏无关（狗叫、乌鸦、开关门），能对上的按 `SOUNDS` 表处理：
- **去掉开头的静音**，再按需要**截短**（结尾 30ms 淡出，免得咔哒一声）。连发的枪声原本 0.88 秒，截到 0.2 秒，
  否则一串子弹的声音糊成一片；终极武器定格的声音截到 2 秒，正好是定格的时长。
- **变调不做任何音频处理**：只改 WAV 头里的采样率（`rate`）。0.8 = 播得慢一点、音调低一点——巡逻兵和炮台用同一个激光声，
  靠降调和玩家的分开；手雷弹地用升调的 Bump。
- `gain` 是音量倍数：开枪这种每秒响好几下的放轻一点。
包里对不上的事件（跳跃、体力耗尽、敌人趴下、D 发现玩家）不输出，素材包里不填，照旧回落到默认包的 8-bit 音效。

音乐：MP3 原样复制（`MUSIC`），关卡用 Track Greenzone（和地形包是配套的），Boss 出场切到节奏最紧的 Track Race。
"""
import os
import shutil
import struct
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.join(HERE, "..", "art_in", "default", "sound")
OUT = os.path.join(HERE, "..", "skins", "cyberpunk")

# 事件 → (源文件, 截到几秒（None 不截）, 采样率倍数, 音量倍数)
SOUNDS = {
	"player_shoot": ("Blaster laser", 0.2, 1.0, 0.55),
	"enemy_shoot": ("Blaster laser", 0.2, 0.8, 0.5),
	"turret_shoot": ("Blaster laser", 0.25, 0.62, 0.6),
	"flyer_shoot": ("Thunderbolt", 0.35, 1.0, 0.7),
	"bullet_impact": ("Bump", 0.18, 1.0, 0.6),
	"grenade_bounce": ("Bump", 0.18, 1.35, 0.7),
	"enemy_hit": ("Punch", 0.3, 1.0, 0.7),
	"enemy_death": ("Dead2", None, 1.0, 0.8),
	"player_hurt": ("Groans", None, 1.0, 0.9),
	"player_death": ("Dead1", None, 1.0, 0.9),
	"explosion": ("Explosion", None, 1.0, 0.9),
	"ultimate_start": ("Thunderbolt", 2.0, 1.0, 0.8),
	"ultimate_blast": ("Explosion2", None, 1.0, 1.0),
	"boss_appear": ("Warning_loopable", 1.7, 1.0, 0.7),
	"grenade_throw": ("flamethrower", 0.35, 1.0, 0.7),
	"weapon_switch": ("Press", 0.3, 1.0, 0.6),
	"game_over": ("Access denied", None, 1.0, 0.9),
}
MUSIC = {"level": "Track greenzone", "boss": "Track race"}
SILENCE = 300    # 开头低于这个振幅（16bit）的都当静音去掉
FADE = 0.03      # 结尾淡出几秒


def read(name):
	with wave.open(os.path.join(PACK, "Sounds", name + ".wav")) as w:
		assert w.getsampwidth() == 2, "%s 不是 16bit" % name
		channels, rate = w.getnchannels(), w.getframerate()
		raw = w.readframes(w.getnframes())
	samples = list(struct.unpack("<%dh" % (len(raw) // 2), raw))
	return channels, rate, samples


def process(name, seconds, rate_scale, gain):
	channels, rate, samples = read(name)
	frames = len(samples) // channels
	start = next((f for f in range(frames) if max(abs(samples[f * channels + c]) for c in range(channels)) > SILENCE), 0)
	end = frames if seconds is None else min(frames, start + int(seconds * rate))
	fade = int(FADE * rate)
	out = []
	for f in range(start, end):
		k = gain * min(1.0, (end - f) / fade) if fade > 0 else gain
		for c in range(channels):
			out.append(max(-32768, min(32767, int(samples[f * channels + c] * k))))
	return channels, int(round(rate * rate_scale)), out


def save(path, channels, rate, samples):
	os.makedirs(os.path.dirname(path), exist_ok=True)
	with wave.open(path, "wb") as w:
		w.setnchannels(channels)
		w.setsampwidth(2)
		w.setframerate(rate)
		w.writeframes(struct.pack("<%dh" % len(samples), *samples))


def main():
	write = "--check" not in sys.argv
	if not os.path.isdir(PACK):
		sys.exit("找不到音效素材 %s（它不在仓库里，要自己解压进去）" % os.path.normpath(PACK))
	print("音效：")
	for event, (name, seconds, rate_scale, gain) in SOUNDS.items():
		channels, rate, samples = process(name, seconds, rate_scale, gain)
		if write:
			save(os.path.join(OUT, "sfx", event + ".wav"), channels, rate, samples)
		print("  sfx/%s.wav  %.2fs  ← %s" % (event, len(samples) / channels / rate, name))
	print("音乐：")
	for key, name in MUSIC.items():
		if write:
			os.makedirs(os.path.join(OUT, "music"), exist_ok=True)
			shutil.copyfile(os.path.join(PACK, "Music", "MP3", name + ".mp3"), os.path.join(OUT, "music", key + ".mp3"))
		print("  music/%s.mp3  ← %s" % (key, name))


if __name__ == "__main__":
	main()
