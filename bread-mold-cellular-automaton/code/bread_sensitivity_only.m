function bread_sensitivity_only
% BREAD_SENSITIVITY_ONLY
% ------------------------------------------------------------
% 单独执行“灵敏度分析”的 MATLAB 程序。
% 不再运行整套单次模拟/重复仿真，只分析参数扰动对模型结果的影响。
%
% 改进点：
% 1) 每个参数水平重复仿真多次；
% 2) 各参数水平使用同一组随机种子，避免把“参数变化”和“随机初始化变化”混在一起；
% 3) 输出均值、标准差、方差，并计算中心差分灵敏度系数。
%
% 使用方式：
%   1. 将本文件保存为 bread_sensitivity_only.m
%   2. 在 MATLAB 当前目录运行： bread_sensitivity_only
%
% 输出文件夹： bread_sensitivity_outputs
% ------------------------------------------------------------

clearvars -except ans;
close all;
clc;

outDir = 'bread_sensitivity_outputs';
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

params0 = defaultParams();

% -------- 灵敏度分析设置 --------
paramNames  = {'growScale', 'consumeScale', 'lambdaReplace'};
paramValues = [0.9, 1.0, 1.1];
repeatN     = 8;                     % 每个参数值重复次数
seedList    = 1001 + (1:repeatN);    % 所有参数水平共用同一组随机种子

rows = cell(numel(paramNames) * numel(paramValues) * repeatN, 1);
idx = 0;
for a = 1:numel(paramNames)
    for b = 1:numel(paramValues)
        for r = 1:repeatN
            idx = idx + 1;
            p = params0;
            p.seed = seedList(r);
            p.showFigure = false;
            p.makeGif = false;

            switch paramNames{a}
                case 'growScale'
                    p.growScale = paramValues(b);
                case 'consumeScale'
                    p.consumeScale = paramValues(b);
                case 'lambdaReplace'
                    p.lambdaReplace = paramValues(b);
            end

            result = runSingleSimulation(p);
            rows{idx} = packSensitivityRow(paramNames{a}, paramValues(b), r, p.seed, result, p.moldNamesZh);
            fprintf('参数 %s = %.2f, 重复 %d/%d 完成，稳定步数=%d，优势菌种=%s\n', ...
                paramNames{a}, paramValues(b), r, repeatN, result.stepsUsed, result.dominantNameZh);
        end
    end
end

runsTbl = vertcatCellStruct(rows);
writetable(runsTbl, fullfile(outDir, 'bread_sensitivity_runs.csv'));

summaryTbl = summarizeSensitivity(runsTbl);
writetable(summaryTbl, fullfile(outDir, 'bread_sensitivity_summary.csv'));

coeffTbl = computeSensitivityCoefficient(summaryTbl);
writetable(coeffTbl, fullfile(outDir, 'bread_sensitivity_coefficients.csv'));

plotSensitivityErrorbar(summaryTbl, fullfile(outDir, 'bread_sensitivity_plot.png'));

fprintf('\n=========== 灵敏度分析完成 ===========\n');
fprintf('逐次结果：%s\n', fullfile(outDir, 'bread_sensitivity_runs.csv'));
fprintf('汇总结果：%s\n', fullfile(outDir, 'bread_sensitivity_summary.csv'));
fprintf('灵敏度系数：%s\n', fullfile(outDir, 'bread_sensitivity_coefficients.csv'));
fprintf('图像文件：%s\n', fullfile(outDir, 'bread_sensitivity_plot.png'));
fprintf('=====================================\n');

end

% ==========================================================
%                        主仿真函数
% ==========================================================
function result = runSingleSimulation(params)

rng(params.seed);

rows = params.rows;
cols = params.cols;
mask = makeBreadMask(rows, cols);

OUTSIDE = uint8(0);
CLEAN = uint8(1);
state = OUTSIDE * ones(rows, cols, 'uint8');
state(mask) = CLEAN;
age = zeros(rows, cols);

% ---------- 静态基质场与资源场 ----------
[xx, yy] = meshgrid(1:cols, 1:rows);
centerX = mean(find(any(mask, 1)));
centerY = mean(find(any(mask, 2)));

dNorm = sqrt((xx - centerX).^2 + (yy - centerY).^2);
dNorm = dNorm / max(dNorm(mask));

edgeDist = distanceToMaskEdge(mask);
edgeDist = edgeDist / max(edgeDist(mask));

B = zeros(rows, cols);
B(mask) = 0.40 + 0.40 * edgeDist(mask) + 0.16 * (1 - dNorm(mask));
B(mask) = B(mask) + 0.03 * randn(nnz(mask), 1);
B(mask) = min(max(B(mask), 0.20), 1.00);

