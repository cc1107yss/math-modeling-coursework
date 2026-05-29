function bread_ca_report
% BREAD_CA_REPORT
% ------------------------------------------------------------
% 基于“多菌种竞争-促进型元胞自动机 + 资源场 + 菌龄 + 边界替换”
% 的面包霉菌时空演化模拟程序。
%
% 运行方式：
%   1) 将本文件命名为 bread_ca_report.m
%   2) 在 MATLAB 当前工作目录中运行： bread_ca_report
%
% 主要输出（保存在 bread_report_outputs 文件夹中）：
%   bread_single.gif                 单次模拟动态图
%   bread_single_final.png           单次模拟最终分布图
%   bread_single_curves.png          单次模拟面积占比曲线图
%   bread_single_history.csv         单次模拟逐步历史数据
%   bread_single_summary.csv         单次模拟最终摘要
%   bread_single_interfaces.csv      单次模拟最终交界长度矩阵
%   bread_repeat_runs.csv            多次重复仿真逐次结果
%   bread_repeat_summary.csv         多次重复仿真的均值/方差
%   bread_sensitivity_runs.csv       灵敏度分析逐次结果
%   bread_sensitivity_summary.csv    灵敏度分析汇总结果
%   bread_sensitivity_plot.png       灵敏度分析图
%
% 说明：
%   本程序对应论文中的第 4 部分“模型建立与计算”，并额外补上：
%   (1) 重复仿真统计；
%   (2) 灵敏度分析（模型检验）；
%   (3) 边缘长度与交界长度提取。
% ------------------------------------------------------------

clearvars -except ans;
close all;
clc;

outDir = 'bread_report_outputs';
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

% ==================== 1. 基准参数 ====================
params = defaultParams();

% ==================== 2. 单次模拟 ====================
params.makeGif = true;
params.showFigure = true;
params.seed = 7;
basePrefix = fullfile(outDir, 'bread_single');
baseResult = runSingleSimulation(params, basePrefix);

% ==================== 3. 多次重复仿真 ====================
% 老师要求：多次重复仿真，计算相关数值结果的均值和方差
repeatN = 8;
repeatRows = cell(repeatN, 1);
for r = 1:repeatN
    p = params;
    p.makeGif = false;
    p.showFigure = false;
    p.seed = 100 + r;
    result = runSingleSimulation(p, '');
    repeatRows{r} = packRepeatRow(r, result, p.moldNamesZh);
    fprintf('重复仿真 %d / %d 完成，稳定步数 = %d\n', r, repeatN, result.stepsUsed);
end
repeatTbl = vertcatCellStruct(repeatRows);
repeatRunsFile = fullfile(outDir, 'bread_repeat_runs.csv');
writetable(repeatTbl, repeatRunsFile);
repeatSummaryTbl = summarizeMeanVar(repeatTbl, {'run'});
repeatSummaryFile = fullfile(outDir, 'bread_repeat_summary.csv');
writetable(repeatSummaryTbl, repeatSummaryFile);

% ==================== 4. 灵敏度分析 ====================
% 老师要求：模型检验可用灵敏度分析方法进行
% 这里选择三个最关键参数：
%   growScale      基础生长率整体缩放
%   consumeScale   资源消耗整体缩放
%   lambdaReplace  边界替换阈值
% 每个参数取 0.9, 1.0, 1.1 三个水平。
paramNames = {'growScale', 'consumeScale', 'lambdaReplace'};
paramValues = [0.9, 1.0, 1.1];
runID = 0;
sensRows = cell(numel(paramNames) * numel(paramValues), 1);
for a = 1:numel(paramNames)
    for b = 1:numel(paramValues)
        runID = runID + 1;
        p = params;
        p.makeGif = false;
        p.showFigure = false;
        p.seed = 500 + runID;
        switch paramNames{a}
            case 'growScale'
                p.growScale = paramValues(b);
            case 'consumeScale'
                p.consumeScale = paramValues(b);
            case 'lambdaReplace'
                p.lambdaReplace = paramValues(b);
        end
        result = runSingleSimulation(p, '');
        sensRows{runID} = packSensitivityRow(paramNames{a}, paramValues(b), result, p.moldNamesZh);
        fprintf('灵敏度分析：%s = %.2f 完成。\n', paramNames{a}, paramValues(b));
    end
