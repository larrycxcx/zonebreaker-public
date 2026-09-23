"""程序合成复古 8-bit 风格音效（思路同 sfxr/bfxr），输出到默认素材包 skins/default/sfx/*.wav。

只用 Python 标准库。每个音效是 SOUNDS 里的一组参数：一层或几层「声音」叠加，
每层有波形、音调滑动、颤音、音量包络、占空比等。想调某个声音就改这里的数字再运行：

    python tools/sfx_gen.py            # 生成全部
    python tools/sfx_gen.py jump       # 只生成名字里含 jump 的

文件名和游戏里的事件名对应（player_shoot、enemy_death……），对应关系写在 skins/default/default_skin.tres 里。
这些是占位音效：换正式素材时替换同名文件，或者新建一个素材包（见 CLAUDE.md「皮肤与素材包」）。
"""

import math
import os
import random
import struct
import sys
import wave

SAMPLE_RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "skins", "default", "sfx")

# 音名 → 频率（A4 = 440Hz），写旋律用。
NOTE = {
    name + str(octave): 440.0 * 2 ** ((i - 9) / 12 + (octave - 4))
    for octave in range(1, 8)
    for i, name in enumerate(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])
}


def voice(
    wave_type="square",      # square / triangle / saw / sine / noise
    freq=440.0,              # 起始频率
    freq_end=None,           # 结束频率（None = 不滑动），按指数曲线滑，听感更自然
    duration=0.2,            # 这一层总时长（秒）
    attack=0.0,              # 淡入
    decay=None,              # 从 attack 结束到消失的时间，默认用满剩余时长
    duty=0.5,                # 方波占空比：0.5 圆润，0.125 尖细
    duty_end=None,
    vibrato_depth=0.0,       # 颤音幅度（相对频率，0.05 = ±5%）
    vibrato_speed=0.0,       # 颤音速度（Hz）
    notes=None,              # 琶音/旋律：[(开始秒, 频率), ...]，覆盖 freq
    volume=1.0,
    offset=0.0,              # 这一层在整个音效里从第几秒开始
    crush=4,                 # 每 crush 个采样保持同一个值，模拟低采样率的颗粒感（1 = 不降）
    seed=1,
):
    return dict(locals())


def render_voice(v):
    rng = random.Random(v["seed"])
    n = int(v["duration"] * SAMPLE_RATE)
    decay = v["decay"] if v["decay"] is not None else v["duration"] - v["attack"]
    out = [0.0] * n
    phase = 0.0
    noise_value = rng.uniform(-1, 1)
    held = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        k = t / v["duration"]

        if v["notes"]:
            f = v["notes"][0][1]
            for start, note_freq in v["notes"]:
                if t >= start:
                    f = note_freq
        elif v["freq_end"] is not None:
            f = v["freq"] * (v["freq_end"] / v["freq"]) ** k
        else:
            f = v["freq"]
        if v["vibrato_depth"]:
            f *= 1.0 + v["vibrato_depth"] * math.sin(2 * math.pi * v["vibrato_speed"] * t)

        prev_phase = phase
        phase = (phase + f / SAMPLE_RATE) % 1.0
        duty = v["duty"] if v["duty_end"] is None else v["duty"] + (v["duty_end"] - v["duty"]) * k

        w = v["wave_type"]
        if w == "square":
            s = 1.0 if phase < duty else -1.0
        elif w == "triangle":
            s = 4.0 * abs(phase - 0.5) - 1.0
        elif w == "saw":
            s = 2.0 * phase - 1.0
        elif w == "sine":
            s = math.sin(2 * math.pi * phase)
        else:  # noise：每个周期换一个随机值，频率越高越「嘶」，越低越「轰」（同红白机噪声通道）
            if phase < prev_phase:
                noise_value = rng.uniform(-1, 1)
            s = noise_value

        if t < v["attack"]:
            env = t / v["attack"]
        else:
            env = max(0.0, 1.0 - (t - v["attack"]) / decay) if decay > 0 else 0.0
            env = env * env  # 平方衰减，比线性更像打击声

        if i % v["crush"] == 0:
            held = s * env * v["volume"]
        out[i] = held
    return out


def render(layers, peak=0.8):
    length = max(int((l["offset"] + l["duration"]) * SAMPLE_RATE) for l in layers)
    mix = [0.0] * length
    for layer in layers:
        start = int(layer["offset"] * SAMPLE_RATE)
        for i, s in enumerate(render_voice(layer)):
            mix[start + i] += s
    loudest = max(abs(s) for s in mix) or 1.0
    scale = peak / loudest
    # 结尾 5ms 淡出，避免截断处「咔哒」一声
    fade = int(0.005 * SAMPLE_RATE)
    for i in range(fade):
        mix[length - 1 - i] *= i / fade
    return [s * scale for s in mix]