resource = zeros(rows, cols);
resource(mask) = 0.72 + 0.28 * B(mask);
resource(mask) = min(max(resource(mask), 0.15), 1.00);

% ---------- 初始种子点 ----------
seedList = [ ...
    18 18 2;  24 34 2;  16 56 2; ...
    12 14 4;  16 28 4;  14 64 4; 20 70 4; ...
    52 28 6;  60 34 6;  58 58 6; ...
    46 42 3;  38 62 3;  68 62 3; ...
    18 12 5;  64 24 5;  70 50 5];

for s = 1:size(seedList,1)
    r = seedList(s,1);
    c = seedList(s,2);
    typ = uint8(seedList(s,3));
    if r >= 1 && r <= rows && c >= 1 && c <= cols && mask(r,c)
        state(r,c) = typ;
        age(r,c) = 1;
    end
end

for typ = params.moldStates
    for q = 1:2
        [r, c] = randomCleanCell(state, mask);
        state(r,c) = typ;
        age(r,c) = 1;
    end
end

numTypes = numel(params.moldStates);
areaHist = zeros(params.maxSteps, numTypes);
cleanHist = zeros(params.maxSteps, 1);
changeHist = zeros(params.maxSteps, 1);
edgeHist = zeros(params.maxSteps, numTypes);

envFactor = environmentFitness(params);
consumeVec = params.consume * params.consumeScale;
stepsUsed = params.maxSteps;

for t = 1:params.maxSteps
    oldState = state;
    oldAge = age;
    newState = oldState;
    newAge = oldAge;

    % 1) 加权邻域统计
    nbr = zeros(rows, cols, numTypes);
    for k = 1:numTypes
        occ = double(oldState == params.moldStates(k));
        orthNbr = conv2(occ, params.kernelOrth, 'same');
        diagNbr = conv2(occ, params.kernelDiag, 'same');
        nbr(:,:,k) = orthNbr + params.wDiag * diagNbr;
    end

    % 2) 侵占压力
    attackScore = zeros(rows, cols, numTypes);
    for k = 1:numTypes
        Nk = nbr(:,:,k);
        interTerm = zeros(rows, cols);
        for ell = 1:numTypes
            if ell ~= k
                interTerm = interTerm + params.beta(ell, k) * nbr(:,:,ell);
            end
        end
        interTerm = min(max(interTerm, -1.5), 1.5);

        score = (Nk > 0) .* params.baseGrow(k) .* envFactor(k) ...
              .* (B .^ params.theta(k)) .* (max(resource, 1e-8) .^ params.gamma(k)) ...
              .* (Nk .^ params.alpha(k)) .* exp(interTerm);
        score = score .* mask;
        attackScore(:,:,k) = max(0, score);
    end

    % 3) 空白元胞更新
    [rrC, ccC] = find(oldState == CLEAN);
    for ii = 1:numel(rrC)
        i = rrC(ii); j = ccC(ii);
        if resource(i,j) < params.cleanMinResource
            continue;
        end
        scores = squeeze(attackScore(i,j,:))';
        totalScore = sum(scores);
        if totalScore <= 0
            continue;
        end
        pColonize = 1 - exp(-totalScore);
        if rand < pColonize
            chosen = weightedChoice(scores);
            newState(i,j) = params.moldStates(chosen);
            newAge(i,j) = 1;
        end
    end

    % 4) 已占据元胞更新
    [rrM, ccM] = find((oldState >= 2) & mask);
    for ii = 1:numel(rrM)
        i = rrM(ii); j = ccM(ii);
        residentIdx = double(oldState(i,j)) - 1;

        defense = params.baseDefense(residentIdx) ...
                * (1 + params.eta * oldAge(i,j)) ...
                * (max(resource(i,j), 1e-8) ^ params.mu(residentIdx)) ...
                * (1 + params.chi * nbr(i,j,residentIdx));

        replaceGain = zeros(1, numTypes);
        for k = 1:numTypes
            if k == residentIdx
                continue;
            end
            replaceGain(k) = max(0, attackScore(i,j,k) - params.lambdaReplace * defense);
        end

        totalGain = sum(replaceGain);
        if totalGain > 0
            pSwitch = min(0.85, 1 - exp(-totalGain));
            if rand < pSwitch
                chosen = weightedChoice(replaceGain);
                newState(i,j) = params.moldStates(chosen);
                newAge(i,j) = 1;
            else
                newAge(i,j) = oldAge(i,j) + 1;
            end
        else
            newAge(i,j) = oldAge(i,j) + 1;
        end
    end

    % 5) 资源更新
    lapR = conv2(resource, params.kernelLap, 'same');
    newResource = resource + params.DR * lapR - params.cClean * double(newState == CLEAN);
    for k = 1:numTypes
        newResource = newResource - consumeVec(k) * double(newState == params.moldStates(k));
    end
    newResource = min(max(newResource, 0), 1);
    newResource(~mask) = 0;

    % 6) 写回状态、菌龄、资源
    state = newState;
    resource = newResource;
    age = zeros(rows, cols);
    moldOcc = (state >= 2);
    age(moldOcc & (state ~= oldState)) = 1;
    sameOcc = moldOcc & (state == oldState);
    age(sameOcc) = oldAge(sameOcc) + 1;

    % 7) 历史指标
    breadArea = nnz(mask);
    cleanHist(t) = nnz(state == CLEAN) / breadArea;
    for k = 1:numTypes
        areaHist(t,k) = nnz(state == params.moldStates(k)) / breadArea;
        edgeHist(t,k) = computeEdgeLength(state, params.moldStates(k), mask);
    end
    changeHist(t) = nnz((state ~= oldState) & mask);

    % 8) 稳定判据
    if t >= params.minSteps
        if isStable(areaHist, cleanHist, changeHist, t, params.stableWindow, params.areaTol, params.changeTol)
            stepsUsed = t;
            break;
        end
    end
