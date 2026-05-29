# -*- coding: utf-8 -*-

import os
import random
from typing import List, Tuple

import imageio.v2 as imageio
import matplotlib.pyplot as plt
import numpy as np

Position = Tuple[int, int]

# 8 邻域编号
# 1 左上  2 上  3 右上
# 4 左    5 右
# 6 左下  7 下  8 右下
DIRECTION_OFFSETS = {
    1: (-1, -1),
    2: (-1, 0),
    3: (-1, 1),
    4: (0, -1),
    5: (0, 1),
    6: (1, -1),
    7: (1, 0),
    8: (1, 1),
}


def build_classroom_from_ppt(seed = None):
    """设置教室、门口、讲台和桌椅。"""
    if seed is not None:
        random.seed(seed)
        np.random.seed(seed)

    rows, cols = 22, 18
    door: Position = (3, 0)  # MATLAB 的 (4,1) -> Python 的 (3,0)
    big_m = int(np.ceil(np.sqrt(rows ** 2 + cols ** 2)))

    row_index = np.arange(rows)[:, None]
    col_index = np.arange(cols)[None, :]
    weights = np.sqrt((row_index - door[0]) ** 2 + (col_index - door[1]) ** 2)

    obstacle = np.zeros((rows, cols), dtype=bool)

    # 四周墙壁
    obstacle[0, :] = True
    obstacle[-1, :] = True
    obstacle[:, 0] = True
    obstacle[:, -1] = True

    # 讲台障碍：A([4 5],[8 9 10 11])=M
    obstacle[3:5, 7:11] = True

    # 桌椅障碍：A(7:2:19,[4 5 8 9 10 11 14 15])=M
    desk_rows = [6, 8, 10, 12, 14, 16, 18]
    desk_cols = [3, 4, 7, 8, 9, 10, 13, 14]
    for r in desk_rows:
        obstacle[r, desk_cols] = True

    # 门口不是障碍
    obstacle[door] = False

    # 墙壁和障碍赋成大权重
    weights[obstacle] = big_m
    weights[door] = 0.0

    # 随机产生内部起点，但不能落在障碍和门上
    while True:
        start = (np.random.randint(1, 21), np.random.randint(1, 17))
        if (not obstacle[start]) and (start != door):
            break

    return weights, obstacle, door, start, big_m


def in_bounds(pos: Position, rows: int, cols: int) -> bool:
    """判断坐标是否还在矩阵范围内。"""
    r, c = pos
    return 0 <= r < rows and 0 <= c < cols


def make_rgb_image(obstacle: np.ndarray, door: Position, robot: Position) -> np.ndarray:
    """把障碍/门/机器人转成 RGB 图像矩阵。"""
    rows, cols = obstacle.shape
    image = np.ones((rows, cols, 3), dtype=float)  # 先全部设成白色
    image[obstacle] = np.array([0.0, 0.0, 0.0])   # 黑色障碍
    image[door] = np.array([0.0, 1.0, 0.0])       # 绿色门口
    image[robot] = np.array([1.0, 0.0, 0.0])      # 红色机器人
    return image


