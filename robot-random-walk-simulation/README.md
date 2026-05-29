# Robot Navigation & Random-Walk Simulation / 机器人导航与随机游走仿真

Two grid-based robot simulations on an 8-neighborhood lattice, with animated
GIF output.

两个基于 8 邻域网格的机器人仿真，均输出动画 GIF。

## Task 1 — Classroom navigation / 教室导航

A robot navigates a classroom (with a door and desk/chair obstacles) toward the
exit, following a **local minimum-weight movement rule**. Outputs the path,
final state, and an animation.

机器人在带门和桌椅障碍的教室中，依据**局部最小权重移动规则**走向出口，输出路径图、
末态图与动画。

- Code: `task1_classroom_navigation.py`
- Figures: `figures/task1_path.png`, `figures/task1_final.png`, `figures/task1_demo.gif`

## Task 2 — Random-walk escape / 随机游走逃逸

A cleaning robot moves randomly inside an `M × N` walled room with one door.
Using equal-probability moves per the interior/edge/corner rules, **Monte Carlo
simulation** estimates the escape probability, mean steps, and variance.

扫地机器人在带一个门的 `M × N` 封闭房间内随机移动，按内部/墙边/墙角的等概率规则游走，
通过**蒙特卡洛仿真**统计逃逸概率、平均步数与方差。

- Code: `task2_random_walk_exit.py`
- Figures: `figures/task2_demo_31x25.gif`, summary in `figures/task2_summary.csv`

## Run / 运行

```bash
pip install numpy matplotlib imageio pillow
python task1_classroom_navigation.py
python task2_random_walk_exit.py
```