end
sensTbl = vertcatCellStruct(sensRows);
sensRunsFile = fullfile(outDir, 'bread_sensitivity_runs.csv');
writetable(sensTbl, sensRunsFile);
sensSummaryTbl = summarizeMeanVar(sensTbl, {'parameter','value'});
sensSummaryFile = fullfile(outDir, 'bread_sensitivity_summary.csv');
writetable(sensSummaryTbl, sensSummaryFile);
plotSensitivity(sensTbl, fullfile(outDir, 'bread_sensitivity_plot.png'));

% ==================== 5. 命令窗口摘要 ====================
fprintf('\n=============== 运行完成 ===============\n');
fprintf('单次模拟稳定步数：%d\n', baseResult.stepsUsed);
fprintf('优势菌种：%s\n', baseResult.dominantNameZh);
fprintf('输出文件夹：%s\n', outDir);
fprintf('主要结果文件：\n');
fprintf('  %s\n', fullfile(outDir, 'bread_single_final.png'));
fprintf('  %s\n', fullfile(outDir, 'bread_single_curves.png'));
fprintf('  %s\n', fullfile(outDir, 'bread_repeat_summary.csv'));
fprintf('  %s\n', fullfile(outDir, 'bread_sensitivity_summary.csv'));
fprintf('========================================\n');

end

% ==========================================================
%                        主仿真函数
% ==========================================================
function result = runSingleSimulation(params, savePrefix)

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

% ---------- 颜色映射 ----------
cmap = [ ...
    0.86 0.86 0.86; ... % 0 背景
    0.86 0.79 0.67; ... % 1 干净面包
    0.98 0.98 0.98; ... % 2 白色型
    0.33 0.63 0.35; ... % 3 绿色型
    0.10 0.10 0.10; ... % 4 黑色型
    0.94 0.86 0.38; ... % 5 黄色型
    0.90 0.55 0.18];    % 6 橙色型

% ---------- 预分配历史记录 ----------
numTypes = numel(params.moldStates);
areaHist = zeros(params.maxSteps, numTypes);
cleanHist = zeros(params.maxSteps, 1);
changeHist = zeros(params.maxSteps, 1);
edgeHist = zeros(params.maxSteps, numTypes);

