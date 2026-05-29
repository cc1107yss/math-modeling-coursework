# Forest-Fire Cellular Automaton / 森林火灾元胞自动机

Two cellular-automaton models of forest-fire spread.
两个森林火灾蔓延的元胞自动机模型。

## Models / 模型

- **`forestfire1.m`** — a wildfire spread simulation over realistic terrain
  (Los Angeles–style), incorporating **wind direction, wind speed, slope,
  vegetation flammability, and buildings**. Cell states: empty / vegetation /
  burning / building / burned.
  在起伏地形上的火灾蔓延模拟，考虑**风向、风速、坡度、植被易燃度与建筑物**；
  元胞状态：空地 / 植被 / 燃烧 / 建筑物 / 烧毁。

- **`forestfire2.m`** — the classic **Drossel–Schwabl forest-fire model**:
  burning trees become empty; green trees ignite with probability `q` if a
  neighbor burns; empty cells grow trees with probability `p`; trees self-ignite
  (lightning) with probability `f`.
  经典 **Drossel–Schwabl 森林火灾模型**：燃烧树→空地；绿树邻居着火时以概率 `q`
  被点燃；空地以概率 `p` 长树；树以概率 `f`（闪电）自燃。

## Files / 文件

```
forestfire1.m    # terrain + wind + buildings wildfire model
forestfire2.m    # classic probabilistic forest-fire model
forestfire.fig   # MATLAB figure
result.png       # sample output
```

## Run / 运行

Open the `.m` files in MATLAB and run. / 在 MATLAB 中打开并运行 `.m` 文件。