def write_wav(path, samples):
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))


def shoot_variant(base, seed):
    return [
        voice("square", freq=base, freq_end=base * 0.25, duration=0.12, duty=0.25, duty_end=0.5, seed=seed),
        voice("noise", freq=6000, duration=0.035, volume=0.35, seed=seed),
    ]


# 事件名 → (说明, 声音层, 峰值音量)。峰值按「多常听到」调：开枪、命中这类高频声音压低一点。
SOUNDS = {
    # ---- 必须有 ----
    "player_shoot_1": ("玩家开枪（变体 1，三个轮流播放）", shoot_variant(1150, 11), 0.55),
    "player_shoot_2": ("玩家开枪（变体 2）", shoot_variant(1250, 12), 0.55),
    "player_shoot_3": ("玩家开枪（变体 3）", shoot_variant(1330, 13), 0.55),
    "jump": ("跳跃：短促上扬", [
        voice("square", freq=280, freq_end=720, duration=0.16, duty=0.5, duty_end=0.25),
    ], 0.6),
    "player_hurt": ("玩家受伤：颤抖着往下掉", [
        voice("square", freq=620, freq_end=180, duration=0.28, duty=0.5, vibrato_depth=0.25, vibrato_speed=35),
        voice("noise", freq=3000, duration=0.08, volume=0.5, seed=3),
    ], 0.75),
    "menu_move": ("菜单光标移动：一声轻轻的「嘀」", [
        voice("square", freq=880, duration=0.045, duty=0.25, volume=0.8),
    ], 0.35),
    "menu_select": ("菜单确认：两个上行音", [
        voice("square", duration=0.14, duty=0.5, decay=0.3,
              notes=[(0.0, NOTE["E5"]), (0.06, NOTE["A5"])]),
    ], 0.5),
    "menu_back": ("菜单返回：两个下行音", [
        voice("square", duration=0.14, duty=0.25, decay=0.3,
              notes=[(0.0, NOTE["A4"]), (0.06, NOTE["E4"])]),
    ], 0.45),
    "player_down": ("玩家倒地等人救（双人）：往下一沉，末尾留个还有救的尾音", [
        voice("square", freq=520, freq_end=150, duration=0.3, duty=0.25, vibrato_depth=0.15, vibrato_speed=14),
        voice("square", freq=190, freq_end=240, duration=0.22, duty=0.5, volume=0.45, offset=0.3),
    ], 0.7),
    "player_revive": ("被队友拉起来：往上一挑的三音", [
        voice("square", duration=0.3, duty=0.5, decay=0.4,
              notes=[(0.0, NOTE["D4"]), (0.08, NOTE["A4"]), (0.16, NOTE["D5"])]),
    ], 0.65),
    "player_death": ("玩家死亡：下行琶音后长长滑落", [
        voice("square", duration=0.36, duty=0.5, decay=0.5,
              notes=[(0.0, NOTE["C5"]), (0.09, NOTE["A4"]), (0.18, NOTE["F4"]), (0.27, NOTE["D4"])]),
        voice("square", freq=NOTE["D4"], freq_end=55, duration=0.9, duty=0.25, offset=0.36,
              vibrato_depth=0.08, vibrato_speed=8),
    ], 0.75),
    "enemy_shoot": ("敌人开枪（巡逻兵 A/B/C 共用）：比玩家的枪低沉、尖细", [
        voice("square", freq=720, freq_end=190, duration=0.14, duty=0.125),
        voice("noise", freq=4000, duration=0.03, volume=0.3, seed=5),
    ], 0.5),
    "enemy_hit": ("敌人被击中：短促的「嗒」", [
        voice("noise", freq=5000, duration=0.05, volume=0.8, seed=6),
        voice("square", freq=950, freq_end=600, duration=0.05, duty=0.5, volume=0.6),
    ], 0.55),
    "enemy_death": ("敌人死亡：小爆炸", [
        voice("noise", freq=2400, freq_end=180, duration=0.38, seed=7),
        voice("square", freq=420, freq_end=70, duration=0.3, duty=0.5, volume=0.5),
    ], 0.75),
    "bullet_impact": ("子弹打到墙/地面：轻轻的「嘶」", [
        voice("noise", freq=8000, freq_end=3000, duration=0.06, seed=8),
    ], 0.3),
    "game_over": ("游戏结束：下行三音 + 拖长的尾音", [
        voice("square", duration=0.66, duty=0.5, decay=0.8,
              notes=[(0.0, NOTE["G4"]), (0.22, NOTE["E4"]), (0.44, NOTE["C4"])]),
        voice("triangle", freq=NOTE["C3"], freq_end=NOTE["G2"], duration=0.7, offset=0.66,
              vibrato_depth=0.03, vibrato_speed=6, volume=1.2),
    ], 0.7),
    # ---- 建议加 ----
    "chaser_alert": ("D 发现玩家：两声急促的上扬「哔哔！」", [
        voice("square", freq=NOTE["A5"], duration=0.07, duty=0.5),
        voice("square", freq=NOTE["E6"], duration=0.1, duty=0.5, offset=0.09),
    ], 0.6),
    "enemy_prone": ("敌人趴下：低沉的「咚」+ 衣料声", [
        voice("triangle", freq=230, freq_end=100, duration=0.12, crush=2),
        voice("noise", freq=1500, duration=0.04, volume=0.4, seed=9),
    ], 0.6),
    "turret_shoot": ("炮台开火：更重、更闷的炮声", [
        voice("square", freq=420, freq_end=75, duration=0.24, duty=0.5),
        voice("noise", freq=1800, freq_end=300, duration=0.16, volume=0.7, seed=10),
    ], 0.65),
    "flyer_shoot": ("E 往下开火：从高处往下落的音调", [
        voice("triangle", freq=1500, freq_end=380, duration=0.2, vibrato_depth=0.06, vibrato_speed=30, crush=2),
    ], 0.55),
    # ---- 手雷 ----
    "grenade_throw": ("扔出手雷：短促的「嗖」", [
        voice("noise", freq=900, freq_end=3500, duration=0.14, attack=0.03, volume=0.7, seed=12),
        voice("triangle", freq=300, freq_end=520, duration=0.08, crush=2, volume=0.5),
    ], 0.4),
    "grenade_bounce": ("手雷落地弹一下：清脆的「叮」", [
        voice("triangle", freq=1100, freq_end=800, duration=0.06, crush=2),
        voice("noise", freq=6000, duration=0.02, volume=0.4, seed=13),
    ], 0.45),
    "explosion": ("手雷爆炸：比敌人死亡更大、更长", [
        voice("noise", freq=1600, freq_end=90, duration=0.65, seed=14),
        voice("square", freq=220, freq_end=40, duration=0.5, duty=0.5, volume=0.6),
        voice("noise", freq=5000, freq_end=1500, duration=0.08, volume=0.6, seed=15),
    ], 0.85),
    "weapon_switch": ("切换武器：短促的「咔哒」", [
        voice("square", freq=1400, freq_end=1800, duration=0.035, duty=0.25),
        voice("square", freq=900, duration=0.04, duty=0.25, offset=0.045),
        voice("noise", freq=7000, duration=0.015, volume=0.5, seed=16),
    ], 0.4),
    # ---- Boss ----
    "boss_appear": ("Boss 出场：两遍高低交替的警报 + 低音轰鸣", [
        voice("square", duration=0.84, duty=0.5, decay=2.0, volume=0.55,
              notes=[(0.0, 660), (0.18, 440), (0.36, 660), (0.54, 440)]),
        voice("triangle", freq=55, freq_end=45, duration=1.0, attack=0.1, volume=0.9),
    ], 0.75),
    # ---- 终极武器 ----
    "ultimate_start": ("终极武器发动：越来越高的蓄力声", [
        voice("square", freq=180, freq_end=1600, duration=0.9, duty=0.5, duty_end=0.125, vibrato_depth=0.04, vibrato_speed=18),
        voice("noise", freq=500, freq_end=4000, duration=0.9, attack=0.6, volume=0.35, seed=17),
    ], 0.6),
    "ultimate_blast": ("终极武器消灭敌人：很大很长的爆炸", [
        voice("noise", freq=1400, freq_end=50, duration=1.3, seed=18),
        voice("square", freq=160, freq_end=30, duration=1.1, duty=0.5, volume=0.7),
        voice("triangle", freq=90, freq_end=35, duration=1.2, volume=0.8, crush=2),
    ], 0.9),
    "stamina_exhausted": ("体力耗尽：两声往下的「累了」", [
        voice("triangle", freq=NOTE["E5"], duration=0.1, crush=2),
        voice("triangle", freq=NOTE["A4"], duration=0.16, offset=0.11, crush=2),
    ], 0.5),
}


def main():
    # 控制台编码不支持中文时（比如 cp1252）用 ? 代替，而不是崩掉；GBK / UTF-8 控制台照常显示中文。
    sys.stdout.reconfigure(errors="replace")
    os.makedirs(OUT_DIR, exist_ok=True)
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    for name, (desc, layers, peak) in SOUNDS.items():
        if only and only not in name:
            continue
        samples = render(layers, peak)
        write_wav(os.path.join(OUT_DIR, name + ".wav"), samples)
        rms = math.sqrt(sum(s * s for s in samples) / len(samples))
        print(f"{name:20s} {len(samples) / SAMPLE_RATE:5.2f}s  peak {max(abs(s) for s in samples):.2f}  rms {rms:.3f}  {desc}")


if __name__ == "__main__":
    main()
