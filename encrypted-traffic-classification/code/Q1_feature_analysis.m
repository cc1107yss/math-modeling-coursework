clear; clc; close all;

%% ================== 1. 路径与参数设置 ==================
baseDir = 'F:\数学建模作业\2025年北京高校数学建模校际联赛赛题 (2)\2025年北京高校数学建模校际联赛赛题\2025年北京高校数学建模校际联赛赛题\B\B题数据';

trainDir = fullfile(baseDir, 'data', 'xlsx');
outDir   = fullfile(baseDir, 'Q1_outputs');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

% 滑动窗口参数（可根据效果调整）
windowSize = 50;      % 每个窗口包含 50 个包
stepSize   = 25;      % 步长 25
silenceThr = 0.5;     % “长停顿”阈值（秒）

% 题目给出的标签号映射（后续第2问也能直接复用）
labelKeys = {'aim_chat', 'bittorrent', 'email', 'facebook_voip', ...
             'facebook_chat', 'ftps_file_transfer', 'hangouts_voip', ...
             'hangouts_chat', 'icq_chat', 'sftp_file_transfer', ...
             'skype_voip', 'skype_file_transfer'};
labelVals = num2cell(1:12);
labelMap  = containers.Map(labelKeys, labelVals);

fprintf('训练数据目录：%s\n', trainDir);

%% ================== 2. 获取训练文件 ==================
files = dir(fullfile(trainDir, '*.xlsx'));
keep = true(numel(files), 1);
for i = 1:numel(files)
    nm = files(i).name;
    if startsWith(nm, '~$') || startsWith(nm, '.') || strcmpi(nm, 'test.xlsx')
        keep(i) = false;
    end
end
files = files(keep);

if isempty(files)
    error('在 %s 中没有找到训练用的 xlsx 文件。请检查路径是否正确。', trainDir);
end

fprintf('共找到 %d 个训练文件。\n', numel(files));

%% ================== 3. 逐文件读取并提取窗口特征 ==================
allX = [];
allLabel = {};
allLabelNum = [];
allWindowID = [];
allFileName = {};
featureNames = {};

for i = 1:numel(files)
    filePath = fullfile(files(i).folder, files(i).name);
    fprintf('正在处理 [%d/%d]：%s\n', i, numel(files), files(i).name);

    % 只读取需要的列，故意不读 Hex，能快很多
    opts = detectImportOptions(filePath, 'FileType', 'spreadsheet');
    try
        opts.VariableNamingRule = 'preserve';
    catch
    end

    wantedVars = {'Time', 'Source', 'Destination', 'Protocol', 'Length', 'Info', 'app_aux'};
    existedVars = intersect(wantedVars, opts.VariableNames, 'stable');
    opts.SelectedVariableNames = existedVars;

    T = readtable(filePath, opts);

    if isempty(T) || height(T) == 0
        warning('文件 %s 为空，已跳过。', files(i).name);
        continue;
    end

    className = getClassLabel(T, files(i).name);
    if isKey(labelMap, className)
        classNum = labelMap(className);
    else
        classNum = NaN;
    end

    idxPairs = makeWindowIndex(height(T), windowSize, stepSize);
    if isempty(idxPairs)
        idxPairs = [1, height(T)];
    end

    for w = 1:size(idxPairs, 1)
        Tw = T(idxPairs(w, 1):idxPairs(w, 2), :);
        [x, fNames] = extractWindowFeatures(Tw, silenceThr);

        if isempty(featureNames)
            featureNames = fNames;
        end

        allX = [allX; x]; %#ok<AGROW>
        allLabel = [allLabel; {className}]; %#ok<AGROW>
        allLabelNum = [allLabelNum; classNum]; %#ok<AGROW>
        allWindowID = [allWindowID; w]; %#ok<AGROW>
        allFileName = [allFileName; {files(i).name}]; %#ok<AGROW>
    end
end

if isempty(allX)
    error('没有成功提取到任何特征，请检查数据文件内容。');
end

fprintf('窗口特征提取完成，总窗口数：%d\n', size(allX, 1));

%% ================== 4. 标准化 ==================
mu = mean(allX, 1);
sigma = std(allX, 0, 1);
sigma(sigma < 1e-12) = 1;
Xz = (allX - mu) ./ sigma;

%% ================== 5. PCA（用 SVD 实现，不依赖额外工具箱） ==================
X0 = Xz - mean(Xz, 1);
[~, S, V] = svd(X0, 'econ');
score = X0 * V;
latent = (diag(S).^2) / max(size(X0, 1) - 1, 1);
explained = 100 * latent / sum(latent);

