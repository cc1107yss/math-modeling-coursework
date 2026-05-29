# Bread-Mold Cellular Automaton / 面包霉菌元胞自动机

Modeling the **spatiotemporal evolution of multi-species mold** on a bread
surface, where colored colonies (white/green/black/yellow/orange) expand,
compete, and replace one another over time.

对面包表面**多菌种霉菌的时空演化**进行建模：不同颜色（白/绿/黑/黄/橙）的菌斑随时间
扩张、竞争、相互挤压与局部替换。

## Model / 模型

A **competition–facilitation cellular automaton** on a 2-D discretized bread
surface, coupling environmental suitability, local resources, and boundary-
replacement rules. It answers:

二维离散面包表面上的**竞争–促进型元胞自动机**，耦合环境适宜度、局部资源与边界替换
规则，用于回答：

- how each species' colony expands over time / 各菌种扩张过程随时间的演变；
- how area fractions evolve and which species dominates / 面积占比变化与最终优势菌种；
- when the system reaches a stable state / 系统何时达到稳定；
- how to extract colony contours and inter-species boundaries from the final
  colored map / 如何从最终彩色分布图提取菌落轮廓与交界边界。

A **sensitivity analysis** over model coefficients confirms robustness.
对模型系数的**灵敏度分析**验证了结果的稳健性。

## Files / 文件

```
code/
  bread_ca_report.m         # main cellular-automaton simulation + figures
  bread_sensitivity_only.m  # sensitivity analysis over coefficients
data/
  bread_sensitivity_summary.csv, bread_sensitivity_coefficients.csv
figures/
  bread_single.gif          # animated colony evolution
  bread_single_curves.png, bread_single_final.png, bread_sensitivity_plot.png
report.pdf / report.tex
```

## Run / 运行

Open the `.m` files in MATLAB from the project root.
在 MATLAB 中于项目根目录运行 `.m` 文件。
