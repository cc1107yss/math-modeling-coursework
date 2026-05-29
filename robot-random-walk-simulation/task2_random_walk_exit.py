# -*- coding: utf-8 -*-
"""
任务二
----------------------------------
如果房间有一个出口，扫地机器人在里面随意移动，
仿真计算它移动到出口的可能性和所需要的平均时间。

1. 房间大小为 M 行 N 列，包含四周墙壁；
2. 门的位置设为左侧第 4 排；
3. 初始位置设为房间中心；
4. 若机器人位于“门口右侧紧挨着的位置”，则下一步走出房间；
5. 其余情况按 PPT 给出的内部 / 墙角 / 墙边规则等概率随机移动；
6. 多次重复实验，统计成功概率、平均步数、方差；
7. 额外保存一个演示 GIF 动图，以及详细数据表和汇总数据表。

代码特点：
- 只依赖 numpy + pillow；
- GIF 会保存下来，macOS 下默认会自动打开 GIF；
"""

# ==============================
# 一、导入需要的库
# ==============================
# os / pathlib：处理文件和文件夹路径
# csv：把结果写成 CSV 表格
# subprocess / platform：在不同系统上尝试自动打开 GIF
# dataclasses：把单次实验结果打包成更清晰的数据结构
# typing：类型提示，便于阅读
# numpy：随机数、数组、均值、方差等计算
# PIL：用来画网格图并保存 GIF
import csv
import os
import platform
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
from PIL import Image, ImageDraw


# ==============================
# 二、类型与常量
# ==============================
# Position 表示一个二维坐标 (行, 列)
Position = Tuple[int, int]

# RGB 颜色
BLACK = (0, 0, 0)          # 墙：黑色
WHITE = (255, 255, 255)    # 空地：白色
GREEN = (0, 180, 0)        # 门：绿色
RED = (255, 0, 0)          # 机器人：红色
GRAY = (180, 180, 180)     # 网格线：灰色
TEXT_BG = (245, 245, 245)  # 顶部文字背景：浅灰
BLUE = (0, 100, 255)       # 统计图线：蓝色

# 按 PPT 的九宫格编号建立方向表：
# 1 左上, 2 上, 3 右上, 4 左, 5 右, 6 左下, 7 下, 8 右下
# 行号向下增大，列号向右增大。
DIRECTION_OFFSETS: Dict[int, Tuple[int, int]] = {
    1: (-1, -1),
    2: (-1, 0),
    3: (-1, 1),
    4: (0, -1),
    5: (0, 1),
    6: (1, -1),
    7: (1, 0),
    8: (1, 1),
}


# ==============================
# 三、单次实验结果的数据结构
# ==============================
# @dataclass 是 Python 里很适合“存一组相关数据”的写法。
# 它会自动帮你生成初始化函数，让代码更清晰。
@dataclass
class TrialResult:
    m: int
    n: int
    trial_id: int
    success: bool
    steps: int
    path_length_inside_room: int


# ==============================
# 四、输出文件夹
# ==============================
def get_output_dir(folder_name: str = "task2_output_final") -> Path:
    """创建并返回输出文件夹路径。"""
    try:
        # 在普通 .py 脚本里，__file__ 表示当前脚本路径。
        base_dir = Path(__file__).resolve().parent
    except NameError:
        # 在某些交互环境里，__file__ 可能不存在，这时退回当前工作目录。
        base_dir = Path.cwd()

    output_dir = base_dir / folder_name
    output_dir.mkdir(parents=True, exist_ok=True)
    return output_dir


