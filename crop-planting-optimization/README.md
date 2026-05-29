# Crop-Planting Optimization / 农作物种植方案优化

Designing an optimal crop-planting plan for a village's farmland and greenhouses
over **2024–2030** to maximize total revenue, accounting for unsold-surplus
waste. Based on **CUMCM 2024 Problem C, sub-problem 1(1)**.

为乡村现有耕地与大棚制定 **2024–2030 年**的最优种植方案，在考虑超产滞销浪费的
条件下最大化总收益。题目来自 **2024 高教社杯全国大学生数学建模竞赛 C 题第一问（情形 1）**。

## Model / 模型

A **mixed-integer (non)linear program**: maximize 2024–2030 total revenue
subject to land-type suitability, minimum planting area, crop-rotation,
legume-planting requirements, and field-management constraints. The surplus
term `S = min(Q, D)` (production capped by expected demand) is linearized via
Gurobi's `addGenConstrMin`.

混合整数（非）线性规划：在地块适宜性、最小种植面积、轮作、豆类种植与田间管理等
约束下最大化总收益；用 Gurobi 的 `addGenConstrMin` 对滞销项 `S = min(Q, D)` 进行线性化。

## Two solution strategies / 两种求解策略

- **`code/gurobi_exact.py`** — exact solve via Gurobi (linearized model).
  使用 Gurobi 精确求解（线性化模型）。
- **`code/heuristics_sa_ga.py`** — Simulated Annealing + Genetic Algorithm
  metaheuristics for comparison. 模拟退火 + 遗传算法的启发式对比求解。

## Files / 文件

```
code/
  gurobi_exact.py        # Gurobi exact solver
  heuristics_sa_ga.py    # SA + GA metaheuristics
data/
  result_gurobi.xlsx, result_sa.xlsx, result_ga.xlsx  # planting plans per method
  algorithm_summary.xlsx                               # objective-value comparison
problem-statement.pdf    # original competition problem (Problem C)
report.pdf / report.tex  # modeling report
```

## Run / 运行

```bash
pip install pandas openpyxl numpy gurobipy   # Gurobi requires a valid license
python code/gurobi_exact.py
python code/heuristics_sa_ga.py
```