% ---------- 实时图 ----------
if params.showFigure
    fig = figure('Name', 'bread-CA', 'Color', 'w', 'Position', [100 100 1080 500]);
    tl = tiledlayout(fig, 1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
    ax1 = nexttile(tl, 1);
    imh = imagesc(ax1, state);
    axis(ax1, 'image');
    axis(ax1, 'off');
    colormap(ax1, cmap);
    caxis(ax1, [0 6]);
    title(ax1, '面包霉菌空间分布');

    ax2 = nexttile(tl, 2);
    hold(ax2, 'on');
    lineColors = [0 0 0; 0 0.55 0; 0.15 0.15 0.15; 0.82 0.66 0.08; 0.90 0.45 0.10; 0.55 0.38 0.20];
    hLines = gobjects(numTypes + 1, 1);
    for k = 1:numTypes
        hLines(k) = plot(ax2, nan, nan, 'LineWidth', 1.6, 'Color', lineColors(k,:));
    end
    hLines(numTypes + 1) = plot(ax2, nan, nan, '--', 'LineWidth', 1.4, 'Color', lineColors(end,:));
    hold(ax2, 'off');
    grid(ax2, 'on');
    xlabel(ax2, '步数');
    ylabel(ax2, '面积占比');
    ylim(ax2, [0 1]);
    xlim(ax2, [1 params.maxSteps]);
    legend(ax2, [params.moldNamesZh, {'干净面包'}], 'Location', 'eastoutside');
    title(ax2, '面积占比变化');
    drawnow;
else
    fig = [];
    ax1 = [];
    ax2 = [];
    imh = [];
    hLines = [];
end

% ---------- GIF 初始化 ----------
if params.makeGif && ~isempty(savePrefix)
    gifFile = [savePrefix, '.gif'];
    if exist(gifFile, 'file')
        delete(gifFile);
    end
else
    gifFile = '';
end

% ---------- 环境适宜度（固定环境下可预先计算） ----------
envFactor = environmentFitness(params);

stepsUsed = params.maxSteps;

for t = 1:params.maxSteps
    oldState = state;
    oldAge = age;
    newState = oldState;
    newAge = oldAge;

    % ---------- 1) 加权邻域统计 ----------
    nbr = zeros(rows, cols, numTypes);
    for k = 1:numTypes
        occ = double(oldState == params.moldStates(k));
        orthNbr = conv2(occ, params.kernelOrth, 'same');
        diagNbr = conv2(occ, params.kernelDiag, 'same');
        nbr(:,:,k) = orthNbr + params.wDiag * diagNbr;
    end

    % ---------- 2) 侵占压力计算 ----------
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

    % ---------- 3) 更新空白元胞 ----------
    [rrC, ccC] = find(oldState == CLEAN);
    for idx = 1:numel(rrC)
        i = rrC(idx);
        j = ccC(idx);

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

    % ---------- 4) 更新已占据元胞（边界替换） ----------
    [rrM, ccM] = find((oldState >= 2) & mask);
    for idx = 1:numel(rrM)
        i = rrM(idx);
        j = ccM(idx);
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

    % ---------- 5) 资源更新 ----------
    lapR = conv2(resource, params.kernelLap, 'same');
    newResource = resource + params.DR * lapR - params.cClean * double(newState == CLEAN);
    for k = 1:numTypes
        newResource = newResource - params.consume(k) * double(newState == params.moldStates(k));
    end
    newResource = min(max(newResource, 0), 1);
    newResource(~mask) = 0;

    % ---------- 6) 写回状态/菌龄/资源 ----------
    state = newState;
    resource = newResource;
    age = zeros(rows, cols);
    moldOcc = (state >= 2);
    age(moldOcc & (state ~= oldState)) = 1;
    age(moldOcc & (state == oldState)) = oldAge(moldOcc & (state == oldState)) + 1;

    % ---------- 7) 历史指标 ----------
    breadArea = nnz(mask);
    cleanHist(t) = nnz(state == CLEAN) / breadArea;
    for k = 1:numTypes
        areaHist(t,k) = nnz(state == params.moldStates(k)) / breadArea;
        edgeHist(t,k) = computeEdgeLength(state, params.moldStates(k), mask);
    end
    changeHist(t) = nnz((state ~= oldState) & mask);

    % ---------- 8) 实时刷新 ----------
    if params.showFigure
        set(imh, 'CData', state);
        title(ax1, sprintf('面包霉菌空间分布（第 %d 步）', t));
        for k = 1:numTypes
            set(hLines(k), 'XData', 1:t, 'YData', areaHist(1:t,k));
        end
        set(hLines(numTypes + 1), 'XData', 1:t, 'YData', cleanHist(1:t));
        title(ax2, sprintf('面积占比变化（当前步：%d）', t));
        drawnow limitrate;
    end

    % ---------- 9) 写 GIF ----------
    if params.makeGif && ~isempty(savePrefix) && mod(t, params.frameEvery) == 0 && ~isempty(fig)
        frame = getframe(fig);
        im = frame2im(frame);
        [A, map] = rgb2ind(im, 256);
        if t == params.frameEvery
            imwrite(A, map, gifFile, 'gif', 'LoopCount', Inf, 'DelayTime', params.frameDelay);
        else
            imwrite(A, map, gifFile, 'gif', 'WriteMode', 'append', 'DelayTime', params.frameDelay);
        end
    end

    % ---------- 10) 稳定判据 ----------
    if t >= params.minSteps
        if isStable(areaHist, cleanHist, changeHist, t, params.stableWindow, params.areaTol, params.changeTol)
            stepsUsed = t;
            break;
        end
    end
end

% ---------- 截断历史 ----------
areaHist = areaHist(1:stepsUsed, :);
cleanHist = cleanHist(1:stepsUsed);
changeHist = changeHist(1:stepsUsed);
edgeHist = edgeHist(1:stepsUsed, :);

% ---------- 最终指标 ----------
finalFrac = areaHist(end, :);
[dominantFrac, dominantIdx] = max(finalFrac);
finalCell = zeros(numTypes, 1);
for k = 1:numTypes
    finalCell(k) = nnz(state == params.moldStates(k));
end
finalEdge = edgeHist(end, :)';

% 最终交界长度矩阵
interfaceMat = zeros(numTypes, numTypes);
for i = 1:numTypes
    for j = 1:numTypes
        if i ~= j
            interfaceMat(i,j) = computeInterfaceLength(state, params.moldStates(i), params.moldStates(j), mask);
        end
    end