%% ================== 6. 按类别求均值中心 ==================
[uLabels, ~, grp] = unique(allLabel, 'stable');
nClass = numel(uLabels);
nFeat = size(allX, 2);

centersRaw = zeros(nClass, nFeat);
centersZ = zeros(nClass, nFeat);
windowCounts = zeros(nClass, 1);
classNums = nan(nClass, 1);

for k = 1:nClass
    idx = (grp == k);
    centersRaw(k, :) = mean(allX(idx, :), 1);
    centersZ(k, :) = mean(Xz(idx, :), 1);
    windowCounts(k) = sum(idx);
    if isKey(labelMap, uLabels{k})
        classNums(k) = labelMap(uLabels{k});
    end
end

overallMeanZ = mean(centersZ, 1);
distMat = euclidDistMat(centersZ);

%% ================== 7. 保存结果表格 ==================
windowTable = array2table(allX, 'VariableNames', featureNames);
windowTable.class_name = string(allLabel);
windowTable.label_num = allLabelNum;
windowTable.window_id = allWindowID;
windowTable.file_name = string(allFileName);
windowTable = movevars(windowTable, {'class_name', 'label_num', 'file_name', 'window_id'}, 'Before', 1);
writetable(windowTable, fullfile(outDir, 'window_feature_dataset.csv'));

classTable = array2table(centersRaw, 'VariableNames', featureNames);
classTable.class_name = string(uLabels(:));
classTable.label_num = classNums;
classTable.window_count = windowCounts;
classTable = movevars(classTable, {'class_name', 'label_num', 'window_count'}, 'Before', 1);
writetable(classTable, fullfile(outDir, 'class_feature_mean.csv'));
sel = {'duration','len_mean','large_ratio','dt_mean','dt_p90', ...
       'silence_ratio','burstiness','switch_rate', ...
       'tcp_ratio','udp_ratio','tls_ratio','ssh_ratio','stun_ratio','appdata_ratio'};

summaryTable = classTable(:, [{'class_name','label_num','window_count'}, sel]);
writetable(summaryTable, fullfile(outDir, 'class_feature_summary.csv'));

writematrix(distMat, fullfile(outDir, 'class_distance_matrix.csv'));
fid2 = fopen(fullfile(outDir, 'nearest_class_pairs.txt'), 'w');
for k = 1:nClass
    d = distMat(k, :);
    d(k) = inf;
    [ds, ord] = sort(d, 'ascend');
    fprintf(fid2, '类别 %d (%s) 最近的两类：\n', classNums(k), uLabels{k});
    fprintf(fid2, '  1) %d (%s), 距离 = %.4f\n', classNums(ord(1)), uLabels{ord(1)}, ds(1));
    fprintf(fid2, '  2) %d (%s), 距离 = %.4f\n\n', classNums(ord(2)), uLabels{ord(2)}, ds(2));
end
fclose(fid2);
sparseLabels = [1, 9, 12];
idxSparse = ismember(classNums, sparseLabels);
sparseTable = classTable(idxSparse, {'class_name','label_num','duration','dt_mean','dt_p90','silence_ratio','burstiness'});
writetable(sparseTable, fullfile(outDir, 'sparse_flow_summary.csv'));
% 每类最显著的前5个特征
fid = fopen(fullfile(outDir, 'top5_features_each_class.txt'), 'w');
for k = 1:nClass
    [~, ord] = sort(abs(centersZ(k, :) - overallMeanZ), 'descend');
    top5 = ord(1:min(5, numel(ord)));
    fprintf(fid, '类别 %d (%s) 的最显著特征：\n', classNums(k), uLabels{k});
    for j = 1:numel(top5)
        fprintf(fid, '  %d) %s\n', j, featureNames{top5(j)});
    end
    fprintf(fid, '\n');
end
fclose(fid);

%% ================== 8. 画图：PCA散点图 ==================
colors = lines(nClass);
fig1 = figure('Color', 'w', 'Position', [100, 100, 1100, 650]);
hold on;
for k = 1:nClass
    idx = (grp == k);
    scatter(score(idx, 1), score(idx, 2), 24, 'MarkerFaceColor', colors(k, :), ...
        'MarkerEdgeColor', colors(k, :), ...
        'DisplayName', sprintf('%d-%s', classNums(k), uLabels{k}));
end
grid on;
xlabel(sprintf('PC1 (%.2f%%)', explained(1)), 'FontSize', 12);
ylabel(sprintf('PC2 (%.2f%%)', explained(2)), 'FontSize', 12);
title('Q1：12类加密流量的 PCA 可视化', 'FontSize', 14);
lgd = legend('Location', 'eastoutside');
set(lgd, 'Interpreter', 'none');
saveas(fig1, fullfile(outDir, 'PCA_scatter.png'));