end

areaHist = areaHist(1:stepsUsed, :);
cleanHist = cleanHist(1:stepsUsed);
edgeHist = edgeHist(1:stepsUsed, :);

finalFrac = areaHist(end, :);
[dominantFrac, dominantIdx] = max(finalFrac);
finalEdge = edgeHist(end, :)';

result.stepsUsed = stepsUsed;
result.areaHist = areaHist;
result.cleanHist = cleanHist;
result.edgeHist = edgeHist;
result.finalFrac = finalFrac;
result.finalEdge = finalEdge;
result.dominantIdx = dominantIdx;
result.dominantFrac = dominantFrac;
result.dominantNameZh = params.moldNamesZh{dominantIdx};
result.cleanFinal = cleanHist(end);

end

% ==========================================================
%                    灵敏度结果打包与汇总
% ==========================================================
function s = packSensitivityRow(parameter, value, repeatID, seed, result, moldNamesZh)
s = struct();
s.parameter = string(parameter);
s.value = value;
s.repeatID = repeatID;
s.seed = seed;
s.stepsUsed = result.stepsUsed;
s.cleanFinal = result.cleanFinal;
s.dominantName = string(result.dominantNameZh);
s.dominantFrac = result.dominantFrac;
for k = 1:numel(moldNamesZh)
    en = lower(strrep(moldNamesZh{k}, '色型', ''));
    switch moldNamesZh{k}
        case '白色型', en = 'white';
        case '绿色型', en = 'green';
        case '黑色型', en = 'black';
        case '黄色型', en = 'yellow';
        case '橙色型', en = 'orange';
    end
    s.(['frac_', en]) = result.finalFrac(k);
    s.(['edge_', en]) = result.finalEdge(k);
end
end

function tbl = summarizeSensitivity(runsTbl)
g = findgroups(runsTbl(:, {'parameter','value'}));
keys = unique(runsTbl(:, {'parameter','value'}), 'rows', 'stable');

meanStep = splitapply(@mean, runsTbl.stepsUsed, g);
stdStep  = splitapply(@std,  runsTbl.stepsUsed, g);
varStep  = splitapply(@var,  runsTbl.stepsUsed, g);
meanDom  = splitapply(@mean, runsTbl.dominantFrac, g);
stdDom   = splitapply(@std,  runsTbl.dominantFrac, g);
varDom   = splitapply(@var,  runsTbl.dominantFrac, g);
meanClean= splitapply(@mean, runsTbl.cleanFinal, g);
stdClean = splitapply(@std,  runsTbl.cleanFinal, g);
varClean = splitapply(@var,  runsTbl.cleanFinal, g);

modeDominant = splitapply(@modeString, runsTbl.dominantName, g);

fracWhiteMean  = splitapply(@mean, runsTbl.frac_white, g);
fracGreenMean  = splitapply(@mean, runsTbl.frac_green, g);
fracBlackMean  = splitapply(@mean, runsTbl.frac_black, g);
fracYellowMean = splitapply(@mean, runsTbl.frac_yellow, g);
fracOrangeMean = splitapply(@mean, runsTbl.frac_orange, g);

repeatCount = splitapply(@numel, runsTbl.stepsUsed, g);

