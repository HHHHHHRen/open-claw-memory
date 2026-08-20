%% ========================================================================
% LBM-D3Q19 for 3D RO/NF Spacer-Filled Channel Flow
% 反渗透隔网流道三维流动模拟 - 格子玻尔兹曼方法
%
% 物理模型：三维通道内有圆柱形隔网丝（可多层交错）
% 边界条件：周期性进口/出口，无滑移上下壁面，反弹边界圆柱
% ========================================================================

clear; clc; close all;

tic;

%% 1. 参数设置
% ------------------------------------------------------------------------
% 格子参数
Nx = 200;           % x方向格子数（流向）
Ny = 50;            % y方向格子数（横向，通道宽度）
Nz = 30;            % z方向格子数（高度，通道高度）

% 物理参数（无量纲化）
Re = 100;           % 雷诺数（基于丝径）
D_f = 8;            % 丝径（格子单位）
H_channel = Nz - 2; % 有效通道高度

% 计算松弛时间tau
nu = Re / D_f;      % 运动粘度（这里用不同的无量纲化，参考Schreckenberg&Richter）
tau = 3 * nu + 0.5; % 松弛时间
omega = 1 / tau;    % 松弛频率

fprintf('=== 3D RO Spacer LBM (D3Q19) ===\n');
fprintf('Grid: %d x %d x %d = %d cells\n', Nx, Ny, Nz, Nx*Ny*Nz);
fprintf('Memory required: ~%.1f MB\n', Nx*Ny*Nz*19*8/1e6);
fprintf('Re = %d, tau = %.4f, omega = %.4f\n\n', Re, tau, omega);

% 迭代参数
maxIter = 20000;    % 最大迭代步
tol = 1e-5;         % 收敛判据
plotInterval = 1000;% 绘图间隔

%% 2. D3Q19模型定义
% ------------------------------------------------------------------------
% 19个速度方向 [cxi, cyi, czi]
cx = [0, 1,-1, 0, 0, 0, 0, 1,-1, 1,-1, 1,-1, 1,-1, 0, 0, 0, 0];
cy = [0, 0, 0, 1,-1, 0, 0, 1, 1,-1,-1, 0, 0, 0, 0, 1,-1, 1,-1];
cz = [0, 0, 0, 0, 0, 1,-1, 0, 0, 0, 0, 1, 1,-1,-1, 1, 1,-1,-1];

% 权重
w = zeros(1, 19);
w(1) = 1/3;                    % (0,0,0)
w(2:7) = 1/18;                 % 轴向6个方向
w(8:19) = 1/36;                % 面内对角12个方向

% 反向索引（用于反弹边界）
opp = [1, 3, 2, 5, 4, 7, 6, 10, 9, 8, 11, 14, 13, 12, 15, 18, 17, 16, 19];

%% 3. 初始化
% ------------------------------------------------------------------------
f = zeros(Nz, Ny, Nx, 19);     % 分布函数 f(z,y,x,dir)
ux = zeros(Nz, Ny, Nx);        % x方向速度
uy = zeros(Nz, Ny, Nx);        % y方向速度  
uz = zeros(Nz, Ny, Nx);        % z方向速度
rho = ones(Nz, Ny, Nx);        % 密度

% 初始化平衡态
for i = 1:19
    f(:,:,:,i) = w(i);
end

%% 4. 生成隔网几何（多层交错圆柱）
% ------------------------------------------------------------------------
obstacle = false(Nz, Ny, Nx);  % 固体掩码

% 隔网参数
layerConfig = [                  % 每层配置: [z位置, y偏移, x起始, 间距]
    8,  0,  20, 40;              % 下层
    15, 20, 40, 40;              % 中层（交错）
    22, 0,  20, 40;              % 上层
];
numLayers = size(layerConfig, 1);

for layer = 1:numLayers
    z_center = layerConfig(layer, 1);
    y_offset = layerConfig(layer, 2);
    x_start = layerConfig(layer, 3);
    x_spacing = layerConfig(layer, 4);
    
    % 沿x方向放置多根丝
    for x_pos = x_start:x_spacing:Nx-x_start
        for k = 1:Nz
            for j = 1:Ny
                for i = 1:Nx
                    % 圆柱沿x轴方向
                    dist = sqrt((j - (Ny/2 + y_offset))^2 + (k - z_center)^2);
                    if dist <= D_f/2
                        obstacle(k, j, i) = true;
                    end
                end
            end
        end
    end