end

% ---------- 输出文件 ----------
if ~isempty(savePrefix)
    finalFigFile = [savePrefix, '_final.png'];
    curveFigFile = [savePrefix, '_curves.png'];
    histFile = [savePrefix, '_history.csv'];
    summaryFile = [savePrefix, '_summary.csv'];
    interfaceFile = [savePrefix, '_interfaces.csv'];

    % 最终分布图
    fig2 = figure('Name', 'bread-final', 'Color', 'w', 'Position', [160 120 560 560]);
    imagesc(state);
    axis image off;
    colormap(cmap);
    caxis([0 6]);
    title(sprintf('最终分布图（第 %d 步）', stepsUsed), 'FontWeight', 'bold');
    saveFigureSafe(fig2, finalFigFile);
    close(fig2);

    % 面积变化曲线
    fig3 = figure('Name', 'bread-curves', 'Color', 'w', 'Position', [180 180 860 430]);
    hold on;
    lineColors = [0 0 0; 0 0.55 0; 0.15 0.15 0.15; 0.82 0.66 0.08; 0.90 0.45 0.10; 0.55 0.38 0.20];
    for k = 1:numTypes
        plot(1:stepsUsed, areaHist(:,k), 'LineWidth', 1.8, 'Color', lineColors(k,:));
    end
    plot(1:stepsUsed, cleanHist, '--', 'LineWidth', 1.4, 'Color', lineColors(end,:));
    hold off;
    grid on;
    xlabel('步数');
    ylabel('面积占比');
    ylim([0 1]);
    xlim([1 max(stepsUsed, 2)]);
    legend([params.moldNamesZh, {'干净面包'}], 'Location', 'eastoutside');
    title('面积占比变化曲线');
    saveFigureSafe(fig3, curveFigFile);
    close(fig3);

    % 历史表
    historyTbl = table((1:stepsUsed)', cleanHist, areaHist(:,1), areaHist(:,2), areaHist(:,3), areaHist(:,4), areaHist(:,5), ...
        edgeHist(:,1), edgeHist(:,2), edgeHist(:,3), edgeHist(:,4), edgeHist(:,5), changeHist, ...
        'VariableNames', {'step','clean','white','green','black','yellow','orange','edge_white','edge_green','edge_black','edge_yellow','edge_orange','changes'});
    writetable(historyTbl, histFile);

    % 摘要表
    summaryTbl = table((1:numTypes)', params.moldNamesZh', finalCell, finalFrac', finalEdge, ...
        'VariableNames', {'编号','霉菌类型','最终格子数','最终面积占比','最终边缘长度'});
    writetable(summaryTbl, summaryFile);

    % 交界矩阵表
    interfaceTbl = array2table(interfaceMat, 'VariableNames', params.moldNamesEn, 'RowNames', params.moldNamesEn);
    writetable(interfaceTbl, interfaceFile, 'WriteRowNames', true);
end

% ---------- 返回结构 ----------
result.stepsUsed = stepsUsed;
result.state = state;
result.areaHist = areaHist;
result.cleanHist = cleanHist;
result.edgeHist = edgeHist;
result.finalFrac = finalFrac;
result.finalCell = finalCell;
result.finalEdge = finalEdge;
result.dominantIdx = dominantIdx;
result.dominantFrac = dominantFrac;
result.dominantNameZh = params.moldNamesZh{dominantIdx};
result.interfaceMat = interfaceMat;
result.cleanFinal = cleanHist(end);

if params.showFigure && ~isempty(fig) && isvalid(fig)
    % 保留单次主图，不强制关闭
end

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
params.frameDelay = 0.10;
params.frameEvery = 2;
params.makeGif = false;
params.showFigure = true;
params.seed = 1;

% 环境参数
params.T = 25;
params.aw = 0.95;
params.pH = 5.5;

% 状态编码
params.moldStates = uint8(2:6);
params.moldNamesZh = {'白色型','绿色型','黑色型','黄色型','橙色型'};
params.moldNamesEn = {'white','green','black','yellow','orange'};

% 核函数
params.kernelOrth = [0 1 0; 1 0 1; 0 1 0];
params.kernelDiag = [1 0 1; 0 0 0; 1 0 1];
params.kernelLap = [0 1 0; 1 -4 1; 0 1 0];
params.wDiag = 0.7;

