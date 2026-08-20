%% RO 菱形编织隔网（3×1阵列，完整节点版）
clear; clc; close all;

%% 精确尺寸
d_fiber = 1.0;         % mm，纤维直径
r_fiber = 0.5;         % mm

d_node = 1.22;         % mm，球形节点高度
r_node = d_node / 2;   % 0.61 mm

pitch = 4.0;           % mm，节距
dx = 0.05;             % mm

diamond_diag = pitch * sqrt(2);  % ≈ 5.657 mm

%% 计算域：X方向3个cross，Y方向1个cross
num_cross_x = 3;
num_cross_y = 1;

Lx_core = num_cross_x * diamond_diag;  % X方向3个cross
Ly_core = num_cross_y * diamond_diag;  % Y方向1个cross

% 关键：扩展边界，让边界节点完整显示
Lx = Lx_core + 2 * r_node;  % 左右各扩展r_node
Ly = Ly_core + 2 * r_node;  % 上下各扩展r_node
Lz = 2.0;

NX = round(Lx / dx);
NY = round(Ly / dx);
NZ = round(Lz / dx);

% 核心区域索引（3×1个cross）
x_core_start = round(r_node / dx);
x_core_end = x_core_start + round(Lx_core / dx);
y_core_start = round(r_node / dx);
y_core_end = y_core_start + round(Ly_core / dx);

fprintf('=== 3×1阵列隔网（完整节点） ===\n');
fprintf('核心区域: %.2f×%.2f mm (X:3个cross, Y:1个cross)\n', Lx_core, Ly_core);
fprintf('扩展区域: %.2f×%.2f mm (含完整节点)\n', Lx, Ly);
fprintf('网格: %d×%d×%d\n', NX, NY, NZ);

%% 网格
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
z = (0:NZ-1) * dx;

[X, Y] = meshgrid(x, y);

%% 生成纤维和节点
z_fiber_center = r_fiber;
solid = false(NY, NX, NZ);

% 下层纤维（+45°）：扩展范围，确保边界纤维完整
for c = -(Ly+r_node):diamond_diag:(Lx+Ly+r_node)
    dist_xy = abs(X - Y - c) / sqrt(2);
    
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_fiber_center);
        is_cyl = (dist_xy < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_cyl;
    end
end

% 上层纤维（-45°）：扩展范围
for c = -r_node:diamond_diag:(Lx+Ly+r_node)
    dist_xy = abs(X + Y - c) / sqrt(2);
    
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_fiber_center);
        is_cyl = (dist_xy < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_cyl;
    end
end

% 球形节点：扩展范围，确保边界节点完整
for c1 = -(Ly+r_node):diamond_diag:(Lx+Ly+r_node)
    for c2 = -r_node:diamond_diag:(Lx+Ly+r_node)
        x_cross = (c1 + c2) / 2;
        y_cross = (c2 - c1) / 2;
        
        % 只要节点中心在扩展区域内，就生成完整节点
        if x_cross >= -r_node && x_cross <= (Lx+r_node) && ...
           y_cross >= -r_node && y_cross <= (Ly+r_node)
            
            z_node_center = z_fiber_center;
            
            for iz = 1:NZ
                for iy = 1:NY
                    for ix = 1:NX
                        dist = sqrt((x(ix)-x_cross)^2 + (y(iy)-y_cross)^2 + (z(iz)-z_node_center)^2);
                        if dist < r_node
                            solid(iy, ix, iz) = true;
                        end
                    end
                end
            end
        end
    end
end

%% 统计（核心3×1区域）
core_solid = solid(y_core_start:y_core_end, x_core_start:x_core_end, :);
core_count = sum(core_solid(:));
core_total = (x_core_end-x_core_start+1) * (y_core_end-y_core_start+1) * NZ;
porosity = 1 - core_count / core_total;

fprintf('\n核心区域孔隙率: %.2f%%\n', porosity*100);

%% 可视化
figure('Name', '3×1阵列隔网（完整节点）', 'Position', [30 30 1600 450]);

[ys, xs, zs] = ind2sub([NY, NX, NZ], find(solid));

% XY俯视图：显示完整节点，但标记核心3×1区域
subplot(1,4,1);
scatter(xs, ys, 2, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y');
title(sprintf('XY俯视 (核心%.1f%%)', porosity*100));
grid on;
hold on;
% 核心区域边界（红色实线）
plot([x_core_start x_core_start], [y_core_start y_core_end], 'r-', 'LineWidth', 2);
plot([x_core_end x_core_end], [y_core_start y_core_end], 'r-', 'LineWidth', 2);
plot([x_core_start x_core_end], [y_core_start y_core_start], 'r-', 'LineWidth', 2);
plot([x_core_start x_core_end], [y_core_end y_core_end], 'r-', 'LineWidth', 2);
% X方向3个cross分界线
for i = 1:2
    xv = x_core_start + i * round(diamond_diag/dx);
    plot([xv xv], [y_core_start y_core_end], 'r--', 'LineWidth', 1);
end
hold off;

% XZ侧视图
subplot(1,4,2);
scatter(xs, zs, 2, 'r', 'filled');
axis equal tight;
xlabel('X'); ylabel('Z');
title('XZ侧视（完整节点）');
grid on;
hold on;
plot([x_core_start x_core_start], [0 NZ], 'r-', 'LineWidth', 2);
plot([x_core_end x_core_end], [0 NZ], 'r-', 'LineWidth', 2);
plot([0 NX], [1.0/dx 1.0/dx], 'g--');
plot([0 NX], [1.22/dx 1.22/dx], 'r--');
hold off;

% YZ侧视图
subplot(1,4,3);
scatter(ys, zs, 2, 'g', 'filled');
axis equal tight;
xlabel('Y'); ylabel('Z');
title('YZ侧视');
grid on;
hold on;
plot([y_core_start y_core_start], [0 NZ], 'r-', 'LineWidth', 2);
plot([y_core_end y_core_end], [0 NZ], 'r-', 'LineWidth', 2);
hold off;

% 3D
subplot(1,4,4);
scatter3(xs, ys, zs, 2, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y'); zlabel('Z');
title('3D');
view(45,30); grid on;

%% 导出（核心3×1区域，用于CUDA）
fid = fopen('geometry_check.dat', 'w');
fprintf(fid, 'X Y Z\n');
for iz = 1:NZ
    for iy = y_core_start:y_core_end
        for ix = x_core_start:x_core_end
            if solid(iy, ix, iz)
                fprintf(fid, '%d %d %d\n', ix-x_core_start, iy-y_core_start, iz-1);
            end
        end
    end
end
fclose(fid);
fprintf('\n已导出核心3×1区域: geometry_check.dat\n');