end

% 上下壁面（膜表面）
obstacle(1, :, :) = true;       % 下壁面
obstacle(Nz, :, :) = true;      % 上壁面

fluid = ~obstacle;              % 流体格子
numFluid = sum(fluid(:));
fprintf('Fluid cells: %d (%.1f%%)\n', numFluid, 100*numFluid/(Nx*Ny*Nz));

%% 5. 主迭代循环
% ------------------------------------------------------------------------
fprintf('\nStarting LBM iteration...\n');
ux_old = ux;
residual_history = [];

% 体积力驱动（模拟压力梯度）
Fx = 1e-6;

for iter = 1:maxIter
    
    % ---- 5.1 计算宏观量 ----
    rho = sum(f, 4);
    ux = zeros(Nz, Ny, Nx);
    uy = zeros(Nz, Ny, Nx);
    uz = zeros(Nz, Ny, Nx);
    
    for i = 1:19
        ux = ux + f(:,:,:,i) * cx(i);
        uy = uy + f(:,:,:,i) * cy(i);
        uz = uz + f(:,:,:,i) * cz(i);
    end
    ux = ux ./ rho;
    uy = uy ./ rho;
    uz = uz ./ rho;
    
    % 施加体积力
    ux = ux + tau * Fx;
    
    % ---- 5.2 碰撞步骤（BGK）----
    f_eq = zeros(Nz, Ny, Nx, 19);
    for i = 1:19
        cu = cx(i)*ux + cy(i)*uy + cz(i)*uz;
        uu = ux.^2 + uy.^2 + uz.^2;
        f_eq(:,:,:,i) = w(i) * rho .* (1 + 3*cu + 4.5*cu.^2 - 1.5*uu);
    end
    
    f_star = f - omega * (f - f_eq);  % 碰撞后分布函数
    
    % ---- 5.3 迁移步骤 ----
    f_streamed = zeros(Nz, Ny, Nx, 19);
    for i = 1:19
        f_streamed(:,:,:,i) = circshift(f_star(:,:,:,i), [cz(i), cy(i), cx(i)]);
    end
    
    % ---- 5.4 边界处理 ----
    f = f_streamed;
    
    % 上下壁面反弹（z方向）
    for j = 1:Ny
        for i = 1:Nx
            % 下壁面 (z=1是固体，z=2是流体)
            if ~obstacle(2, j, i)
                f(2, j, i, [6,12,13]) = f_streamed(2, j, i, [7,15,14]);  % z+方向反弹
            end
            % 上壁面
            if ~obstacle(Nz-1, j, i)
                f(Nz-1, j, i, [7,14,15]) = f_streamed(Nz-1, j, i, [6,13,12]);
            end
        end
    end
    
    % 圆柱表面反弹
    [obs_z, obs_y, obs_x] = ind2sub([Nz, Ny, Nx], find(obstacle));
    numObs = length(obs_z);
    
    for idx = 1:numObs
        k = obs_z(idx);
        j = obs_y(idx);
        i = obs_x(idx);
        
        % 检查6个直接邻居（轴向）
        for dir = 2:7
            ni = i + cx(dir);
            nj = j + cy(dir);
            nk = k + cz(dir);
            
            if ni >= 1 && ni <= Nx && nj >= 1 && nj <= Ny && nk >= 1 && nk <= Nz
                if ~obstacle(nk, nj, ni)
                    % 反弹到相邻流体格子
                    f(nk, nj, ni, opp(dir)) = f_streamed(k, j, i, dir);
                end
            end
        end
        
        % 检查12个对角邻居
        for dir = 8:19
            ni = i + cx(dir);
            nj = j + cy(dir);
            nk = k + cz(dir);
            
            if ni >= 1 && ni <= Nx && nj >= 1 && nj <= Ny && nk >= 1 && nk <= Nz
                if ~obstacle(nk, nj, ni)
                    f(nk, nj, ni, opp(dir)) = f_streamed(k, j, i, dir);
                end
            end
        end
    end
    
    % ---- 5.5 收敛检查 ----
    if mod(iter, 500) == 0
        residual = max(max(max(abs(ux - ux_old)))) / (max(max(max(abs(ux)))) + eps);
        residual_history(end+1) = residual;
        
        if mod(iter, 2000) == 0
            u_max = max(max(max(abs(ux(fluid)))));
            fprintf('Iter %5d: Residual = %.6f, Umax = %.6f\n', iter, residual, u_max);
        end
        
        if residual < tol && iter > 1000
            fprintf('Converged at iteration %d\n', iter);
            break;
        end
    end
    ux_old = ux;
    
    % ---- 5.6 可视化 ----
    if mod(iter, plotInterval) == 0
        plotResults3D(ux, uy, uz, rho, obstacle, iter, Nx, Ny, Nz);
    end
