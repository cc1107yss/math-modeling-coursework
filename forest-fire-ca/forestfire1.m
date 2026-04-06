%% 这是一个考虑了风速、风向、和地形坡度影响的洛杉矶着火模拟
% 没有赋值RGB,灰白色图层

%  一、初始化 
Z = peaks(200); % 基础地形矩阵，生成一个 200*200 的起伏曲面矩阵
Z(50:70,30:50) = Z(50:70,30:50)*0.3; % 取一个矩阵区域模拟峡谷（人为造一个）

states = zeros(size(Z)); % size(Z) 会返回 Z 的大小 zeros(size(Z)) 就会创建一个同样大小的全 0 矩阵
% 状态矩阵0:空地 1:植被 2:燃烧 3:建筑物 4:烧毁
flammability = zeros(size(Z)); % 易燃系数矩阵，初始全为0

wind_dir = [1, -1]; % 定义一个二维东北风向量
wind_speed = 0.7; % 0-1区间

% 灌木易燃区（洛杉矶特征）
flammability(Z > 0.5) = 0.9; % 山地灌木 地势较高区域被看作山地灌木区，更容易着火
flammability(Z <= 0.5) = 0.6; % 平缓区域
flammability(rand(size(Z))<0.05) = 0.2; % 人工绿化带 rand(size(Z)) 会生成一个 200*200 的随机矩阵
% 每个元素都在 0 到 1 之间。再判断 <0.05，就会随机选出大约 5% 的格子

buildings = randi([0 1],200,200); % 随机建筑分布 生成一个 200*200 的随机整数矩阵，元素只能是0或1（有建筑）
buildings(180:200,:)=rand(21,200)<0.9;%rand(m,n) 是生成一个 m行n列 的矩阵，
% 矩阵中每个元素都是 0 到 1 之间的随机数
%原错误代码buildings(180:200,:) = buildings(180:200,:).*0.3; % 选中buildings数组里第 180 到 200 行的全部元素 
% 模拟贫民区密集建筑 .*0.3：这是逐元素乘法 对选中的每一个元素单独乘以 0.3，而不是矩阵乘法
states(buildings==1) = 3;%把所有 buildings==1 的位置，在 states 里设成 3 

% 让未被建筑覆盖的区域随机分配植被
veg_density = 0.7; % 植被覆盖率
rand_veg = rand(size(Z)) < veg_density;%rand()生成一个0-1之间的随机数 每个位置随机决定是否种植被，大约有 70% 的位置会被选中
states(rand_veg & states == 0) = 1; % 在rand-veg为真 且states==0的位置把状态改成1
% 只在空地上种植被

% 让部分区域有更稠密的植被，比如山地和峡谷
states(Z > 0.5 & rand(size(Z)) < 0.8&states==0) = 1; % 高山地区80% 概率成为植被 应该只在空地上补植被

fire_dept = ones(size(Z))*0.8; % 建立一个全是 0.8 的矩阵，每个位置默认有 80% 的灭火成功概率
fire_dept(90:110,80:120) = 0.2; % 模拟消防预算削减区域
fire_dept(rand(size(Z))<0.1) = 0; % 随机让 10% 的位置消防能力为 0
figure;%打开一个新的图像窗口
colormap([0.8 0.8 0.8;   % 定义颜色映射表 空地 - 灰色
          0.1 0.7 0.1;   % 植被 - 绿色（调整为更亮的绿色）
          1   0.0 0;     % 燃烧 - 红色
          0.5 0.5 0.5;   % 建筑 - 深灰
          0.1 0.1 0.1]); % 烧毁 - 黑色

% 设置初始火点（模拟多起火点）
states(50,50) = 2;
states(180,30) = 2;
states(150,170) = 2;

%% 主循环
% 地形影响计算
    [gx, gy] = gradient(Z);%计算二维矩阵 Z 的梯度 计算地形 Z 在两个方向上的变化率
    slope_effect = sqrt(gx.^2 + gy.^2) * 0.15; % .^ 是逐元素平方
    % 平方根综合坡度 坡度加速燃烧
for t = 1:300%从1-300模拟时刻重复执行
    % 风场实时变化（圣安娜风增强）
    if mod(t,50)==0%mod(t,50) 表示 t 除以 50 的余数 每过 50 个时刻，调整一次风速
        wind_speed = min(wind_speed*1.2, 0.95);%模拟圣安娜风逐渐增强，但有上限
    end
    
    
    
    new_states = states;%复制当前状态 新旧状态分开
    [rows,cols] = size(states);
    
    for i = 2:rows-1
        for j = 2:cols-1%扫描内部每个格子避开边界
            if states(i,j) == 2 % 燃烧状态
                % 消防系统作用
                if rand() < fire_dept(i,j)%生成一个0-1的随机数 小于该位置灭火概率即成功
                    new_states(i,j) = 0; % 灭火成功
                 else
                    new_states(i,j) = 4; % 变为烧毁状态
                end
                
                % 传播火焰
                for dx = -1:1 %-1，0，1
                    for dy = -1:1
                        ni = i+dx;
                        nj = j+dy;%找到邻居坐标
                        % 风场影响计算
                        wind_effect = dot([dx,dy], wind_dir)*wind_speed;%dot点积 判断邻居方向和风向是否一致
                        %风越大影响越明显
                        
                        spread_prob = (0.3 + wind_effect + slope_effect(i,j)) * flammability(ni,nj);
                        %基础传播能力 风影响 坡度影响 邻居自己的易燃程度
                        spread_prob = max(0, min(1, spread_prob));%把传播概率限制在 [0,1] 范围内

if rand() < spread_prob
    if states(ni,nj)==1 || states(ni,nj)==3%邻居是植被或建筑物
        new_states(ni,nj) = 2;
    end
end
                    end
                end
                
            elseif (states(i,j) > 0 && states(i,j) < 2) || states(i,j) == 3 % 植被/建筑物
                % 基础设施隐患（随机自燃）
                if rand() < 0.0001*flammability(i,j) %自然概率小 越易燃自燃概率越大
                    new_states(i,j) = 2;
                end
            end
        end
    end
    
    states = new_states;%把新状态整体替换成当前状态
    
    % 可视化
    imagesc(states);%图像显示 仿真动画本质上是不断更新矩阵不断显示，每个数字一种颜色
    caxis([0 4]);%固定颜色范围在0-4
    title(sprintf('洛杉矶大火模拟 t=%d 风速%.2f',t,wind_speed));%整数 保留两位小数
    drawnow;%立即刷新图像窗口
    
    % 保存动画帧
    frame = getframe(gcf);%从当前图形窗口抓取一帧画面
    im{t} = frame2im(frame);%把抓到的帧转换成图像，并存在 im 这个 cell 数组里
end

% 保存为GIF
filename = 'la_fire_simulation.gif';
for idx = 1:length(im)%遍历前面保存的所有帧
    [A,map] = rgb2ind(im{idx},256);%GIF 保存前通常要先做格式转换
    if idx == 1
        imwrite(A,map,filename,'gif','LoopCount',Inf,'DelayTime',0.1);%无限循环播放 每帧间隔0.1秒
    else
        imwrite(A,map,filename,'gif','WriteMode','append','DelayTime',0.1);
    end
end
