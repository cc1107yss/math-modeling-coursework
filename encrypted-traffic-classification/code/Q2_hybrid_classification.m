
clear; clc; close all;

%% ================== Q2：路径与参数设置 ==================
% 说明：
% 1) 本脚本默认与题目数据文件放在同一目录下运行；
% 2) 若你的数据位于其它目录，只需修改 baseDir；
% 3) 本脚本在问题一 33 维统计行为特征与滑动窗口框架上继续搭建，
%    并新增“窗口后验概率 -> 数据包标签”的映射层，以及“Hex精确签名校正”模块。

baseDir = '/mnt/data';   % ====== 按需修改 ======
outDir  = fullfile(baseDir, 'Q2_outputs');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

% 与问题一保持一致的滑动窗口参数
windowSize = 50;      % 每个窗口 50 个包
stepSize   = 25;      % 步长 25
silenceThr = 0.5;     % 长停顿阈值（秒）

% 候选模型比较参数（用于论文中的路线比较）
doModelCompare = true;   % 若只想快速得到最终结果，可改为 false
cvWindowSize   = 50;     % 验证时仍用 50 包窗口
cvStepSize     = 50;     % 为避免重叠泄漏，验证采用非重叠窗口
nFolds         = 5;      % 分块交叉验证折数
knnK           = 5;      % KNN 邻居数

% 主模型参数
nTrees = 300;            % 随机森林树数
rngSeed = 2025;
rng(rngSeed);

% 标签映射（完全沿用问题一）
labelKeys = {'aim_chat', 'bittorrent', 'email', 'facebook_voip', ...
    'facebook_chat', 'ftps_file_transfer', 'hangouts_voip', ...
    'hangouts_chat', 'icq_chat', 'sftp_file_transfer', ...
    'skype_voip', 'skype_file_transfer'};
labelVals = num2cell(1:12);
labelMap = containers.Map(labelKeys, labelVals);

fprintf('================ Q2 开始运行 ================\n');
fprintf('baseDir = %s\n', baseDir);

%% ================== 1. 解析训练目录与测试文件 ==================
trainDir = resolveTrainDir(baseDir);
testFile = resolveTestFile(baseDir);

fprintf('训练数据目录：%s\n', trainDir);
fprintf('测试文件：%s\n', testFile);

%% ================== 2. 提取问题一同口径训练窗口特征 ==================
[trainX, trainYNum, trainYName, featureNames, trainFileName, trainWindowID] = ...
    extractTrainingWindows(trainDir, labelMap, windowSize, stepSize, silenceThr);

if isempty(trainX)
    error('训练集窗口特征为空，请检查文件路径和数据内容。');
end

fprintf('问题一口径训练窗口提取完成，总窗口数 = %d，特征维数 = %d\n', ...
    size(trainX, 1), size(trainX, 2));

% 标准化（沿用问题一）
mu = mean(trainX, 1);
sigma = std(trainX, 0, 1);
sigma(sigma < 1e-12) = 1;
trainXz = (trainX - mu) ./ sigma;

%% ================== 3. 候选路线比较（非重叠窗口 + 分块交叉验证） ==================
compareTable = table();
if doModelCompare
    fprintf('\n================ 候选模型比较 ================\n');
    [cvX, cvYNum, ~, ~, ~, ~] = extractTrainingWindows(trainDir, labelMap, cvWindowSize, cvStepSize, silenceThr);
    foldID = makeBlockedFoldID(cvYNum, nFolds);

    resNC  = evaluateNearestCentroidCV(cvX, cvYNum, foldID);
    resKNN = evaluateWeightedKNNCV(cvX, cvYNum, foldID, knnK);
    resRF  = evaluateRandomForestCV(cvX, cvYNum, foldID, nTrees, rngSeed);

    compareTable = table( ...
        ["NearestCentroid"; "WeightedKNN"; "RandomForest"], ...
        [resNC.acc; resKNN.acc; resRF.acc], ...
        [resNC.macroF1; resKNN.macroF1; resRF.macroF1], ...
        'VariableNames', {'model_name', 'accuracy', 'macro_f1'});
    writetable(compareTable, fullfile(outDir, 'model_compare_cv.csv'));

    disp(compareTable);
else
    fprintf('\n已跳过候选模型比较。\n');
end