end

toc;

%% 6. 后处理
% ------------------------------------------------------------------------
fprintf('\n=== Simulation Complete ===\n');

% 计算统计量
U_mag = sqrt(ux.^2 + uy.^2 + uz.^2);
U_mean = mean(U_mag(fluid));
U_max = max(U_mag(fluid));

fprintf('Mean velocity: %.6f\n', U_mean);
fprintf('Max velocity: %.6f\n', U_max);

% 压降估算（基于体积力平衡）
deltaP = Fx * Nx;
fprintf('Pressure drop: %.6f (lattice units)\n', deltaP);

% 摩擦系数
Re_eff = U_mean * H_channel / (tau - 0.5) / 3;
fprintf('Effective Re: %.2f\n', Re_eff);

% 最终可视化
plotResults3D(ux, uy, uz, rho, obstacle, iter, Nx, Ny, Nz);

%% 7. 导出数据（可选）
% save('spacer_flow_results.mat', 'ux', 'uy', 'uz', 'rho', 'obstacle', '-v7.3');

%% ========================================================================
% 子函数：3D结果可视化
%% ========================================================================
function plotResults3D(ux, uy, uz, rho, obstacle, iter, Nx, Ny, Nz)
    U_mag = sqrt(ux.^2 + uy.^2 + uz.^2);
    U_mag(obstacle) = NaN;
    
    % 取几个切片
    x_mid = round(Nx/2);
    y_mid = round(Ny/2);
    z_mid = round(Nz/2);
    
    figure(1);
    clf;
    
    % X-Y平面切片（水平截面）
    subplot(2,2,1);
    imagesc(squeeze(U_mag(z_mid, :, :)));
    set(gca, 'YDir', 'normal');
    colormap(jet);
    colorbar;
    title(sprintf('U-mag at z=%d (Iter %d)', z_mid, iter));
    xlabel('x'); ylabel('y');
    caxis([0, nanmax(U_mag(:))*0.9]);
    
    % X-Z平面切片（垂直截面，沿流向）
    subplot(2,2,2);
    imagesc(squeeze(U_mag(:, y_mid, :)));
    set(gca, 'YDir', 'normal');
    colormap(jet);
    colorbar;
    title(sprintf('U-mag at y=%d', y_mid));
    xlabel('x'); ylabel('z');
    caxis([0, nanmax(U_mag(:))*0.9]);
    
    % Y-Z平面切片（垂直截面，横向）
    subplot(2,2,3);
    imagesc(squeeze(U_mag(:, :, x_mid)));
    set(gca, 'YDir', 'normal');
    colormap(jet);
    colorbar;
    title(sprintf('U-mag at x=%d', x_mid));
    xlabel('y'); ylabel('z');
    caxis([0, nanmax(U_mag(:))*0.9]);
    
    % 速度剖面
    subplot(2,2,4);
    ux_profile = squeeze(mean(mean(ux(:, :, :), 2), 3));
    plot(1:Nz, ux_profile, 'b-', 'LineWidth', 2);
    xlabel('z'); ylabel('Mean u_x');
    title('Mean Velocity Profile');
    grid on;
    
    drawnow;
end
