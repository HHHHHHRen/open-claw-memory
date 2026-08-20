%% RO 菱形编织隔网几何生成（正确版）
clear; clc; close all;

%% 参数设置
Lx = 24.0;      % mm，流道长度
Ly = 5.66;      % mm，流道宽度（1个cross的宽度 = pitch*sqrt(2)）  
Lz = 1.2;       % mm，流道高度

d_fiber = 1.0;  % mm，纤维直径
r_fiber = 0.5;  % mm，纤维半径

pitch = 4.0;    % mm，节距（相邻平行纤维中心距离）
angle = 45;     % 度

dx = 0.05;      % mm，网格分辨率

NX = round(Lx / dx);  % 480
NY = round(Ly / dx);  % 113
NZ = round(Lz / dx);  % 24

% 菱形编织的关键参数
% 菱形对角线长度 = pitch * sqrt(2)
diamond_diag = pitch * sqrt(2);  % ≈ 5.657 mm
% 这正是 Ly 的长度，所以Y方向刚好是1个菱形

fprintf('网格: %d×%d×%d = %.2f 万\n', NX, NY, NZ, NX*NY*NZ/10000);
fprintf('菱形对角线: %.3f mm (Ly=%.2f mm)\n', diamond_diag, Ly);
fprintf('X方向可排 %d 个完整菱形周期\n', floor(Lx / diamond_diag));

%% 生成网格坐标
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
z = (0:NZ-1) * dx;

[X, Y] = meshgrid(x, y);

%% 下层纤维：+45° 方向（从左下到右上）
% 平行线族：y = x + c，间距为 diamond_diag
layer1_2D = false(NY, NX);

% 纤维中心线位置（周期性）
for c = -Lx:diamond_diag:(Lx+Ly)
    % 直线 y = x + c，即 x - y + c = 0
    % 距离 = |x - y + c| / sqrt(2)
    dist = abs(X - Y + c) / sqrt(2);
    layer1_2D = layer1_2D | (dist < r_fiber);
end

%% 上层纤维：-45° 方向（从左上到右下）
% 平行线族：y = -x + c，间距为 diamond_diag
layer2_2D = false(NY, NX);

for c = 0:diamond_diag:(Lx+Ly)
    % 直线 y = -x + c，即 x + y - c = 0
    % 距离 = |x + y - c| / sqrt(2)
    dist = abs(X + Y - c) / sqrt(2);
    layer2_2D = layer2_2D | (dist < r_fiber);
end

%% 沿 Z 方向构建 3D 结构（上下层交错）
solid = false(NY, NX, NZ);

% 下层在底部，上层在顶部，中间是流道
z_layer_thickness = d_fiber;  % 每层纤维占一个直径厚度

for iz = 1:NZ
    z_phys = z(iz);
    
    if z_phys <= z_layer_thickness
        solid(:, :, iz) = layer1_2D;  % 下层：+45°
    elseif z_phys >= (Lz - z_layer_thickness)
        solid(:, :, iz) = layer2_2D;  % 上层：-45°
    end
end

%% 统计
solid_count = sum(solid(:));
total_count = NX * NY * NZ;
porosity = 1 - solid_count / total_count;

fprintf('\n固体格点: %d\n', solid_count);
fprintf('总格点: %d\n', total_count);
fprintf('孔隙率: %.4f (%.2f%%)\n', porosity, porosity*100);

if porosity >= 0.75 && porosity <= 0.95
    fprintf('✓ 孔隙率正常\n');
else
    fprintf('注意：孔隙率可能需要调整\n');
end

%% 可视化
figure('Name', '菱形编织隔网（正确版）', 'Position', [20 20 1600 450]);

[ys, xs, zs] = ind2sub([NY, NX, NZ], find(solid));

% 1. 3D整体
subplot(1,4,1);
scatter3(xs, ys, zs, 3, zs, 'filled');
axis equal tight;
xlabel('X'); ylabel('Y'); zlabel('Z');
title('3D整体');
colorbar; view(45,30); grid on;

% 2. XY俯视图（应该看到清晰的菱形网格）
subplot(1,4,2);
scatter(xs, ys, 1, 'b', 'filled');
axis equal tight;
xlabel('X (格点)'); ylabel('Y (格点)');
title('XY俯视图（菱形编织）');
grid on; box on;
xlim([1 NX]); ylim([1 NY]);

% 画菱形辅助验证
hold on;
cx = NX/2; cy = NY/2;
plot([cx-50 cx+50], [cy-50 cy+50], 'r--', 'LineWidth', 0.5);
plot([cx-50 cx+50], [cy+50 cy-50], 'r--', 'LineWidth', 0.5);
hold off;

% 3. XZ侧视图（两层）
subplot(1,4,3);
scatter(xs, zs, 2, 'r', 'filled');
axis equal tight;
xlabel('X'); ylabel('Z');
title('XZ侧视图（两层结构）');
grid on;

% 4. YZ侧视图
subplot(1,4,4);
scatter(ys, zs, 2, 'g', 'filled');
axis equal tight;
xlabel('Y'); ylabel('Z');
title('YZ侧视图');
grid on;

%% 导出
fid = fopen('geometry_check.dat', 'w');
fprintf(fid, 'X Y Z\n');
for i = 1:length(xs)
    fprintf(fid, '%d %d %d\n', xs(i)-1, ys(i)-1, zs(i)-1);
end
fclose(fid);
fprintf('\n已保存: geometry_check.dat\n');