%% ================== 9. 画图：类别特征热力图 ==================
fig2 = figure('Color', 'w', 'Position', [120, 120, 1500, 650]);
imagesc(centersZ);
colormap(parula);
colorbar;
set(gca, 'XTick', 1:nFeat, 'XTickLabel', featureNames, 'XTickLabelRotation', 45, ...
    'YTick', 1:nClass, 'YTickLabel', strcat(string(classNums), '-', string(uLabels)));
ax = gca;
ax.TickLabelInterpreter = 'none';
title('Q1：各类流量的标准化特征中心热力图', 'FontSize', 14);
axis tight;
saveas(fig2, fullfile(outDir, 'class_feature_heatmap.png'));

%% ================== 10. 画图：类别间距离矩阵 ==================
fig3 = figure('Color', 'w', 'Position', [140, 140, 900, 760]);
imagesc(distMat);
colormap(parula);
colorbar;
set(gca, 'XTick', 1:nClass, 'XTickLabel', strcat(string(classNums), '-', string(uLabels)), ...
    'YTick', 1:nClass, 'YTickLabel', strcat(string(classNums), '-', string(uLabels)), ...
    'XTickLabelRotation', 45);
ax = gca;
ax.TickLabelInterpreter = 'none';
title('Q1：类别间欧氏距离矩阵（基于标准化特征中心）', 'FontSize', 14);
axis square;
saveas(fig3, fullfile(outDir, 'class_distance_heatmap.png'));

%% ================== 11. 输出摘要 ==================
fprintf('\n================ 运行完成 ================\n');
fprintf('结果已保存到：%s\n', outDir);
fprintf('1) window_feature_dataset.csv   —— 所有窗口样本的特征\n');
fprintf('2) class_feature_mean.csv       —— 12类流量的平均特征\n');
fprintf('3) class_distance_matrix.csv    —— 类别间距离矩阵\n');
fprintf('4) PCA_scatter.png              —— PCA散点图\n');
fprintf('5) class_feature_heatmap.png    —— 特征热力图\n');
fprintf('6) class_distance_heatmap.png   —— 类别距离热力图\n');
fprintf('7) top5_features_each_class.txt —— 每类最显著的5个特征\n');


%% ================== 以下是本脚本用到的局部函数 ==================
function idxPairs = makeWindowIndex(n, win, step)
    if n <= 0
        idxPairs = [];
        return;
    end
    if n <= win
        idxPairs = [1, n];
        return;
    end
    starts = 1:step:(n - win + 1);
    idxPairs = [starts(:), starts(:) + win - 1];
    if idxPairs(end, 2) < n
        idxPairs = [idxPairs; n - win + 1, n]; %#ok<AGROW>
    end
    idxPairs = unique(idxPairs, 'rows', 'stable');
end

function className = getClassLabel(T, fileName)
    vars = T.Properties.VariableNames;
    if any(strcmp(vars, 'app_aux'))
        tmp = string(T.app_aux(1));
        className = char(tmp);
        return;
    end

    % 如果未来读取 test.xlsx 没有 app_aux，则退回到文件名解析
    [~, nm, ~] = fileparts(fileName);
    nm = erase(nm, 'vpn_');
    % 这里只给训练数据兜底，不追求泛化到所有命名方式
    patterns = {'aim_chat', 'bittorrent', 'email', 'facebook_audio', ...
                'facebook_chat', 'ftps', 'hangouts_audio', 'hangouts_chat', ...
                'icq_chat', 'sftp', 'skype_audio', 'skype_files'};
    mapped = {'aim_chat', 'bittorrent', 'email', 'facebook_voip', ...
              'facebook_chat', 'ftps_file_transfer', 'hangouts_voip', 'hangouts_chat', ...
              'icq_chat', 'sftp_file_transfer', 'skype_voip', 'skype_file_transfer'};

    className = nm;
    for i = 1:numel(patterns)
        if contains(nm, patterns{i})
            className = mapped{i};
            return;
        end
    end
end