%% ================== 4. 训练主模型：随机森林（问题一特征空间） ==================
fprintf('\n================ 训练主模型 ================\n');
useRF = false;
rfModel = [];
rfClassOrder = [];
featureImportance = nan(1, numel(featureNames));
oobFinal = NaN;

try
    response = cellstr(string(trainYNum));
    rfModel = TreeBagger(nTrees, trainXz, response, ...
        'Method', 'classification', ...
        'OOBPrediction', 'On', ...
        'OOBPredictorImportance', 'On', ...
        'Prior', 'uniform', ...
        'NumPredictorsToSample', max(1, round(sqrt(size(trainXz, 2)))));
    useRF = true;
    rfClassOrder = str2double(string(rfModel.ClassNames));
    oobCurve = oobError(rfModel, 'Mode', 'ensemble');
    oobFinal = oobCurve(end);
    featureImportance = rfModel.OOBPermutedPredictorDeltaError;
    fprintf('随机森林训练完成，OOB误差 = %.4f\n', oobFinal);
catch ME
    warning('未能成功调用 TreeBagger，改用类中心最近邻作为后备模型。\n%s', ME.message);
    useRF = false;
end

if useRF
    impTable = table((1:numel(featureNames))', string(featureNames(:)), featureImportance(:), ...
        'VariableNames', {'feat_id', 'feature_name', 'importance'});
    impTable = sortrows(impTable, 'importance', 'descend');
    writetable(impTable, fullfile(outDir, 'rf_feature_importance.csv'));
else
    impTable = table();
end

%% ================== 5. 构建训练集 Hex 精确签名库 ==================
fprintf('\n================ 构建 Hex 精确签名库 ================\n');
[hexMap, hexConflictCount] = buildHexLabelMap(trainDir, labelMap);
fprintf('Hex签名库构建完成；冲突签名数 = %d\n', hexConflictCount);

%% ================== 6. 对 test.xlsx 进行分类 ==================
fprintf('\n================ 测试集分类 ================\n');
Ttest = readPacketTable(testFile, true);
nTest = height(Ttest);
if nTest ~= 490
    warning('当前 test.xlsx 行数为 %d，与赛题中 490 个测试数据包不一致，请核查。', nTest);
end

% 6.1 先做“窗口 -> 概率 -> 包级投票”
testIdxPairs = makeWindowIndex(nTest, windowSize, stepSize);
if isempty(testIdxPairs)
    testIdxPairs = [1, nTest];
end

nWinTest = size(testIdxPairs, 1);
testX = zeros(nWinTest, numel(featureNames));
for w = 1:nWinTest
    Tw = Ttest(testIdxPairs(w, 1):testIdxPairs(w, 2), :);
    testX(w, :) = extractWindowFeatures(Tw, silenceThr);
end

testXz = (testX - mu) ./ sigma;
windowScore = predictWindowScore(testXz, trainXz, trainYNum, useRF, rfModel, rfClassOrder, numel(labelKeys));

packetScore = zeros(nTest, numel(labelKeys));
packetCover = zeros(nTest, 1);
for w = 1:nWinTest
    idx = testIdxPairs(w, 1):testIdxPairs(w, 2);
    packetScore(idx, :) = packetScore(idx, :) + repmat(windowScore(w, :), numel(idx), 1);
    packetCover(idx) = packetCover(idx) + 1;
end
packetScore = packetScore ./ max(packetCover, 1);
[~, modelPacketLabel] = max(packetScore, [], 2);

% 6.2 再用 Hex 精确签名进行最小修正
exactHit = false(nTest, 1);
exactLabel = nan(nTest, 1);
if any(strcmp(Ttest.Properties.VariableNames, 'Hex'))
    for i = 1:nTest
        key = normalizeHexString(Ttest.Hex(i));
        if strlength(key) > 0 && isKey(hexMap, char(key))
            exactHit(i) = true;
            exactLabel(i) = hexMap(char(key));
        end
    end
end

finalPacketLabel = modelPacketLabel;
finalPacketLabel(exactHit) = exactLabel(exactHit);

predictionMode = repmat("model_vote", nTest, 1);
predictionMode(exactHit) = "exact_hex";

predClassName = strings(nTest, 1);
for i = 1:nTest
    predClassName(i) = string(labelKeys{finalPacketLabel(i)});
end

