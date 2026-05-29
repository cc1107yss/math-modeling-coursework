# Mathematical Modeling Coursework / 数学建模作业集

A collection of mathematical-modeling projects completed during my coursework.
Each project contains the source code, a written report (PDF + LaTeX), and
representative figures/data so the results are reproducible.

本仓库收录了我在数学建模课程中完成的建模项目。每个项目包含源代码、书面报告
（PDF + LaTeX 源文件）以及可复现结果所需的代表性图表与数据。

> Reports are written in Chinese; code comments are mixed Chinese/English.
> 报告为中文撰写，代码注释为中英文混合。

## Projects / 项目一览

| Project | Topic | Methods | Language |
|---|---|---|---|
| [`encrypted-traffic-classification`](./encrypted-traffic-classification) | Encrypted network-traffic classification by statistical behavioral features<br>基于统计行为特征的加密流量分类识别 | Feature engineering · PCA · Random Forest | MATLAB |
| [`crop-planting-optimization`](./crop-planting-optimization) | Optimal crop-planting plan for 2024–2030 (CUMCM 2024 Problem C)<br>农作物种植方案优化（2024 高教社杯 C 题） | MINLP · Gurobi · Simulated Annealing · Genetic Algorithm | Python |
| [`bread-mold-cellular-automaton`](./bread-mold-cellular-automaton) | Spatiotemporal evolution of multi-species bread mold<br>多菌种面包霉菌的时空演化建模 | Cellular automaton · Competition–facilitation dynamics · Sensitivity analysis | MATLAB |
| [`robot-random-walk-simulation`](./robot-random-walk-simulation) | Robot navigation & random-walk escape simulation<br>机器人导航与随机游走逃逸仿真 | Monte Carlo · Rule-based navigation | Python |
| [`forest-fire-ca`](./forest-fire-ca) | Forest-fire spread cellular automaton<br>森林火灾蔓延元胞自动机 | Cellular automaton | MATLAB |

## Tech stack / 技术栈

- **Python** — NumPy, pandas, Gurobi, matplotlib, imageio
- **MATLAB** — numerical simulation, statistical feature analysis, visualization
- **LaTeX** — report typesetting

## Repository layout / 目录结构

Each project follows the same convention:

```
<project>/
├── README.md          # project overview (bilingual)
├── code/  or  *.py    # source code
├── data/              # input data and key result tables
├── figures/           # representative output figures
└── report.pdf / .tex  # written report
```
