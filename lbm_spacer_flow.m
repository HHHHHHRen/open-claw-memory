%% ========================================================================
% LBM-D2Q9 for RO/NF Spacer-Filled Channel Flow
% 反渗透隔网流道流动模拟 - 格子玻尔兹曼方法
% 
% 物理模型：二维通道内有圆柱形隔网丝
% 边界条件：周期性进口/出口，无滑移上下壁面，反弹边界圆柱
% ========================================================================

clear; clc; close all;

%% 1. 参数设置
% ------------------------------------------------------------------------
% 格子参数
Nx = 400;           % x方向格子数（流向）
Ny = 100;           % y方向格子数（横向）

% 物理参数（无量纲化）
Re = 50;            % 雷诺数（基于丝径）
D_f = 10;           % 丝径（格子单位）
U_max = 0.1;        % 最大速度（格子单位，需<0.3保证稳定性）

% 计算松弛时间tau（与粘度相关）
nu = U_max * D_f / Re;      % 运动粘度
omega = 1 / (3*nu + 0.5);   % 松弛频率 omega = 1/tau

% 迭代参数
maxIter = 50000;    % 最大迭代步
tol = 1e-6;         % 收敛判据
plotInterval = 500; % 绘图间隔

% 隔网几何参数
numFilaments = 3;               % 隔网丝数量
filamentPositions = [Nx/4, Nx/2, 3*Nx/4];  % 丝的位置（x坐标）
filamentY = Ny/2 * ones(1, numFilaments);  % 丝的位置（y坐标，中心）

fprintf('=== RO Spacer LBM Simulation ===\n');
fprintf('Grid: %d x %d\n', Nx, Ny);
fprintf('Re = %.1f, tau = %.4f\n', Re, 1/omega);
fprintf('Omega (relaxation) = %.4f\n\n', omega);

%% 2. D2Q9模型权重与速度方向
% ------------------------------------------------------------------------
cx = [0, 1, 0, -1, 0, 1, -1, -1, 1];   % x方向速度分量
cy = [0, 0, 1, 0, -1, 1, 1, -1, -1];   % y方向速度分量
w = [4/9, 1/9, 1/9, 1/9, 1/9, 1/36, 1/36, 1/36, 1/36];  % 权重

%% 3. 初始化
% ------------------------------------------------------------------------
% 分布函数初始化（平衡态）
f = zeros(Ny, Nx, 9);
ux = zeros(Ny, Nx);     % x方向速度
uy = zeros(Ny, Nx);     % y方向速度
rho = ones(Ny, Nx);     % 密度

for i = 1:9
    f(:,:,i) = w(i);
end

% 生成障碍物掩码（固体格子）
obstacle = false(Ny, Nx);
for n = 1:numFilaments
    for j = 1:Ny
        for i = 1:Nx
            dist = sqrt((i - filamentPositions(n))^2 + (j - filamentY(n))^2);
            if dist <= D_f/2
                obstacle(j,i) = true;
            end
        end
    end
end

% 上下壁面也是固体
obstacle(1,:) = true;       % 下壁面
obstacle(Ny,:) = true;      % 上壁面

fluid = ~obstacle;          % 流体格子掩码

%% 4. 主迭代循环
% ------------------------------------------------------------------------
fprintf('Starting iteration...\n');

ux_old = ux;
residual_history = [];