% 生长、资源、防守参数
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

% 环境最适参数（抽象化）
params.Topt = [24, 25, 29, 26, 27];
params.Tsigma = [6, 5, 6, 6, 6];
params.awOpt = [0.95, 0.94, 0.93, 0.94, 0.94];
params.awSigma = [0.03, 0.04, 0.04, 0.03, 0.03];
params.pHopt = [5.5, 5.6, 5.8, 5.4, 5.5];
params.pHSigma = [0.8, 0.8, 0.9, 0.8, 0.8];

% 异类相互作用矩阵：行=来自邻居类型，列=目标类型
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
awFactor = exp(-((params.aw - params.awOpt).^2) ./ (2 * params.awSigma.^2));
pHFactor = exp(-((params.pH - params.pHopt).^2) ./ (2 * params.pHSigma.^2));
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

% 只做非常轻微的边缘扰动，保留方形轮廓
edgeNoise = rand(rows, cols) > 0.9975;
edgeBand = false(rows, cols);
edgeBand(top+8:top+side-8, left:left+1) = true;
edgeBand(top+8:top+side-8, left+side-2:left+side-1) = true;
edgeBand(top:top+1, left+8:left+side-8) = true;
edgeBand(top+side-2:top+side-1, left+8:left+side-8) = true;
mask(edgeBand & edgeNoise) = false;
end

% ==========================================================
%                     到边缘距离（粗略）
% ==========================================================
function d = distanceToMaskEdge(mask)
[rows, cols] = size(mask);
d = zeros(rows, cols);
for i = 1:rows
    for j = 1:cols
        if ~mask(i,j)
            continue;
        end
        up = 0;
        ii = i;
        while ii >= 1 && mask(ii,j)
            up = up + 1;
            ii = ii - 1;
        end
        down = 0;
        ii = i;
        while ii <= rows && mask(ii,j)
            down = down + 1;
            ii = ii + 1;
        end
        left = 0;
        jj = j;
        while jj >= 1 && mask(i,jj)
            left = left + 1;
            jj = jj - 1;
        end
        right = 0;
        jj = j;
        while jj <= cols && mask(i,jj)
            right = right + 1;
            jj = jj + 1;
        end
        d(i,j) = min([up, down, left, right]);
    end
end
end

% ==========================================================
%                        稳定判据
% ==========================================================
function flag = isStable(areaHist, cleanHist, changeHist, t, win, areaTol, changeTol)
if t < win + 2
    flag = false;
    return;
end
idx = (t-win+1):t;
meanChange = mean(changeHist(idx));
allSeries = [areaHist(:,1:end), cleanHist];
recent = allSeries(idx, :);
deltaMat = abs(diff(recent, 1, 1));
maxDelta = max(deltaMat(:));
flag = (meanChange <= changeTol) && (maxDelta <= areaTol);
end

% ==========================================================
%                        边缘长度
% ==========================================================
function edgeLen = computeEdgeLength(state, moldState, mask)
kernel = ones(3);
kernel(2,2) = 0;
sameNbr = conv2(double(state == moldState), kernel, 'same');
edgeLen = nnz((state == moldState) & mask & (sameNbr < 8));
end

% ==========================================================
%                        交界长度
% ==========================================================
function interfaceLen = computeInterfaceLength(state, moldA, moldB, mask)
kernel = ones(3);
kernel(2,2) = 0;
otherNbr = conv2(double(state == moldB), kernel, 'same');
interfaceLen = nnz((state == moldA) & mask & (otherNbr > 0));
end

% ==========================================================
%                      权重随机选择
% ==========================================================
function idx = weightedChoice(w)
wsum = sum(w);
if wsum <= 0
    idx = 1;
    return;
end
r = rand * wsum;
cs = cumsum(w);
idx = find(r <= cs, 1, 'first');
if isempty(idx)
    idx = numel(w);
end
end

% ==========================================================
%                      随机取干净格子
% ==========================================================
function [r, c] = randomCleanCell(state, mask)
clean = find(mask & (state == 1));
if isempty(clean)
    avail = find(mask);
    pick = avail(randi(numel(avail)));
else
    pick = clean(randi(numel(clean)));
