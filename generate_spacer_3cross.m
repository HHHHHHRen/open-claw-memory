%% RO 菱形编织隔网几何生成（3个Cross并排版）
clear; clc; close all;

%% 参数设置
Lx = 24.0;      % mm，流道长度（刚好容纳3个cross）
Ly = 5.66;      % mm，流道宽度（1个cross的宽度）  
Lz = 1.2;       % mm，流道高度

d_fiber = 1.0;  % mm，纤维直径
r_fiber = 0.5;  % mm，纤维半径

pitch = 4.0;    % mm，节距
angle = 45;     % 度

dx = 0.05;      % mm，网格分辨率

NX = round(Lx / dx);  % 480
NY = round(Ly / dx);  % 113
NZ = round(Lz / dx);  % 24

% 一个cross在X方向的跨度
cross_period_x = pitch * sqrt(2);  % ≈ 5.657 mm
num_cross_x = 3;  % X方向3个cross

fprintf('网格: %d×%d×%d = %.2f 万\n', NX, NY, NZ, NX*NY*NZ/10000);
fprintf('1个cross宽度: %.3f mm\n', cross_period_x);
fprintf('3个cross总宽度: %.3f mm (Ly=%.2f)\n', 3*cross_period_x, Ly);
fprintf('计算域长度: %.2f mm\n', Lx);

%% 生成 2D XY 平面纤维结构
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
z = (0:NZ-1) * dx;

[X_2D, Y_2D] = meshgrid(x, y);

% 下层纤维：+45° 方向（从左下到右上）
% 并排3个cross，需要3组平行的+45°纤维
layer1_2D = false(NY, NX);

for cross_idx = 0:num_cross_x-1
    x_offset = cross_idx * cross_period_x;
    
    % 每个cross内的平行纤维
    for y_start_local = -Ly: pitch : (Ly + pitch)
        y_start = y_start_local + x_offset;  % 加上cross的偏移
        
        % 直线：y = x + y_start (45°)
        dist = abs(Y_2D - X_2D - y_start) / sqrt(2);
        layer1_2D = layer1_2D | (dist < r_fiber);
    end
end

% 上层纤维：-45° 方向（从左上到右下）
layer2_2D = false(NY, NX);

for cross_idx = 0:num_cross_x-1
    x_offset = cross_idx * cross_period_x;
    
    for y_start_local = -Ly: pitch : (Ly + pitch)
        y_start = y_start_local - x_offset;  % -45°方向，偏移相反
        
        % 直线：y = -x + y_start (-45°)
        dist = abs(Y_2D + X_2D - y_start) / sqrt(2);
        layer2_2D = layer2_2D | (dist < r_fiber);
    end
end

%% 沿 Z 方向构建 3D 结构（上下层交错）
solid = false(NY, NX, NZ);

% 下层占据Z底部，上层占据Z中部
z_layer1_end = r_fiber;        
z_layer2_start = r_fiber;

for iz = 1:NZ
    z_phys = z(iz);
    
    if z_phys <= z_layer1_end + dx/2
        solid(:, :, iz) = layer1_2D;  % 下层：+45°
    elseif z_phys >= z_layer2_start - dx/2 && z_phys <= (z_layer2_start + d_fiber + dx/2)
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

% 理论孔隙率估算
% 纤维体积 ≈ 长度 * π * r^2
% 单根斜纤维长度 ≈ sqrt(Lx^2 + Ly^2)
% 大概估算...
if porosity >= 0.75 && porosity <= 0.95
    fprintf('✓ 孔隙率正常\n');
else
    fprintf('注意：孔隙率可能需要调整\n');
end

%% 可视化
figure('Name', '3个Cross并排隔网', 'Position', [20 20 1600 450]);

[ys, xs, zs] = ind2sub([NY, NX, NZ], find(solid));

% 1. 3D整体
subplot(1,4,1);
scatter3(xs, ys, zs, 3, zs, 'filled');
axis equal tight;
xlabel('X'); ylabel('Y'); zlabel('Z');
title('3D整体（3个cross并排）');
colorbar; view(45,30); grid on;

% 2. XY俯视图（应该看到3组菱形）
subplot(1,4,2);
scatter(xs, ys, 1, 'b', 'filled');
axis equal tight;
xlabel('X (格点)'); ylabel('Y (格点)');
title('XY俯视图（3组菱形）');
grid on; box on;
xlim([1 NX]); ylim([1 NY]);

% 画3个cross的分界线
hold on;
for i = 1:2
    x_line = i * cross_period_x / dx;
    plot([x_line x_line], [1 NY], 'r--', 'LineWidth', 1);
end
hold off;

% 3. XZ侧视图
subplot(1,4,3);
scatter(xs, zs, 2, 'r', 'filled');
axis equal tight;
xlabel('X'); ylabel('Z');
title('XZ侧视图（上下两层）');
grid on; ylim([1 NZ]);

% 4. 局部放大（看一个cross的细节）
subplot(1,4,4);
center_x = round(cross_period_x / dx);
center_y = round(NY/2);
range = 40;

idx_local = (xs >= center_x-range) & (xs <= center_x+range) & ...
            (ys >= center_y-range) & (ys <= center_y+range);

scatter(xs(idx_local), ys(idx_local), 10, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y');
title(sprintf('局部放大（第1个cross中心）'));
grid on;

% 画菱形辅助线
hold on;
plot([center_x-range center_x+range], [center_y-range center_y+range], 'r--');
plot([center_x-range center_x+range], [center_y+range center_y-range], 'r--');
hold off;

%% 导出给 CUDA
fid = fopen('geometry_check.dat', 'w');
fprintf(fid, 'X Y Z\n');
for i = 1:length(xs)
    fprintf(fid, '%d %d %d\n', xs(i)-1, ys(i)-1, zs(i)-1);
end
fclose(fid);
fprintf('\n已保存: geometry_check.dat\n');

%% 导出二进制
fid = fopen('spacer_geometry.bin', 'wb');
fwrite(fid, uint8(solid), 'uint8');
fclose(fid);
fprintf('二进制文件: spacer_geometry.bin\n');