function [x, featureNames] = extractWindowFeatures(Tw, silenceThr)
    t = double(Tw.Time);
    L = double(Tw.Length);
    src = string(Tw.Source);
    dst = string(Tw.Destination);
    protocol = string(Tw.Protocol);
    info = string(Tw.Info);
    src(ismissing(src)) = "";
    dst(ismissing(dst)) = "";
    protocol(ismissing(protocol)) = "";
    info(ismissing(info)) = "";
    protocol = upper(protocol);
    info = upper(info);

    if isempty(t)
        x = zeros(1, 33);
        featureNames = defaultFeatureNames();
        return;
    end

    dt = diff(t);
    if isempty(dt)
        dt = 0;
    end

    localIP = getLocalIP(src, dst);
    direction = ones(numel(src), 1);
    direction(src ~= localIP) = -1;
    signedLen = direction .* L;

    if numel(direction) > 1
        switchRate = mean(direction(2:end) ~= direction(1:end-1));
    else
        switchRate = 0;
    end

    upMask = (direction == 1);
    downMask = (direction == -1);

    featureNames = defaultFeatureNames();
    x = [ ...
        numel(L), ...                              % 1 n_pkt
        safeDuration(t), ...                       % 2 duration
        mean(L), std(L), min(L), max(L), ...      % 3-6
        prctile(L, 25), prctile(L, 50), prctile(L, 75), ... % 7-9
        mean(L < 100), mean(L > 1000), ...        % 10-11
        mean(dt), std(dt), prctile(dt, 50), prctile(dt, 90), ... % 12-15
        mean(dt > silenceThr), ...                % 16
        burstiness(dt), ...                       % 17
        mean(upMask), mean(downMask), ...         % 18-19
        sum(L(upMask)) / max(sum(L), eps), ...    % 20
        sum(L(downMask)) / max(sum(L), eps), ...  % 21
        switchRate, ...                           % 22
        mean(signedLen), std(signedLen), ...      % 23-24
        mean(contains(protocol, 'TCP')), ...      % 25
        mean(contains(protocol, 'UDP')), ...      % 26
        mean(contains(protocol, 'TLS') | contains(protocol, 'SSL')), ... % 27
        mean(contains(protocol, 'SSH')), ...      % 28
        mean(contains(protocol, 'STUN')), ...     % 29
        mean(contains(info, 'ACK')), ...          % 30
        mean(contains(info, 'SYN')), ...          % 31
        mean(contains(info, 'FIN')), ...          % 32
        mean(contains(info, 'APPLICATION DATA')) ... % 33
        ];
end

function names = defaultFeatureNames()
    names = { ...
        'n_pkt', 'duration', ...
        'len_mean', 'len_std', 'len_min', 'len_max', 'len_p25', 'len_p50', 'len_p75', ...
        'small_ratio', 'large_ratio', ...
        'dt_mean', 'dt_std', 'dt_p50', 'dt_p90', 'silence_ratio', 'burstiness', ...
        'up_ratio', 'down_ratio', 'up_bytes_ratio', 'down_bytes_ratio', 'switch_rate', ...
        'signed_len_mean', 'signed_len_std', ...
        'tcp_ratio', 'udp_ratio', 'tls_ratio', 'ssh_ratio', 'stun_ratio', ...
        'ack_ratio', 'syn_ratio', 'fin_ratio', 'appdata_ratio' ...
        };
end

function y = safeDuration(t)
    if numel(t) <= 1
        y = 0;
    else
        y = t(end) - t(1);
    end
end

function b = burstiness(dt)
    m = mean(dt);
    s = std(dt);
    b = (s - m) / (s + m + eps);
end

function localIP = getLocalIP(src, dst)
    allIPs = [src(:); dst(:)];
    privateFlags = false(numel(allIPs), 1);
    for i = 1:numel(allIPs)
        privateFlags(i) = isPrivateIPv4(char(allIPs(i)));
    end
    if any(privateFlags)
        localIP = modeString(allIPs(privateFlags));
    else
        localIP = modeString(allIPs);
    end
end

function tf = isPrivateIPv4(ip)
    ip = strtrim(ip);
    tf = false;
    if startsWith(ip, '10.')
        tf = true;
        return;
    end
    if startsWith(ip, '192.168.')
        tf = true;
        return;
    end
    if startsWith(ip, '172.')
        parts = split(ip, '.');
        if numel(parts) >= 2
            secondNum = str2double(parts{2});
            if ~isnan(secondNum) && secondNum >= 16 && secondNum <= 31
                tf = true;
                return;
            end
        end
    end
end

function s = modeString(arr)
    arr = string(arr(:));
    if isempty(arr)
        s = "";
        return;
    end
    [u, ~, ic] = unique(arr, 'stable');
    counts = accumarray(ic, 1);
    [~, idx] = max(counts);
    s = u(idx);
end

function D = euclidDistMat(X)
    n = size(X, 1);
    D = zeros(n, n);
    for i = 1:n
        for j = i:n
            d = sqrt(sum((X(i, :) - X(j, :)).^2));
            D(i, j) = d;
            D(j, i) = d;
        end
    end
end