def choose_next_step_ppt(current: Position, weights: np.ndarray, obstacle: np.ndarray, door: Position) -> Position:
   
    rows, cols = obstacle.shape
    r, c = current

    candidates: List[Position] = []
    for direction_id in range(1, 9):
        dr, dc = DIRECTION_OFFSETS[direction_id]
        next_pos = (r + dr, c + dc)
        if in_bounds(next_pos, rows, cols) and (not obstacle[next_pos]):
            candidates.append(next_pos)

    if not candidates:
        return current

    candidate_weights = [weights[pos] for pos in candidates]
    min_weight = min(candidate_weights)
    best_positions = [pos for pos in candidates if np.isclose(weights[pos], min_weight)]
    chosen = random.choice(best_positions)

    # 若最优位置就是门口
    if chosen == door:
        # 门在机器人的左上方：先向上走
        if current == (door[0] + 1, door[1] + 1):
            up = (r - 1, c)
            if in_bounds(up, rows, cols) and (not obstacle[up]):
                return up

        # 门在机器人的左下方：先向下走
        if current == (door[0] - 1, door[1] + 1):
            down = (r + 1, c)
            if in_bounds(down, rows, cols) and (not obstacle[down]):
                return down

        return chosen

    dr = chosen[0] - r
    dc = chosen[1] - c

    # 左上角最优时的特殊判断
    if (dr, dc) == (-1, -1):
        left = (r, c - 1)
        up = (r - 1, c)
        left_blocked = (not in_bounds(left, rows, cols)) or obstacle[left]
        up_blocked = (not in_bounds(up, rows, cols)) or obstacle[up]

        if left_blocked and (not up_blocked):
            return up
        if up_blocked and (not left_blocked):
            return left
        if (not left_blocked) and (not up_blocked):
            return chosen
        return current

    # 左下角最优时的特殊判断
    if (dr, dc) == (1, -1):
        left = (r, c - 1)
        down = (r + 1, c)
        left_blocked = (not in_bounds(left, rows, cols)) or obstacle[left]
        down_blocked = (not in_bounds(down, rows, cols)) or obstacle[down]

        if left_blocked and (not down_blocked):
            return down
        if down_blocked and (not left_blocked):
            return left
        if (not left_blocked) and (not down_blocked):
            return chosen
        return current

    return chosen


def render_frame(obstacle: np.ndarray, door: Position, robot: Position, step: int, dt: float = 1.0):
    """渲染当前帧，并把标题写上时间和实时坐标。"""
    image = make_rgb_image(obstacle, door, robot)

    fig, ax = plt.subplots(figsize=(5, 7))
    ax.imshow(image, interpolation="nearest")

    # 给用户展示更直观的 1 基坐标，更接近 MATLAB 的写法
    matlab_row = robot[0] + 1
    matlab_col = robot[1] + 1
    current_time = step * dt

    ax.set_title(f"evacuation, step={step}, t={current_time:.1f}s, pos=({matlab_row},{matlab_col})")
    ax.set_xticks([])
    ax.set_yticks([])
    plt.tight_layout()

    # 把当前 figure 转为 numpy 图像帧，后面用于生成 GIF
    fig.canvas.draw()
    w, h = fig.canvas.get_width_height()
    buffer = np.frombuffer(fig.canvas.buffer_rgba(), dtype=np.uint8)
    # 根据实际缓冲区大小计算正确的高度（应对 DPI 缩放问题）
    actual_h = len(buffer) // (w * 4)
    frame = buffer.reshape((actual_h, w, 4))[..., :3].copy()
    return fig, ax, frame


def save_png(obstacle: np.ndarray, door: Position, robot: Position, step: int, save_path: str, dt: float = 1.0):
    """保存单张 PNG 截图。"""
    fig, ax, _ = render_frame(obstacle, door, robot, step, dt=dt)
    fig.savefig(save_path, dpi=200)
    plt.close(fig)


def save_path_figure(obstacle: np.ndarray, door: Position, path: List[Position], save_path: str):
   
    rows, cols = obstacle.shape
    plt.figure(figsize=(5, 7))
    base = np.ones((rows, cols))
    base[obstacle] = 0
    plt.imshow(base, cmap="gray", interpolation="nearest")
    plt.scatter([door[1]], [door[0]], c="lime", s=120, marker="s", label="door")

    path_rows = [p[0] for p in path]
    path_cols = [p[1] for p in path]
    plt.plot(path_cols, path_rows, linewidth=2, label="path")
    plt.scatter([path[0][1]], [path[0][0]], c="orange", s=100, marker="o", label="start")
    plt.scatter([path[-1][1]], [path[-1][0]], c="red", s=120, marker="o", label="end")
    plt.gca().invert_yaxis()
    plt.xticks([])
    plt.yticks([])
    plt.legend(loc="upper right")
    plt.title(f"task1 path, total steps={len(path)-1}")
    plt.tight_layout()
    plt.savefig(save_path, dpi=200)
    plt.close()