resultTable = table((1:nTest)', finalPacketLabel, predClassName, predictionMode, ...
    'VariableNames', {'packet_id', 'pred_label', 'pred_class_name', 'pred_mode'});
writetable(resultTable, fullfile(outDir, 'test_packet_predictions.csv'));

segmentTable = makeSegmentSummary(finalPacketLabel, labelKeys);
writetable(segmentTable, fullfile(outDir, 'test_segment_summary.csv'));

%% ================== 7. 生成附录表1与表2 ==================
appendixPacketID = [1; 30; 60; 90; 120; 150; 180; 210; 240; 270; 300; 330; 360; 390; 420; 450; 480; 490];
appendixLabel = finalPacketLabel(appendixPacketID);
appendixClass = strings(numel(appendixPacketID), 1);
for i = 1:numel(appendixPacketID)
    appendixClass(i) = string(labelKeys{appendixLabel(i)});
end
appendixTable1 = table(appendixPacketID, appendixLabel, appendixClass, ...
    'VariableNames', {'packet_id', 'pred_label', 'pred_class_name'});
writetable(appendixTable1, fullfile(outDir, 'appendix_table1.csv'));

icqPacketID = find(finalPacketLabel == 9);
appendixTable2 = table(repmat("9(icq_chat)", numel(icqPacketID), 1), icqPacketID, ...
    'VariableNames', {'flow_type', 'packet_id'});
writetable(appendixTable2, fullfile(outDir, 'appendix_table2_icq_chat.csv'));

%% ================== 8. 保存模型摘要 ==================
fid = fopen(fullfile(outDir, 'Q2_summary.txt'), 'w');
fprintf(fid, 'Q2 主模型：随机森林 + 包级概率投票 + Hex精确签名校正\n');
fprintf(fid, '训练窗口参数：(m, s) = (%d, %d)\n', windowSize, stepSize);
fprintf(fid, '测试包数：%d\n', nTest);
fprintf(fid, 'Hex精确命中数：%d\n', sum(exactHit));
fprintf(fid, 'Hex精确命中率：%.4f\n', mean(exactHit));
if useRF
    fprintf(fid, '随机森林 OOB误差：%.6f\n', oobFinal);
else
    fprintf(fid, '未使用随机森林，当前为类中心最近邻后备模式。\n');
end
if ~isempty(compareTable)
    fprintf(fid, '\n候选模型比较（blocked CV）：\n');
    for i = 1:height(compareTable)
        fprintf(fid, '%s: accuracy = %.6f, macro_f1 = %.6f\n', ...
            char(compareTable.model_name(i)), compareTable.accuracy(i), compareTable.macro_f1(i));
    end
end
fclose(fid);

%% ================== 9. 控制台输出 ==================
fprintf('\n================ Q2 运行完成 ================\n');
fprintf('结果目录：%s\n', outDir);
fprintf('1) test_packet_predictions.csv —— 490个测试数据包的最终标签\n');
fprintf('2) appendix_table1.csv —— 论文附录表1可直接填写结果\n');
fprintf('3) appendix_table2_icq_chat.csv —— 论文附录表2（标签9）结果\n');
fprintf('4) test_segment_summary.csv —— 测试序列分段摘要\n');
fprintf('5) model_compare_cv.csv —— 候选模型比较结果（若已开启）\n');
fprintf('6) rf_feature_importance.csv —— 随机森林特征重要度（若已成功训练）\n');
fprintf('7) Q2_summary.txt —— 模型摘要\n');

disp('附录表1对应结果如下：');
disp(appendixTable1);