tbl = table(keys.parameter, keys.value, repeatCount, modeDominant, ...
    meanStep, stdStep, varStep, meanDom, stdDom, varDom, meanClean, stdClean, varClean, ...
    fracWhiteMean, fracGreenMean, fracBlackMean, fracYellowMean, fracOrangeMean, ...
    'VariableNames', {'parameter','value','repeatN','modeDominant','meanStep','stdStep','varStep', ...
    'meanDominantFrac','stdDominantFrac','varDominantFrac','meanCleanFinal','stdCleanFinal','varCleanFinal', ...
    'meanWhite','meanGreen','meanBlack','meanYellow','meanOrange'});
end

function coeffTbl = computeSensitivityCoefficient(summaryTbl)
params = unique(summaryTbl.parameter, 'stable');
rows = cell(numel(params),1);
for i = 1:numel(params)
    p = params(i);
    sub = summaryTbl(summaryTbl.parameter == p, :);
    sub = sortrows(sub, 'value');
    if height(sub) < 3
        error('参数 %s 的水平不足 3 个，无法计算中心差分灵敏度系数。', p);
    end
    vLow = sub.value(1);  yLow = sub.meanDominantFrac(1);
    vMid = sub.value(2);  yMid = sub.meanDominantFrac(2);
    vHigh= sub.value(3);  yHigh= sub.meanDominantFrac(3);

    coeff = ((yHigh - yLow) / (vHigh - vLow)) * (vMid / max(yMid, 1e-8));
    rows{i} = struct('parameter', p, 'baseValue', vMid, 'baseMeanDominantFrac', yMid, 'sensitivityCoeff', coeff);
end
coeffTbl = vertcatCellStruct(rows);
end

function plotSensitivityErrorbar(summaryTbl, filename)
fig = figure('Color', 'w', 'Position', [160 160 900 480]);
hold on;
params = unique(summaryTbl.parameter, 'stable');
for i = 1:numel(params)
    sub = summaryTbl(summaryTbl.parameter == params(i), :);
    sub = sortrows(sub, 'value');
    errorbar(sub.value, sub.meanDominantFrac, sub.stdDominantFrac, '-o', 'LineWidth', 1.8, 'MarkerSize', 8);
end
hold off;
grid on;
xlabel('参数取值');
ylabel('最终优势菌种面积占比（均值 ± 标准差）');
title('灵敏度分析图');
legend(cellstr(params), 'Location', 'northeast');
saveas(fig, filename);
close(fig);
end

% ==========================================================
%                        默认参数
% ==========================================================
function params = defaultParams()
params.rows = 90;
params.cols = 90;
params.maxSteps = 140;
params.minSteps = 50;
params.stableWindow = 10;
params.areaTol = 8e-4;
params.changeTol = 2.5;
params.makeGif = false;
params.showFigure = false;
params.seed = 1;

params.T = 25;
params.aw = 0.95;
params.pH = 5.5;

params.moldStates = uint8(2:6);
params.moldNamesZh = {'白色型','绿色型','黑色型','黄色型','橙色型'};

params.kernelOrth = [0 1 0; 1 0 1; 0 1 0];
params.kernelDiag = [1 0 1; 0 0 0; 1 0 1];
params.kernelLap  = [0 1 0; 1 -4 1; 0 1 0];
params.wDiag = 0.7;

params.growScale = 1.0;
params.consumeScale = 1.0;
params.lambdaReplace = 1.0;
params.cleanMinResource = 0.14;

params.baseGrow = [0.82, 0.70, 0.66, 0.54, 0.58];
params.baseDefense = [0.84, 0.76, 0.86, 0.68, 0.72];
params.theta = [1.00, 1.00, 1.05, 0.95, 1.00];
params.gamma = [0.58, 0.70, 0.76, 0.72, 0.74];
params.alpha = [0.95, 0.92, 0.90, 0.88, 0.90];
params.mu = [0.90, 0.90, 0.95, 0.85, 0.88];
params.consume = [0.0090, 0.0075, 0.0070, 0.0060, 0.0065];
params.cClean = 0.0010;
params.DR = 0.04;
params.eta = 0.010;
params.chi = 0.06;

params.Topt = [24, 25, 29, 26, 27];
params.Tsigma = [6, 5, 6, 6, 6];
params.awOpt = [0.95, 0.94, 0.93, 0.94, 0.94];
params.awSigma = [0.03, 0.04, 0.04, 0.03, 0.03];
params.pHopt = [5.5, 5.6, 5.8, 5.4, 5.5];
params.pHSigma = [0.8, 0.8, 0.9, 0.8, 0.8];

