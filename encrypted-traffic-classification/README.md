# Encrypted Network-Traffic Classification / 加密网络流量分类识别

Characterizing and classifying **12 categories of labeled encrypted network
traffic** (plus 490 unlabeled test packets) using statistical behavioral
features, since payload content is unavailable under encryption.

在无法利用加密载荷明文的前提下，使用统计行为特征对 **12 类已标注加密网络流量**
（以及 490 个类别未知的测试数据包）进行特征刻画与分类识别。

## Approach / 方法

1. **Feature engineering** — 33 statistical features across four dimensions
   (packet length, timing, directional interaction, protocol behavior),
   extracted with a sliding window of length 50 / step 25.
   从包长、时序、方向交互、协议行为四个维度提取 33 个统计特征，采用长度 50、
   步长 25 的滑动窗口构造局部样本。
2. **Characterization** — standardized class centroids, Euclidean distance
   matrix, and PCA to reveal class structure and similarity.
   通过标准化类中心、欧氏距离矩阵与 PCA 刻画类别结构与差异。
3. **Classification** — a Random Forest 12-class model, mapping window-level
   posteriors to packet-level labels via *posterior aggregation + hex-signature
   correction*. 随机森林 12 分类，并通过“窗口后验—包级聚合—Hex 签名校正”将
   窗口级结果映射为数据包级标签。

## Results / 结果

- PCA first two components explain **52.43%** of variance.
- Random Forest: **accuracy 0.9107**, **Macro-F1 0.8895** — outperforming
  nearest-centroid and weighted-KNN baselines.
- Closest class pairs: `facebook_chat`–`hangouts_chat`,
  `bittorrent`–`ftps_file_transfer`, `hangouts_voip`–`skype_voip`;
  `aim_chat` / `icq_chat` show distinctly sparse temporal behavior.
- Window-parameter sensitivity analysis confirms robustness of the class structure.

## Files / 文件

```
code/
  Q1_feature_analysis.m        # feature extraction, PCA, distance/heatmaps
  Q2_hybrid_classification.m   # Random Forest classification + packet-level mapping
data/
  window_feature_dataset.csv   # windowed feature dataset (model input)
  class_feature_mean.csv, class_feature_summary.csv, class_distance_matrix.csv
  Q2_test_packet_predictions.csv  # predicted labels for the 490 test packets
figures/
  PCA_scatter.png, class_feature_heatmap.png, class_distance_heatmap.png
report.pdf / report.tex        # full report (Problems 1 & 2)
```

## Run / 运行

Open the `.m` files in MATLAB from the project root; data paths are relative to `data/`.
在 MATLAB 中于项目根目录运行 `.m` 文件，数据路径相对于 `data/`。