disp('标签 9（icq_chat）检测出的数据包编号如下：');
disp(icqPacketID');

%% ================== 以下为本脚本局部函数 ==================
function trainDir = resolveTrainDir(baseDir)
cand1 = fullfile(baseDir, 'data', 'xlsx');
cand2 = baseDir;
if exist(cand1, 'dir') && ~isempty(dir(fullfile(cand1, 'vpn_*.xlsx')))
    trainDir = cand1;
elseif exist(cand2, 'dir') && ~isempty(dir(fullfile(cand2, 'vpn_*.xlsx')))
    trainDir = cand2;
else
    error('未找到训练数据目录，请检查 baseDir 下是否存在 vpn_*.xlsx 文件。');
end
end

function testFile = resolveTestFile(baseDir)
cand1 = fullfile(baseDir, 'data', 'xlsx', 'test.xlsx');
cand2 = fullfile(baseDir, 'test.xlsx');
if isfile(cand1)
    testFile = cand1;
elseif isfile(cand2)
    testFile = cand2;
else
    error('未找到 test.xlsx。');
end
end

function [X, yNum, yName, featureNames, fileNameList, windowID] = extractTrainingWindows(trainDir, labelMap, windowSize, stepSize, silenceThr)
files = dir(fullfile(trainDir, 'vpn_*.xlsx'));
keep = true(numel(files), 1);
for i = 1:numel(files)
    nm = files(i).name;
    if startsWith(nm, '~$') || startsWith(nm, '.') || strcmpi(nm, 'test.xlsx')
        keep(i) = false;
    end
end
files = files(keep);

X = [];
yNum = [];
yName = {};
featureNames = {};
fileNameList = {};
windowID = [];

for i = 1:numel(files)
    filePath = fullfile(files(i).folder, files(i).name);
    T = readPacketTable(filePath, false);
    if isempty(T) || height(T) == 0
        continue;
    end

    className = getClassLabel(T, files(i).name);
    if ~isKey(labelMap, className)
        warning('文件 %s 未能识别标签，已跳过。', files(i).name);
        continue;
    end
    classNum = labelMap(className);

    idxPairs = makeWindowIndex(height(T), windowSize, stepSize);
    if isempty(idxPairs)
        idxPairs = [1, height(T)];
    end

    for w = 1:size(idxPairs, 1)
        Tw = T(idxPairs(w, 1):idxPairs(w, 2), :);
        x = extractWindowFeatures(Tw, silenceThr);

        if isempty(featureNames)
            featureNames = defaultFeatureNames();
        end

        X = [X; x]; %#ok<AGROW>
        yNum = [yNum; classNum]; %#ok<AGROW>
        yName = [yName; {className}]; %#ok<AGROW>
        fileNameList = [fileNameList; {files(i).name}]; %#ok<AGROW>
        windowID = [windowID; w]; %#ok<AGROW>
    end
end
end

function T = readPacketTable(filePath, includeHex)
opts = detectImportOptions(filePath, 'FileType', 'spreadsheet');
try
    opts.VariableNamingRule = 'preserve';
catch
end

wantedVars = {'Time', 'Source', 'Destination', 'Protocol', 'Length', 'Info', 'app_aux'};
if includeHex
    wantedVars = [wantedVars, {'Hex'}];
end

existedVars = intersect(wantedVars, opts.VariableNames, 'stable');
opts.SelectedVariableNames = existedVars;
T = readtable(filePath, opts);
end

function [hexMap, conflictCount] = buildHexLabelMap(trainDir, labelMap)
files = dir(fullfile(trainDir, 'vpn_*.xlsx'));
keep = true(numel(files), 1);
for i = 1:numel(files)
    nm = files(i).name;
    if startsWith(nm, '~$') || startsWith(nm, '.') || strcmpi(nm, 'test.xlsx')
        keep(i) = false;
    end
end
files = files(keep);

tmpMap = containers.Map('KeyType', 'char', 'ValueType', 'double');
conflictMap = containers.Map('KeyType', 'char', 'ValueType', 'logical');

for i = 1:numel(files)
    filePath = fullfile(files(i).folder, files(i).name);
    T = readPacketTable(filePath, true);
    if isempty(T) || height(T) == 0 || ~any(strcmp(T.Properties.VariableNames, 'Hex'))
        continue;
    end

    className = getClassLabel(T, files(i).name);
    if ~isKey(labelMap, className)
        continue;
    end
    classNum = labelMap(className);

    for r = 1:height(T)
        key = normalizeHexString(T.Hex(r));
        if strlength(key) == 0
            continue;
        end
        keyc = char(key);
        if isKey(conflictMap, keyc)
            continue;
        end
        if ~isKey(tmpMap, keyc)
            tmpMap(keyc) = classNum;
        else
            if tmpMap(keyc) ~= classNum
                remove(tmpMap, keyc);
                conflictMap(keyc) = true;
            end
        end
    end
end

hexMap = tmpMap;
conflictCount = length(keys(conflictMap));
end

function scoreMat = predictWindowScore(XtestZ, XtrainZ, ytrain, useRF, rfModel, rfClassOrder, nClass)
if useRF
    [~, rawScore] = predict(rfModel, XtestZ);
    rawScore = double(rawScore);
    scoreMat = zeros(size(XtestZ, 1), nClass);
    for j = 1:numel(rfClassOrder)
        scoreMat(:, rfClassOrder(j)) = rawScore(:, j);
    end
else
    centers = zeros(nClass, size(XtrainZ, 2));
    for c = 1:nClass
        centers(c, :) = mean(XtrainZ(ytrain == c, :), 1);
    end
    dist = zeros(size(XtestZ, 1), nClass);
    for c = 1:nClass
        diff = XtestZ - centers(c, :);
        dist(:, c) = sqrt(sum(diff.^2, 2));
    end
    scoreMat = 1 ./ (dist + eps);
    scoreMat = scoreMat ./ max(sum(scoreMat, 2), eps);
end
end

function foldID = makeBlockedFoldID(y, K)
foldID = zeros(size(y));
classes = unique(y(:))';
for c = classes
    idx = find(y == c);
    n = numel(idx);
    edges = round(linspace(0, n, K + 1));
    for k = 1:K
        seg = idx((edges(k) + 1):edges(k + 1));
        foldID(seg) = k;
    end
end
end

function res = evaluateNearestCentroidCV(X, y, foldID)
nClass = numel(unique(y));
yTrue = [];
yPred = [];
for fold = 1:max(foldID)
    tr = foldID ~= fold;
    te = foldID == fold;

    mu = mean(X(tr, :), 1);
    sigma = std(X(tr, :), 0, 1);
    sigma(sigma < 1e-12) = 1;

    Xtr = (X(tr, :) - mu) ./ sigma;
    Xte = (X(te, :) - mu) ./ sigma;

    centers = zeros(nClass, size(Xtr, 2));
    for c = 1:nClass
        centers(c, :) = mean(Xtr(y(tr) == c, :), 1);
    end

    dist = zeros(sum(te), nClass);
    for c = 1:nClass
        diff = Xte - centers(c, :);
        dist(:, c) = sqrt(sum(diff.^2, 2));
    end

    [~, pred] = min(dist, [], 2);
    yTrue = [yTrue; y(te)]; %#ok<AGROW>
    yPred = [yPred; pred]; %#ok<AGROW>
end

res.acc = mean(yTrue == yPred);
res.macroF1 = macroF1(yTrue, yPred, nClass);
end

function res = evaluateWeightedKNNCV(X, y, foldID, knnK)
nClass = numel(unique(y));
yTrue = [];
yPred = [];
ok = true;

for fold = 1:max(foldID)
    tr = foldID ~= fold;
    te = foldID == fold;

    mu = mean(X(tr, :), 1);
    sigma = std(X(tr, :), 0, 1);
    sigma(sigma < 1e-12) = 1;

    Xtr = (X(tr, :) - mu) ./ sigma;
    Xte = (X(te, :) - mu) ./ sigma;

    try
        mdl = fitcknn(Xtr, y(tr), ...
            'NumNeighbors', knnK, ...
            'Distance', 'euclidean', ...
            'DistanceWeight', 'inverse', ...
            'Standardize', false);
        pred = predict(mdl, Xte);
    catch
        ok = false;
        break;
    end

    yTrue = [yTrue; y(te)]; %#ok<AGROW>
    yPred = [yPred; pred]; %#ok<AGROW>
end

if ok
    res.acc = mean(yTrue == yPred);
    res.macroF1 = macroF1(yTrue, yPred, nClass);
else
    res.acc = NaN;
    res.macroF1 = NaN;
end
end

function res = evaluateRandomForestCV(X, y, foldID, nTrees, rngSeed)
nClass = numel(unique(y));
yTrue = [];
yPred = [];
ok = true;

for fold = 1:max(foldID)
    rng(rngSeed + fold);
    tr = foldID ~= fold;
    te = foldID == fold;

    mu = mean(X(tr, :), 1);
    sigma = std(X(tr, :), 0, 1);
    sigma(sigma < 1e-12) = 1;

    Xtr = (X(tr, :) - mu) ./ sigma;
    Xte = (X(te, :) - mu) ./ sigma;

    try
        mdl = TreeBagger(nTrees, Xtr, cellstr(string(y(tr))), ...
            'Method', 'classification', ...
            'OOBPrediction', 'Off', ...
            'Prior', 'uniform', ...
            'NumPredictorsToSample', max(1, round(sqrt(size(Xtr, 2)))));
        predCell = predict(mdl, Xte);
        pred = str2double(string(predCell));
    catch
        ok = false;
        break;
    end

    yTrue = [yTrue; y(te)]; %#ok<AGROW>
    yPred = [yPred; pred]; %#ok<AGROW>
end

if ok
    res.acc = mean(yTrue == yPred);
    res.macroF1 = macroF1(yTrue, yPred, nClass);
else
    res.acc = NaN;
    res.macroF1 = NaN;
end
end

function F = macroF1(yTrue, yPred, nClass)
f1 = nan(nClass, 1);
for c = 1:nClass
    tp = sum((yTrue == c) & (yPred == c));
    fp = sum((yTrue ~= c) & (yPred == c));
    fn = sum((yTrue == c) & (yPred ~= c));

    if tp == 0 && fp == 0 && fn == 0
        f1(c) = NaN;
        continue;
    end

    prec = tp / max(tp + fp, eps);
    rec  = tp / max(tp + fn, eps);

    if prec + rec < eps
        f1(c) = 0;
    else
        f1(c) = 2 * prec * rec / (prec + rec);
    end
end
F = mean(f1(~isnan(f1)));
end

function segTable = makeSegmentSummary(labelSeq, labelKeys)
n = numel(labelSeq);
if n == 0
    segTable = table();
    return;
end

startPos = 1;
segStart = [];
segEnd = [];
segLabel = [];
segLen = [];
for i = 2:(n + 1)
    if i == n + 1 || labelSeq(i) ~= labelSeq(i - 1)
        segStart = [segStart; startPos]; %#ok<AGROW>
        segEnd   = [segEnd; i - 1]; %#ok<AGROW>
        segLabel = [segLabel; labelSeq(i - 1)]; %#ok<AGROW>
        segLen   = [segLen; i - startPos]; %#ok<AGROW>
        startPos = i;
    end
end

segName = strings(numel(segLabel), 1);
for i = 1:numel(segLabel)
    segName(i) = string(labelKeys{segLabel(i)});
end

segTable = table(segStart, segEnd, segLabel, segName, segLen, ...
    'VariableNames', {'start_packet', 'end_packet', 'label_num', 'class_name', 'packet_count'});
end

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
    if strlength(tmp) > 0
        className = char(tmp);
        return;
    end
end

[~, nm, ~] = fileparts(fileName);
nm = erase(nm, 'vpn_');
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

function x = extractWindowFeatures(Tw, silenceThr)
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
    switchRate = mean(direction(2:end) ~= direction(1:end - 1));
else
    switchRate = 0;
end

upMask = (direction == 1);
downMask = (direction == -1);

x = [ ...
    numel(L), ...
    safeDuration(t), ...
    mean(L), std(L), min(L), max(L), ...
    prctile(L, 25), prctile(L, 50), prctile(L, 75), ...
    mean(L < 100), mean(L > 1000), ...
    mean(dt), std(dt), prctile(dt, 50), prctile(dt, 90), ...
    mean(dt > silenceThr), ...
    burstiness(dt), ...
    mean(upMask), mean(downMask), ...
    sum(L(upMask)) / max(sum(L), eps), ...
    sum(L(downMask)) / max(sum(L), eps), ...
    switchRate, ...
    mean(signedLen), std(signedLen), ...
    mean(contains(protocol, 'TCP')), ...
    mean(contains(protocol, 'UDP')), ...
    mean(contains(protocol, 'TLS') | contains(protocol, 'SSL')), ...
    mean(contains(protocol, 'SSH')), ...
    mean(contains(protocol, 'STUN')), ...
    mean(contains(info, 'ACK')), ...
    mean(contains(info, 'SYN')), ...
    mean(contains(info, 'FIN')), ...
    mean(contains(info, 'APPLICATION DATA')) ...
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

function key = normalizeHexString(x)
try
    key = string(x);
catch
    key = "";
end
if ismissing(key) || strlength(key) == 0
    key = "";
    return;
end
key = lower(regexprep(key, '\s+', ''));
end