# ==============================
# 五、建房间：四周墙 + 左侧第4排是门 + 中心起点
# ==============================
def build_room(m: int, n: int, door_row_1_based: int = 4) -> Tuple[np.ndarray, Position, Position]:
    """
    返回：
    - wall：布尔矩阵，True 表示墙
    - door：门坐标（Python 0 基坐标）
    - start：机器人起点（房间中心）
    """
    wall = np.zeros((m, n), dtype=bool)

    # 给四周赋值为墙
    wall[0, :] = True
    wall[m - 1, :] = True
    wall[:, 0] = True
    wall[:, n - 1] = True

    # PPT 中门设在“左侧第4排”，MATLAB 是 1 基，所以 Python 要减 1。
    door = (door_row_1_based - 1, 0)
    wall[door] = False  # 门不是墙

    # 起点设在房间中心
    start = (m // 2, n // 2)
    return wall, door, start


# ==============================
# 六、判断机器人属于内部 / 墙边 / 墙角哪一类
# ==============================
def classify_position(pos: Position, m: int, n: int, door: Position) -> str:
    """
    机器人站的是“可走格”，不是墙格，所以：
    - 靠近上墙的位置是 r == 1
    - 靠近左墙的位置是 c == 1

    这里额外把“门口右侧紧挨着的位置”单独标出来，
    因为规则说：在这个位置，下一步直接走出房间。
    """
    r, c = pos

    # 门在左边界，所以门口右侧紧挨着的位置是 (door_row, 1)
    if pos == (door[0], door[1] + 1):
        return "next_to_door"

    top = (r == 1)
    bottom = (r == m - 2)
    left = (c == 1)
    right = (c == n - 2)

    if top and left:
        return "top_left_corner"
    if top and right:
        return "top_right_corner"
    if bottom and left:
        return "bottom_left_corner"
    if bottom and right:
        return "bottom_right_corner"
    if top:
        return "top_edge"
    if bottom:
        return "bottom_edge"
    if left:
        return "left_edge"
    if right:
        return "right_edge"
    return "inner"


# ==============================
# 七、严格按 PPT 给出可选方向
# ==============================
def allowed_direction_ids(pos: Position, m: int, n: int, door: Position) -> List[int]:
    """
    返回一个列表，表示当前位置允许随机选择的方向编号。
    """
    state = classify_position(pos, m, n, door)

    if state == "inner":
        return [1, 2, 3, 4, 5, 6, 7, 8]
    if state == "top_left_corner":
        return [5, 7, 8]
    if state == "top_right_corner":
        return [4, 6, 7]
    if state == "bottom_left_corner":
        return [2, 3, 5]
    if state == "bottom_right_corner":
        return [1, 2, 4]
    if state == "top_edge":
        return [4, 5, 6, 7, 8]
    if state == "bottom_edge":
        return [1, 2, 3, 4, 5]
    if state == "left_edge":
        return [2, 3, 5, 7, 8]
    if state == "right_edge":
        return [1, 2, 4, 6, 7]

    # next_to_door 的情况不在这里走普通随机移动，
    # 而是在下一步直接判定出房间，所以返回空列表。
    return []


# ==============================
# 八、按 PPT 规则随机走一步
# ==============================
def random_step_ppt(current: Position, m: int, n: int, door: Position,
                    rng: np.random.Generator) -> Optional[Position]:
    """
    返回值有两种：
    - 返回一个坐标，表示下一步仍在房间内
    - 返回 None，表示下一步已经走出房间
    """
    state = classify_position(current, m, n, door)

    # 规则：若在门口右侧紧挨着的位置，则下一步走出房间
    if state == "next_to_door":
        return None

    allowed_ids = allowed_direction_ids(current, m, n, door)

    # rng.choice(...) 表示“从列表里等概率随机抽一个元素”
    direction_id = int(rng.choice(allowed_ids))
    dr, dc = DIRECTION_OFFSETS[direction_id]

    nr = current[0] + dr
    nc = current[1] + dc
    return (nr, nc)


# ==============================
# 九、把当前状态画成一帧图像
# ==============================
def draw_room_frame(m: int,
                    n: int,
                    wall: np.ndarray,
                    door: Position,
                    robot_pos: Position,
                    step: int,
                    dt: float,
                    cell_size: int = None,
                    top_bar_height: int = 48) -> Image.Image:
    """
    使用 Pillow 画一帧图片。
    
    自动根据房间大小调整 cell_size 以保持图片合理大小：
    - 11x9 房间：28 像素/格子
    - 21x17 房间：16 像素/格子
    - 31x25 房间：12 像素/格子
    """
    # 自动计算合理的 cell_size
    if cell_size is None:
        if m <= 11 and n <= 9:
            cell_size = 28
        elif m <= 21 and n <= 17:
            cell_size = 16
        else:
            cell_size = 12
    width = n * cell_size
    height = m * cell_size + top_bar_height

    img = Image.new("RGB", (width, height), WHITE)
    draw = ImageDraw.Draw(img)

    # 顶部文字背景条
    draw.rectangle([0, 0, width, top_bar_height], fill=TEXT_BG)

    # 这里把 Python 的 0 基坐标改回更直观的 1 基坐标显示
    r_show = robot_pos[0] + 1
    c_show = robot_pos[1] + 1
    t_seconds = step * dt

    text = f"random walk, step={step}, t={t_seconds:.1f}s, pos=({r_show},{c_show})"
    draw.text((10, 14), text, fill=(0, 0, 0))

    # 逐格绘图
    for r in range(m):
        for c in range(n):
            color = WHITE
            if wall[r, c]:
                color = BLACK
            if (r, c) == door:
                color = GREEN
            if (r, c) == robot_pos:
                color = RED

            x0 = c * cell_size
            y0 = r * cell_size + top_bar_height
            x1 = x0 + cell_size
            y1 = y0 + cell_size
            draw.rectangle([x0, y0, x1, y1], fill=color, outline=GRAY)

    return img


# ==============================
# 十、模拟一次实验
# ==============================
def simulate_one_trial(m: int,
                       n: int,
                       max_steps: int,
                       rng: np.random.Generator,
                       dt: float = 1.0,
                       save_frames: bool = False,
                       frame_every: int = 1) -> Tuple[bool, int, List[Position], List[Image.Image]]:
    """
    模拟一次随机游动。

    返回：
    - success：是否成功走出房间
    - steps：成功时的步数；失败时返回 max_steps
    - path：房间内经过的轨迹坐标
    - frames：用于做 GIF 的所有帧
    """
    wall, door, start = build_room(m, n)
    current = start
    path: List[Position] = [current]
    frames: List[Image.Image] = []

    if save_frames:
        frames.append(draw_room_frame(m, n, wall, door, current, step=0, dt=dt))

    for step in range(1, max_steps + 1):
        next_pos = random_step_ppt(current, m, n, door, rng)

        # 若下一步出房间，则本次实验成功结束
        if next_pos is None:
            return True, step, path, frames

        current = next_pos
        path.append(current)

        if save_frames and step % frame_every == 0:
            frames.append(draw_room_frame(m, n, wall, door, current, step=step, dt=dt))

    # 达到最大步数还没出房间，视为失败
    return False, max_steps, path, frames


# ==============================
# 十一、保存 GIF
# ==============================
def save_gif(frames: List[Image.Image], save_path: Path, duration_ms: int = 180) -> None:
    """把多帧图片保存为 GIF 动图。"""
    if not frames:
        return

    frames[0].save(
        save_path,
        save_all=True,
        append_images=frames[1:],
        duration=duration_ms,
        loop=0,
    )


# ==============================
# 十二、保存 CSV
# ==============================
def save_detailed_csv(rows: List[TrialResult], save_path: Path) -> None:
    """保存每次实验一行的详细结果表。"""
    with open(save_path, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow(["M", "N", "trial_id", "success", "steps", "path_length_inside_room"])
        for row in rows:
            writer.writerow([
                row.m,
                row.n,
                row.trial_id,
                "是" if row.success else "否",
                row.steps,
                row.path_length_inside_room,
            ])


# ==============================
# 十三、重复实验并做统计
# ==============================
def run_experiment(room_sizes: List[Tuple[int, int]],
                   n_trials: int,
                   max_steps: int,
                   seed: int) -> Tuple[List[TrialResult], List[Dict[str, float]]]:
    """
    对多组房间大小重复做实验。

    这里“数据收集”的两种思路：
    1. 已知一共做 n_trials 次，可以先分配数组空间；
    2. 每次实验结果逐条 append 到列表里。
    """
    rng = np.random.default_rng(seed)

    detailed_rows: List[TrialResult] = []
    summary_rows: List[Dict[str, float]] = []

    for m, n in room_sizes:
        # 已知实验次数 -> 先分配数组
        success_flags = np.zeros(n_trials, dtype=int)
        steps_array = np.full(n_trials, np.nan)

        for trial_id in range(1, n_trials + 1):
            success, steps, path, _ = simulate_one_trial(
                m=m,
                n=n,
                max_steps=max_steps,
                rng=rng,
                save_frames=False,
            )

            idx = trial_id - 1
            success_flags[idx] = 1 if success else 0
            if success:
                steps_array[idx] = steps

            detailed_rows.append(
                TrialResult(
                    m=m,
                    n=n,
                    trial_id=trial_id,
                    success=success,
                    steps=steps,
                    path_length_inside_room=len(path),
                )
            )

        success_count = int(np.sum(success_flags))
        exit_probability = float(np.mean(success_flags))

        # np.nanmean / np.nanvar 会自动忽略失败样本的 nan
        if success_count > 0:
            mean_steps = float(np.nanmean(steps_array))
            var_steps = float(np.nanvar(steps_array))
        else:
            mean_steps = float("nan")
            var_steps = float("nan")

        summary_rows.append(
            {
                "M": m,
                "N": n,
                "n_trials": n_trials,
                "success_count": success_count,
                "exit_probability": exit_probability,
                "mean_steps_success_only": mean_steps,
                "var_steps_success_only": var_steps,
                "max_steps": max_steps,
            }
        )

    return detailed_rows, summary_rows


# ==============================
# 十四、保存汇总表
# ==============================
def save_summary_csv(summary_rows: List[Dict[str, float]], save_path: Path) -> None:
    """保存每种房间大小一行的汇总表。"""
    with open(save_path, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        writer.writerow([
            "M", "N", "n_trials", "success_count", "exit_probability",
            "mean_steps_success_only", "var_steps_success_only", "max_steps"
        ])
        for row in summary_rows:
            writer.writerow([
                row["M"], row["N"], row["n_trials"], row["success_count"],
                f"{row['exit_probability']:.6f}",
                "" if np.isnan(row["mean_steps_success_only"]) else f"{row['mean_steps_success_only']:.6f}",
                "" if np.isnan(row["var_steps_success_only"]) else f"{row['var_steps_success_only']:.6f}",
                row["max_steps"],
            ])


# ==============================
# 十五、生成统计收敛动画
# ==============================
def create_convergence_animation(detailed_rows: List[TrialResult], 
                                  save_path: Path,
                                  room_m: int,
                                  room_n: int,
                                  duration_ms: int = 100) -> None:
    """
    生成一个动画，展示该房间大小的成功概率随着实验次数增加而逐步收敛的过程。
    """
    # 筛选出该房间大小的结果
    room_data = [r for r in detailed_rows if r.m == room_m and r.n == room_n]
    if not room_data:
        return
    
    # 计算累积成功概率
    cumsum_success = 0
    cum_probabilities = []
    for row in room_data:
        cumsum_success += (1 if row.success else 0)
        cum_prob = cumsum_success / (row.trial_id)
        cum_probabilities.append(cum_prob)
    
    n_trials = len(room_data)
    
    # 生成动画帧
    frames = []
    
    # 图表参数
    width, height = 600, 400
    margin = 60
    plot_width = width - 2 * margin
    plot_height = height - 2 * margin
    
    for frame_idx in range(0, n_trials, max(1, n_trials // 30)):  # 最多30帧，避免GIF过大
        img = Image.new("RGB", (width, height), WHITE)
        draw = ImageDraw.Draw(img)
        
        # 背景
        draw.rectangle([margin, margin, width - margin, height - margin], 
                      outline=BLACK, width=2)
        
        # 标题
        draw.text((width // 2 - 80, 20), f"房间 {room_m}x{room_n} 成功概率收敛过程", 
                 fill=BLACK)
        
        # 轴标签
        draw.text((10, height - margin + 10), "试验次数", fill=BLACK)
        draw.text((10, margin - 30), "成功概率", fill=BLACK)
        
        # 绘制已有的数据点和连线
        prev_x, prev_y = None, None
        for trial_idx in range(min(frame_idx + 1, n_trials)):
            trial_num = trial_idx + 1
            prob = cum_probabilities[trial_idx]
            
            # 坐标转换（屏幕坐标系）
            x = margin + (trial_num / n_trials) * plot_width
            y = height - margin - (prob / 1.0) * plot_height
            
            # 绘制连线
            if prev_x is not None:
                draw.line([(prev_x, prev_y), (x, y)], fill=BLUE, width=2)
            
            # 绘制点
            r = 3
            draw.ellipse([x - r, y - r, x + r, y + r], fill=RED)
            
            prev_x, prev_y = x, y
        
        # 显示当前进度
        current_trial = min(frame_idx + 1, n_trials)
        current_prob = cum_probabilities[frame_idx] if frame_idx < n_trials else cum_probabilities[-1]
        progress_text = f"进度: {current_trial}/{n_trials} 次 | 当前成功概率: {current_prob:.4f}"
        draw.text((margin, height - margin + 40), progress_text, fill=BLACK)
        
        frames.append(img)
    
    # 保存最后一帧（完整统计结果）
    if frames:
        save_gif(frames, save_path, duration_ms=duration_ms)
def try_open_file(path: Path) -> None:
    """
    """
    try:
        system_name = platform.system()
        if system_name == "Darwin":
            subprocess.run(["open", str(path)], check=False)
        elif system_name == "Windows":
            os.startfile(str(path))  # type: ignore[attr-defined]
        elif system_name == "Linux":
            subprocess.run(["xdg-open", str(path)], check=False)
    except Exception:
        # 就算打开失败，也不影响主程序保存结果。
        pass


# ==============================
# 十六、主函数
# ==============================
def main() -> None:
    """主程序入口。"""
    output_dir = get_output_dir("task2_output_final")

    # ---------- 1）先做多个演示 GIF，展示不同房间大小的随机游走 ----------
    demo_configs = [
        (11, 9, 2026, "演示房间_11x9"),
        (21, 17, 2027, "演示房间_21x17"),
        (31, 25, 2028, "演示房间_31x25"),
    ]
    
    print("\n" + "=" * 60)
    print("正在生成演示动图...")
    print("=" * 60)
    
    for demo_m, demo_n, demo_seed, demo_name in demo_configs:
        demo_rng = np.random.default_rng(demo_seed)
        
        # 对小房间重新生成直到轨迹足够长（至少需要200帧），来展示有趣的随机游走
        if demo_m <= 11 and demo_n <= 9:
            # 小房间容易快速到达出口，所以我们生成多个直到找到一个相对较长的
            best_frames = []
            best_steps = 0
            for attempt in range(20):  # 最多尝试20次
                _, steps, _, frames = simulate_one_trial(
                    m=demo_m,
                    n=demo_n,
                    max_steps=1000,
                    rng=demo_rng,
                    dt=1.0,
                    save_frames=True,
                    frame_every=1,  # 小房间记录所有帧
                )
                if len(frames) > len(best_frames):
                    best_frames = frames
                    best_steps = steps
                if len(frames) >= 200:  # 达到200帧就停止
                    break
            demo_success = best_steps < 1000
            demo_frames = best_frames
            demo_steps = best_steps
        else:
            demo_success, demo_steps, demo_path, demo_frames = simulate_one_trial(
                m=demo_m,
                n=demo_n,
                max_steps=1000,
                rng=demo_rng,
                dt=1.0,
                save_frames=True,
                frame_every=2,
            )
        
        gif_name = f"task2_demo_{demo_m}x{demo_n}.gif"
        gif_path = output_dir / gif_name
        save_gif(demo_frames, gif_path, duration_ms=150)
        
        print(f"✓ {gif_name} 已生成 ({len(demo_frames)} 帧, 成功: {'是' if demo_success else '否'}, {demo_steps} 步)")
    
    print("=" * 60)

    # ---------- 2）正式做数据收集 ----------
    print("正在采集实验数据，这会花费一点时间...")
    print("=" * 60)
    
    # 按示例，比较几组房间大小
    room_sizes = [(11, 9), (21, 17), (31, 25)]
    n_trials = 30
    max_steps = 100000
    stats_seed = 2027

    detailed_rows, summary_rows = run_experiment(
        room_sizes=room_sizes,
        n_trials=n_trials,
        max_steps=max_steps,
        seed=stats_seed,
    )

    detailed_csv_path = output_dir / "task2_detailed_results.csv"
    summary_csv_path = output_dir / "task2_summary.csv"

    save_detailed_csv(detailed_rows, detailed_csv_path)
    save_summary_csv(summary_rows, summary_csv_path)
    
    # 生成统计收敛动画
    print("\n" + "=" * 60)
    print("正在生成统计收敛演示动画...")
    print("=" * 60)
    for m, n in room_sizes:
        anim_path = output_dir / f"task2_convergence_{m}x{n}.gif"
        create_convergence_animation(detailed_rows, anim_path, m, n, duration_ms=100)
        print(f"✓ task2_convergence_{m}x{n}.gif 已生成")

    # ---------- 3）在终端打印结果 ----------
    print("\n" + "=" * 60)
    print("任务二运行完成！")
    print("=" * 60)
    print("\n📺 生成的动图演示：")
    print("  随机游走演示（3个不同房间大小）：")
    print("    • task2_demo_11x9.gif")
    print("    • task2_demo_21x17.gif")
    print("    • task2_demo_31x25.gif")
    print("  成功概率收敛动画（展示实验过程）：")
    print("    • task2_convergence_11x9.gif")
    print("    • task2_convergence_21x17.gif")
    print("    • task2_convergence_31x25.gif")
    print("\n📊 生成的数据表：")
    print(f"  • 详细数据表: task2_detailed_results.csv")
    print(f"  • 汇总统计表: task2_summary.csv")
    print("\n📈 汇总统计结果：")
    for row in summary_rows:
        mean_steps_str = "nan" if np.isnan(row["mean_steps_success_only"]) else f"{row['mean_steps_success_only']:.2f}"
        var_steps_str = "nan" if np.isnan(row["var_steps_success_only"]) else f"{row['var_steps_success_only']:.2f}"
        print(
            f"\n  房间 {int(row['M'])}×{int(row['N'])}:"
            f"\n    ├─ 成功次数：{int(row['success_count'])}/{int(row['n_trials'])} 次"
            f"\n    ├─ 成功概率：{row['exit_probability']:.4f}"
            f"\n    ├─ 平均步数（仅成功样本）：{mean_steps_str}"
            f"\n    └─ 步数方差（仅成功样本）：{var_steps_str}"
        )
    print("\n" + "=" * 60)

    # ---------- 4）自动打开演示动图 ----------
    first_demo_gif = output_dir / "task2_demo_11x9.gif"
    if first_demo_gif.exists():
        print("💫 正在打开演示动图...")
        try_open_file(first_demo_gif)
    print("✅ 所有文件已保存到:", output_dir)


# Python 的标准写法：
# 只有当这个文件被“直接运行”时，才执行 main()。
# 如果它被别的文件 import 进来，就不会自动运行。
if __name__ == "__main__":
    main()
