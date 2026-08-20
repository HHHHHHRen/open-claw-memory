%% RO 菱形编织隔网（孔隙率调整版）
clear; clc; close all;

%% 参数
pitch = 4.0;           % mm，节距
d_fiber = 1.0;         % mm，纤维直径
r_fiber = d_fiber / 2; % 0.5 mm

dx = 0.05;             % mm，分辨率

% 菱形几何
diamond_diag = pitch * sqrt(2);  % ≈ 5.657 mm

% 计算域：3个cross
Lx = 3 * diamond_diag;  % ≈ 16.97 mm
Ly = diamond_diag;      % ≈ 5.657 mm  
Lz = 1.2;               % mm，流道高度

NX = round(Lx / dx);    % 339
NY = round(Ly / dx);    % 113
NZ = round(Lz / dx);    % 24

fprintf('=== 菱形编织隔网 ===\n');
fprintf('纤维直径: %.2f mm\n', d_fiber);
fprintf('菱形对角线: %.3f mm\n', diamond_diag);
fprintf('网格: %d×%d×%d\n', NX, NY, NZ);

%% 网格坐标
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
z = (0:NZ-1) * dx;
[X, Y] = meshgrid(x, y);

%% XY平面：菱形编织
layer1_2D = false(NY, NX);  % +45°
layer2_2D = false(NY, NX);  % -45°

% +45° 纤维
for c = -Ly:diamond_diag:(Lx+Ly)
    dist = abs(X - Y - c) / sqrt(2);
    layer1_2D = layer1_2D | (dist < r_fiber);
end

% -45° 纤维
for c = 0:diamond_diag:(Lx+Ly)
    dist = abs(X + Y - c) / sqrt(2);
    layer2_2D = layer2_2D | (dist < r_fiber);
end

%% Z方向关键修正：交错单层结构
% 真实隔网：上下两层纤维在交叉点处交错，不是简单叠加
% Z厚度 ≈ 1.5 * d_fiber（一层厚度 + 交叉点凸起）

solid = false(NY, NX, NZ);

% 计算每层的固体：下层+45°和上层-45°的并集
XY_solid = layer1_2D | layer2_2D;

% 在Z方向，隔网占据中间区域（模拟编织厚度）
z_center = Lz / 2;
net_thickness = 0.8;  % mm，隔网实际厚度（比直径略小，因为交叉）

for iz = 1:NZ
    z_phys = z(iz);
    
    % 隔网占据中间区域
    if abs(z_phys - z_center) < (net_thickness/2)
        solid(:, :, iz) = XY_solid;
    end
end

%% 统计
solid_count = sum(solid(:));
porosity = 1 - solid_count / (NX*NY*NZ);
fprintf('\n孔隙率: %.2f%%\n', porosity*100);

%% 可视化
figure('Name', '菱形编织隔网', 'Position', [50 50 1400 400]);

[ys, xs, zs] = ind2sub([NY, NX, NZ], find(solid));

% XY俯视图
subplot(1,3,1);
scatter(xs, ys, 3, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y');
title(sprintf('XY俯视图 (孔隙率%.1f%%)', porosity*100));
grid on;
xlim([0 NX-1]); ylim([0 NY-1]);

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

%% 如果孔隙率不对，给出建议
fprintf('\n=== 建议 ===\n');
if porosity < 0.80
    fprintf('孔隙率偏低，可调整：\n');
    fprintf('1. 减小 net_thickness（当前%.1fmm）\n', net_thickness);
    fprintf('2. 减小纤维直径 d_fiber\n');
    fprintf('3. 增大节距 pitch\n');
end