def simulate_task1(max_steps: int = 300, seed = None, dt: float = 1.0, fps: int = 2,
                   show_live: bool = True, pause_seconds: float = 0.35):
    """主函数：实时显示动画，同时保存 GIF、初末截图和路径图。"""
    weights, obstacle, door, start, big_m = build_classroom_from_ppt(seed=seed)
    current = start
    path: List[Position] = [current]

    # 输出目录放在当前工作目录下，更容易找到
    output_dir = os.path.join(os.getcwd(), "task1_output")
    os.makedirs(output_dir, exist_ok=True)

    # 先记录初始帧
    frames = []
    fig, ax, frame0 = render_frame(obstacle, door, current, step=0, dt=dt)
    frames.append(frame0)

    if show_live:
        plt.ion()
        live_fig, live_ax = plt.subplots(figsize=(5, 7))
        live_im = live_ax.imshow(make_rgb_image(obstacle, door, current), interpolation="nearest")
        matlab_row = current[0] + 1
        matlab_col = current[1] + 1
        live_ax.set_title(f"evacuation, step=0, t=0.0s, pos=({matlab_row},{matlab_col})")
        live_ax.set_xticks([])
        live_ax.set_yticks([])
        plt.tight_layout()
        plt.pause(pause_seconds)
    else:
        live_fig = live_ax = live_im = None

    save_png(obstacle, door, current, step=0, save_path=os.path.join(output_dir, "task1_initial.png"), dt=dt)
    plt.close(fig)

    step = 0
    while (current != door) and (step < max_steps):
        step += 1
        current = choose_next_step_ppt(current, weights, obstacle, door)
        path.append(current)

        # 记录 GIF 帧
        fig, ax, frame = render_frame(obstacle, door, current, step=step, dt=dt)
        frames.append(frame)
        plt.close(fig)

        # 实时显示动画窗口
        if show_live and (live_im is not None):
            live_im.set_data(make_rgb_image(obstacle, door, current))
            matlab_row = current[0] + 1
            matlab_col = current[1] + 1
            live_ax.set_title(f"evacuation, step={step}, t={step*dt:.1f}s, pos=({matlab_row},{matlab_col})")
            plt.pause(pause_seconds)

    if show_live:
        plt.ioff()
        plt.show(block=True)

    save_png(obstacle, door, current, step=step, save_path=os.path.join(output_dir, "task1_final.png"), dt=dt)
    save_path_figure(obstacle, door, path, os.path.join(output_dir, "task1_path.png"))

    # 真正导出 GIF
    gif_path = os.path.join(output_dir, "task1_demo.gif")
    duration = 1.0 / fps
    imageio.mimsave(gif_path, frames, duration=duration, loop=0)

    return {
        "start": start,
        "door": door,
        "steps": step,
        "reached": current == door,
        "path": path,
        "big_m": big_m,
        "output_dir": output_dir,
        "gif_path": gif_path,
    }


if __name__ == "__main__":
    result = simulate_task1(max_steps=300, seed=None, dt=1.0, fps=2, show_live=True, pause_seconds=0.35)
    print("=" * 60)
    print("任务1修正版：有门教室 + 桌椅障碍 + PPT 局部最小权重规则")
    print(f"起点（Python 0基坐标）: {result['start']}")
    print(f"门口（Python 0基坐标）: {result['door']}")
    print(f"总步数: {result['steps']}")
    print(f"是否到达门口: {result['reached']}")
    print(f"输出目录: {result['output_dir']}")
    print(f"GIF 文件: {result['gif_path']}")
    print("输出文件包括：task1_initial.png、task1_final.png、task1_path.png、task1_demo.gif")
    print("=" * 60)