for iter = 1:maxIter
    
    % ---- 4.1 计算宏观量 ----
    rho = sum(f, 3);
    ux = zeros(Ny, Nx);
    uy = zeros(Ny, Nx);
    for i = 1:9
        ux = ux + f(:,:,i) * cx(i);
        uy = uy + f(:,:,i) * cy(i);
    end
    ux = ux ./ rho;
    uy = uy ./ rho;
    
    % ---- 4.2 施加驱动力（压力梯度）----
    % 使用周期性边界+体积力模拟通道流
    Fx = 1e-5;  % 体积力（调这个控制速度）
    for i = 1:9
        ux = ux + tau * w(i) * cx(i) * Fx;
    end
    
    % ---- 4.3 碰撞步骤（BGK近似）----
    f_eq = zeros(Ny, Nx, 9);
    for i = 1:9
        cu = cx(i)*ux + cy(i)*uy;
        f_eq(:,:,i) = w(i) * rho .* (1 + 3*cu + 4.5*cu.^2 - 1.5*(ux.^2 + uy.^2));
    end
    
    f_star = f + omega * (f_eq - f);  % 碰撞后分布函数
    
    % ---- 4.4 迁移步骤 ----
    f_streamed = zeros(Ny, Nx, 9);
    for i = 1:9
        % 循环移位实现迁移
        f_streamed(:,:,i) = circshift(f_star(:,:,i), [cy(i), cx(i)]);
    end
    
    % ---- 4.5 周期性边界处理 ----
    % 进出口周期性已在circshift中实现
    % 需要调整：进出口密度梯度修正（力驱动流）
    
    % ---- 4.6 反弹边界（固体表面）----
    % 标准反弹边界条件
    f = f_streamed;
    
    % 上下壁面反弹
    for i = 1:Nx
        if ~obstacle(2,i)  % 下壁面附近的流体格子
            f(2,i,[3,6,7]) = f_streamed(2,i,[5,8,9]);  % 反弹
        end
        if ~obstacle(Ny-1,i)  % 上壁面附近的流体格子
            f(Ny-1,i,[5,8,9]) = f_streamed(Ny-1,i,[3,6,7]);
        end
    end
    
    % 圆柱表面反弹
    for j = 2:Ny-1
        for i = 1:Nx
            if obstacle(j,i)
                % 找到相邻流体格子
                for dir = 2:9
                    ni = i + cx(dir);
                    nj = j + cy(dir);
                    if ni >= 1 && ni <= Nx && nj >= 1 && nj <= Ny && ~obstacle(nj,ni)
                        % 反弹：f_opposite进入相邻流体格子
                        opp = [1, 4, 5, 2, 3, 8, 9, 6, 7];  % 反向索引
                        f(nj, ni, opp(dir)) = f_streamed(j, i, dir);
                    end
                end
            end
        end
    end
    
    % ---- 4.7 收敛检查 ----
    if mod(iter, 100) == 0
        residual = max(max(abs(ux - ux_old))) / max(max(abs(ux)) + eps);
        residual_history(end+1) = residual;
        
        if mod(iter, 1000) == 0
            fprintf('Iter %d: Residual = %.6f, Umax = %.4f\n', iter, residual, max(max(abs(ux))));
        end
        
        if residual < tol
            fprintf('Converged at iteration %d\n', iter);
            break;
        end
    end
    ux_old = ux;
    
    % ---- 4.8 实时可视化 ----
    if mod(iter, plotInterval) == 0
        plotResults(ux, uy, rho, obstacle, iter);
    end
end

%% 5. 后处理与结果输出
% ------------------------------------------------------------------------
fprintf('\n=== Simulation Complete ===\n');

% 计算压降
P = rho / 3;  % 压力（格子单位）
deltaP = mean(P(:,1)) - mean(P(:,end));
fprintf('Pressure drop: %.6f (lattice units)\n', deltaP);

% 计算阻力系数（丝的平均）
U_avg = mean(ux(fluid));
F_drag = sum(sum(abs(ux))) * Fx;  % 简化估算
cd_estimate = 2 * F_drag / (rho(1,1) * U_avg^2 * D_f);
fprintf('Estimated Cd: %.4f\n', cd_estimate);

% 最终可视化
plotResults(ux, uy, rho, obstacle, iter);

% 速度场切片
figure('Position', [100 100 1200 400]);
subplot(1,2,1);
plot(ux(:,Nx/2), 1:Ny, 'b-', 'LineWidth', 2);
hold on;
xlabel('u_x'); ylabel('y');
title(sprintf('Velocity Profile at x=%d', Nx/2));
grid on;

subplot(1,2,2);
semilogy(residual_history, 'r-', 'LineWidth', 1.5);
xlabel('Iteration (x100)'); ylabel('Residual');
title('Convergence History');
grid on;

%% ========================================================================
% 子函数：结果可视化
% ========================================================================
function plotResults(ux, uy, rho, obstacle, iter)
    [Ny, Nx] = size(ux);
    
    % 速度大小
    U_mag = sqrt(ux.^2 + uy.^2);
    U_mag(obstacle) = NaN;  % 固体区域不显示
    
    figure(1);
    clf;
    
    % 速度云图
    subplot(2,1,1);
    imagesc(U_mag);
    set(gca, 'YDir', 'normal');
    colormap(jet);
    colorbar;
    caxis([0, max(U_mag(~isnan(U_mag)))*0.8]);
    title(sprintf('Velocity Magnitude - Iter %d', iter));
    xlabel('x'); ylabel('y');
    hold on;
    [obs_y, obs_x] = find(obstacle);
    plot(obs_x, obs_y, 'ks', 'MarkerSize', 2, 'MarkerFaceColor', 'k');
    
    % 流线图（稀疏采样）
    subplot(2,1,2);
    skip = 5;
    [X, Y] = meshgrid(1:Nx, 1:Ny);
    ux_plot = ux; uy_plot = uy;
    ux_plot(obstacle) = 0; uy_plot(obstacle) = 0;
    quiver(X(1:skip:end,1:skip:end), Y(1:skip:end,1:skip:end), ...
           ux_plot(1:skip:end,1:skip:end), uy_plot(1:skip:end,1:skip:end), 2);
    hold on;
    plot(obs_x, obs_y, 'ko', 'MarkerSize', 4, 'MarkerFaceColor', 'k');
    title('Velocity Vector Field');
    xlabel('x'); ylabel('y');
    axis([1 Nx 1 Ny]);
    
    drawnow;
end