end
[r, c] = ind2sub(size(state), pick);
end

% ==========================================================
%                      保存图片（兼容）
% ==========================================================
function saveFigureSafe(fig, filename)
try
    if exist('exportgraphics', 'file')
        exportgraphics(fig, filename, 'Resolution', 180);
    else
        saveas(fig, filename);
    end
catch
    try
        saveas(fig, filename);
    catch
        warning('图像 %s 保存失败。', filename);
    end
end
end

% ==========================================================
%                   打包重复仿真单行结果
% ==========================================================
function s = packRepeatRow(runID, result, moldNamesZh)
s = struct();
s.run = runID;
s.stable_step = result.stepsUsed;
s.dominant_fraction = result.dominantFrac;
s.clean = result.cleanFinal;
for k = 1:numel(moldNamesZh)
    varName = ['frac_', safeFieldName(moldNamesZh{k})];
    edgeName = ['edge_', safeFieldName(moldNamesZh{k})];
    s.(varName) = result.finalFrac(k);
    s.(edgeName) = result.finalEdge(k);
end
end

% ==========================================================
%                  打包灵敏度分析单行结果
% ==========================================================
function s = packSensitivityRow(parameter, value, result, moldNamesZh)
s = struct();
s.parameter = parameter;
s.value = value;
s.stable_step = result.stepsUsed;
s.dominant_fraction = result.dominantFrac;
s.clean = result.cleanFinal;
for k = 1:numel(moldNamesZh)
    varName = ['frac_', safeFieldName(moldNamesZh{k})];
    s.(varName) = result.finalFrac(k);
end
end

% ==========================================================
%                 struct 单元格拼成 table
% ==========================================================
function T = vertcatCellStruct(cellStruct)
validIdx = ~cellfun(@isempty, cellStruct);
cellStruct = cellStruct(validIdx);
S = [cellStruct{:}];
T = struct2table(S);
end

% ==========================================================
%                 计算均值和方差汇总表
% ==========================================================
function summaryTbl = summarizeMeanVar(tbl, groupVars)
varNames = tbl.Properties.VariableNames;
numVars = varNames(varfun(@isnumeric, tbl, 'OutputFormat', 'uniform'));
numVars = setdiff(numVars, groupVars);

if isempty(groupVars)
    error('至少需要一个分组变量。');
end

[G, groupTbl] = findgroups(tbl(:, groupVars));
summaryTbl = groupTbl;
for i = 1:numel(numVars)
    x = tbl.(numVars{i});
    meanVal = splitapply(@mean, x, G);
    varVal = splitapply(@(z) sampleVarSafe(z), x, G);
    summaryTbl.([numVars{i}, '_mean']) = meanVal;
    summaryTbl.([numVars{i}, '_var']) = varVal;
end
end

function v = sampleVarSafe(z)
if numel(z) <= 1
    v = 0;
else
    v = var(z, 0);
end
end

% ==========================================================
%                     字段名安全转换
% ==========================================================
function name = safeFieldName(nameZh)
name = nameZh;
name = strrep(name, '白色型', 'white');
name = strrep(name, '绿色型', 'green');
name = strrep(name, '黑色型', 'black');
name = strrep(name, '黄色型', 'yellow');
name = strrep(name, '橙色型', 'orange');
end

% ==========================================================
%                      灵敏度分析绘图
% ==========================================================
function plotSensitivity(sensTbl, filename)
fig = figure('Name', 'sensitivity', 'Color', 'w', 'Position', [180 180 760 420]);
hold on;
params = unique(sensTbl.parameter, 'stable');
plotColors = [0.1 0.45 0.85; 0.85 0.35 0.1; 0.2 0.65 0.3];
for i = 1:numel(params)
    idx = strcmp(sensTbl.parameter, params{i});
    subTbl = sensTbl(idx, :);
    [xSorted, order] = sort(subTbl.value);
    ySorted = subTbl.dominant_fraction(order);
    plot(xSorted, ySorted, '-o', 'LineWidth', 1.8, 'MarkerSize', 6, 'Color', plotColors(i,:));
end
hold off;
grid on;
xlabel('参数取值');
ylabel('最终优势菌种面积占比');
legend({'growScale','consumeScale','lambdaReplace'}, 'Location', 'best');
title('灵敏度分析图');
saveFigureSafe(fig, filename);
close(fig);
end
