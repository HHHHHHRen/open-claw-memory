%% RO 菱形编织隔网（3个完整Cross版）
clear; clc; close all;

%% 参数设置（关键：Lx刚好容纳3个完整cross）
pitch = 4.0;           % mm，节距
d_fiber = 1.0;         % mm，纤维直径
r_fiber = 0.5;         % mm，纤维半径
angle = 45;            % 度

% 一个cross的X方向跨度（菱形对角线）
cross_width = pitch * sqrt(2);  % ≈ 5.657 mm

% 计算域：刚好3个cross
num_cross = 3;
Lx = num_cross * cross_width;   % ≈ 16.97 mm
Ly = cross_width;               % Y方向1个cross宽度
Lz = 1.2;                       % mm，流道高度

dx = 0.05;                      % mm，分辨率

NX = round(Lx / dx);            % ≈ 339
NY = round(Ly / dx);            % ≈ 113
NZ = round(Lz / dx);            % 24

fprintf('=== 3个完整Cross隔网 ===\n');
fprintf('1个cross宽度: %.3f mm\n', cross_width);
fprintf('3个cross总宽: %.3f mm (Lx)\n', Lx);
fprintf('网格: %d×%d×%d = %.2f 万\n', NX, NY, NZ, NX*NY*NZ/10000);

%% 生成网格坐标
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
z = (0:NZ-1) * dx;

[X, Y] = meshgrid(x, y);

%% 下层纤维：+45°（从左下到右上）
% 平行线：y = x + c
% 穿过3个cross的完整菱形
layer1_2D = false(NY, NX);

% 纤维从左侧边界开始，到右侧边界结束，间距 = cross_width
for c = -Ly:cross_width:Ly+Lx
    dist = abs(X - Y + c) / sqrt(2);
    layer1_2D = layer1_2D | (dist < r_fiber);
end

%% 上层纤维：-45°（从左上到右下）
layer2_2D = false(NY, NX);

% 从第一个cross开始，间距 = cross_width
first_cross_center = cross_width / 2;
for c = first_cross_center:cross_width:(Lx+Ly)
    dist = abs(X + Y - c) / sqrt(2);
    layer2_2D = layer2_2D | (dist < r_fiber);
end

%% Z方向：下层在底部，上层在顶部
solid = false(NY, NX, NZ);

fiber_thickness = round(d_fiber / dx);  % 纤维占的格点数

for iz = 1:NZ
    if iz <= fiber_thickness
        solid(:, :, iz) = layer1_2D;  % 下层：+45°
    elseif iz > (NZ - fiber_thickness)
        solid(:, :, iz) = layer2_2D;  % 上层：-45°
    end
end

%% 统计
solid_count = sum(solid(:));
total_count = NX * NY * NZ;
porosity = 1 - solid_count / total_count;

fprintf('\n固体格点: %d\n', solid_count);
fprintf('孔隙率: %.4f (%.2f%%)\n', porosity, porosity*100);

%% 可视化
figure('Name', '3个完整Cross隔网', 'Position', [20 20 1600 400]);

[ys, xs, zs] = ind2sub([NY, NX, NZ], find(solid));

% XY俯视图（3个完整菱形）
subplot(1,3,1);
scatter(xs, ys, 2, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y');
title('XY俯视图（3个完整菱形）');
grid on; box on;
xlim([0 NX-1]); ylim([0 NY-1]);

% 标记3个cross的边界
hold on;
for i = 1:2
    xline = i * cross_width / dx;
    plot([xline xline], [0 NY-1], 'r--', 'LineWidth', 2);
end
hold off;

% XZ侧视图
subplot(1,3,2);
scatter(xs, zs, 2, 'r', 'filled');
axis equal tight;
xlabel('X'); ylabel('Z');
title('XZ侧视图');
grid on;

% 3D视图
subplot(1,3,3);
scatter3(xs, ys, zs, 3, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y'); zlabel('Z');
title('3D视图');
view(45,30); grid on;

%% 导出
fid = fopen('geometry_check.dat', 'w');
fprintf(fid, 'X Y Z\n');
for i = 1:length(xs)
    fprintf(fid, '%d %d %d\n', xs(i)-1, ys(i)-1, zs(i)-1);
end
fclose(fid);
fprintf('\n已保存: geometry_check.dat\n');