params.beta = [ ...
     0.00,  0.04,  0.08, -0.04, -0.03; ...
    -0.05,  0.00, -0.05,  0.07,  0.04; ...
    -0.10, -0.06,  0.00, -0.07, -0.05; ...
    -0.03,  0.04, -0.03,  0.00,  0.06; ...
    -0.03,  0.03, -0.04,  0.06,  0.00];
end

% ==========================================================
%                        环境适宜度
% ==========================================================
function envFactor = environmentFitness(params)
baseGrow = params.baseGrow * params.growScale;
tempFactor = exp(-((params.T - params.Topt).^2) ./ (2 * params.Tsigma.^2));
awFactor   = exp(-((params.aw - params.awOpt).^2) ./ (2 * params.awSigma.^2));
pHFactor   = exp(-((params.pH - params.pHopt).^2) ./ (2 * params.pHSigma.^2));
envFactor = baseGrow .* tempFactor .* awFactor .* pHFactor;
envFactor = max(envFactor, 0.02);
end

% ==========================================================
%                        面包掩膜
% ==========================================================
function mask = makeBreadMask(rows, cols)
mask = false(rows, cols);
side = 72;
top = 8;
left = 8;
mask(top:top+side-1, left:left+side-1) = true;
edgeNoise = rand(rows, cols) > 0.9975;
edgeBand = false(rows, cols);
edgeBand(top+8:top+side-8, left:left+1) = true;
edgeBand(top+8:top+side-8, left+side-2:left+side-1) = true;
edgeBand(top:top+1, left+8:left+side-8) = true;
edgeBand(top+side-2:top+side-1, left+8:left+side-8) = true;
mask(edgeBand & edgeNoise) = false;
end

function d = distanceToMaskEdge(mask)
[rows, cols] = size(mask);
d = zeros(rows, cols);
for i = 1:rows
    for j = 1:cols
        if ~mask(i,j)
            continue;
        end
        up = 0; ii = i;
        while ii >= 1 && mask(ii,j)
            up = up + 1; ii = ii - 1;
        end
        down = 0; ii = i;
        while ii <= rows && mask(ii,j)
            down = down + 1; ii = ii + 1;
        end
        left = 0; jj = j;
        while jj >= 1 && mask(i,jj)
            left = left + 1; jj = jj - 1;
        end
        right = 0; jj = j;
        while jj <= cols && mask(i,jj)
            right = right + 1; jj = jj + 1;
        end
        d(i,j) = min([up, down, left, right]);
    end
end
end

function [r, c] = randomCleanCell(state, mask)
cleanPos = find(mask & state == 1);
pick = cleanPos(randi(numel(cleanPos)));
[r, c] = ind2sub(size(state), pick);
end

function idx = weightedChoice(w)
w = double(w(:))';
w = max(w, 0);
s = sum(w);
if s <= 0
    idx = randi(numel(w));
    return;
end
w = w / s;
cs = cumsum(w);
r = rand;
idx = find(r <= cs, 1, 'first');
if isempty(idx)
    idx = numel(w);
end
end

function tf = isStable(areaHist, cleanHist, changeHist, t, stableWindow, areaTol, changeTol)
if t <= stableWindow
    tf = false;
    return;
end
segA = areaHist(t-stableWindow+1:t, :);
segC = cleanHist(t-stableWindow+1:t);
segCh = changeHist(t-stableWindow+1:t);
maxAreaJump = max(abs(diff(segA, 1, 1)), [], 'all');
maxCleanJump = max(abs(diff(segC)));
meanChange = mean(segCh);
tf = (max(maxAreaJump, maxCleanJump) < areaTol) && (meanChange < changeTol);
end

function L = computeEdgeLength(state, moldState, mask)
occ = (state == moldState) & mask;
if ~any(occ, 'all')
    L = 0;
    return;
end
up    = circshift(state, [-1,  0]) ~= moldState;
down  = circshift(state, [ 1,  0]) ~= moldState;
left  = circshift(state, [ 0, -1]) ~= moldState;
right = circshift(state, [ 0,  1]) ~= moldState;
edge = occ & (up | down | left | right);
L = nnz(edge);
end

function out = vertcatCellStruct(cellStructs)
if isempty(cellStructs)
    out = table();
    return;
end
out = struct2table(cellStructs{1});
for i = 2:numel(cellStructs)
    out = [out; struct2table(cellStructs{i})]; %#ok<AGROW>
end
end

function s = modeString(x)
x = string(x);
ux = unique(x, 'stable');
count = zeros(size(ux));
for i = 1:numel(ux)
    count(i) = sum(x == ux(i));
end
[~, idx] = max(count);
s = ux(idx);
end
