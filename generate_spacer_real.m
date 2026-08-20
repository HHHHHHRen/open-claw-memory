%% RO 菱形编织隔网（真正正确版）
clear; clc; close all;

%% 参数
pitch = 4.0;           % mm，节距（相邻平行纤维中心距离）
d_fiber = 1.0;         % mm，纤维直径
r_fiber = 0.5;         % mm

dx = 0.05;             % mm，分辨率

% 菱形几何关系：
% 纤维间距 = pitch（沿垂直于纤维方向）
% 菱形对角线 = pitch * sqrt(2)（沿X和Y方向）

diamond_diag = pitch * sqrt(2);  % ≈ 5.657 mm

% 3个cross
Lx = 3 * diamond_diag;  % ≈ 16.97 mm
Ly = diamond_diag;      % ≈ 5.657 mm  
Lz = 1.2;               % mm

NX = round(Lx / dx);    % 339
NY = round(Ly / dx);    % 113
NZ = round(Lz / dx);    % 24

fprintf('=== 菱形编织隔网 ===\n');
fprintf('节距 pitch: %.2f mm\n', pitch);
fprintf('菱形对角线: %.3f mm\n', diamond_diag);
fprintf('网格: %d×%d×%d\n', NX, NY, NZ);

%% 网格坐标
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
[X, Y] = meshgrid(x, y);

%% 关键：纤维中心线的正确位置
% 对于45°纤维，相邻平行线的距离 = pitch
% 直线方程：x - y = const 或 x + y = const
% const的间隔 = pitch * sqrt(2)（因为斜率是1）

layer1_2D = false(NY, NX);  % +45°: x - y = c
layer2_2D = false(NY, NX);  % -45°: x + y = c

% +45° 纤维（从左下到右上）
% const 的取值：从 -Ly 到 Lx，间隔 = pitch * sqrt(2) = diamond_diag
for c = -Ly:diamond_diag:(Lx+Ly)
    dist = abs(X - Y - c) / sqrt(2);  % 到直线 x-y=c 的距离
    layer1_2D = layer1_2D | (dist < r_fiber);
end

% -45° 纤维（从左上到右下）
% 偏移半个周期，使交叉点在菱形中心
for c = 0:diamond_diag:(Lx+Ly)
    dist = abs(X + Y - c) / sqrt(2);  % 到直线 x+y=c 的距离
    layer2_2D = layer2_2D | (dist < r_fiber);
end

%% 合并两层（XY平面已经是完整菱形）
XY_pattern = layer1_2D | layer2_2D;

%% Z方向：厚度方向复制（隔网有厚度）
solid = false(NY, NX, NZ);

fiber_layers = round(d_fiber / dx);  % 纤维占几层格点

% 下层（靠近Z=0）：+45°
% 上层（靠近Z=Lz）：-45°
% 或者两层交错都可以

for iz = 1:NZ
    z_height = (iz-1) * dx;
    
    if z_height < d_fiber
        % 底部是+45°
        solid(:, :, iz) = layer1_2D;
    elseif z_height > (Lz - d_fiber)
        % 顶部是-45°
        solid(:, :, iz) = layer2_2D;
    else
        % 中间是流体通道
        solid(:, :, iz) = false(NY, NX);
    end
end

%% 统计
solid_count = sum(solid(:));
porosity = 1 - solid_count / (NX*NY*NZ);
fprintf('\n孔隙率: %.2f%%\n', porosity*100);

%% 可视化
figure('Name', '菱形编织隔网', 'Position', [50 50 1200 400]);

[ys, xs, zs] = ind2sub([NY, NX, NZ], find(solid));

% XY俯视图
subplot(1,3,1);
scatter(xs, ys, 3, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y');
title('XY俯视图');
grid on;
xlim([0 NX-1]); ylim([0 NY-1]);

% 画3个cross的分界线
hold on;
for i = 1:2
    xv = i * diamond_diag / dx;
    plot([xv xv], [0 NY-1], 'r--', 'LineWidth', 1.5);
end
hold off;

% XZ
subplot(1,3,2);
scatter(xs, zs, 2, 'r', 'filled');
axis equal tight;
xlabel('X'); ylabel('Z');
title('XZ侧视图');
grid on;

% 3D
subplot(1,3,3);
scatter3(xs, ys, zs, 2, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y'); zlabel('Z');
title('3D');
view(45,30); grid on;

%% 导出
fid = fopen('geometry_check.dat', 'w');
fprintf(fid, 'X Y Z\n');
for i = 1:length(xs)
    fprintf(fid, '%d %d %d\n', xs(i)-1, ys(i)-1, zs(i)-1);
end
fclose(fid);
