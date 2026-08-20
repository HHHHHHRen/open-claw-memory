%% RO 菱形编织隔网（完整3个cross，无截断）
clear; clc; close all;

%% 精确尺寸
d_fiber = 1.0;         % mm
r_fiber = 0.5;         % mm
d_node = 1.22;         % mm
r_node = d_node / 2;   % 0.61 mm
pitch = 4.0;           % mm
dx = 0.05;             % mm

diamond_diag = pitch * sqrt(2);  % ≈ 5.657 mm

%% 关键修改：计算域要包含3个完整菱形 + 边界纤维延伸
% 为了让边界处的菱形看起来完整，需要让纤维延伸到核心区域外
num_cross = 3;
Lx_core = num_cross * diamond_diag;  % 16.97 mm
Ly_core = diamond_diag;               % 5.657 mm

% 扩展：纤维要延伸出边界，形成完整菱形
% +45°纤维在左边界外要有延伸，-45°纤维在右边界外要有延伸
Lx = Lx_core + diamond_diag;  % 左右各扩展半个周期以上
Ly = Ly_core + diamond_diag;  % Y方向也扩展
Lz = 2.0;

NX = round(Lx / dx);
NY = round(Ly / dx);
NZ = round(Lz / dx);

% 核心区域：中间的3个完整cross
% 对齐到菱形边界：从第一个菱形的左边缘到最后一个的右边缘
% 第一个菱形的中心在 diamond_diag/2 处
x_core_start = round((diamond_diag/2) / dx);
x_core_end = x_core_start + round(Lx_core / dx);
y_core_start = round((diamond_diag/2) / dx);
y_core_end = y_core_start + round(Ly_core / dx);

fprintf('=== 完整3个cross隔网 ===\n');
fprintf('核心区域: %.2f×%.2f mm (3个完整cross)\n', Lx_core, Ly_core);
fprintf('扩展区域: %.2f×%.2f mm (边界纤维延伸)\n', Lx, Ly);
fprintf('网格: %d×%d×%d\n', NX, NY, NZ);

%% 网格
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
z = (0:NZ-1) * dx;

[X, Y] = meshgrid(x, y);

%% 生成纤维和节点
z_fiber_center = r_fiber;
solid = false(NY, NX, NZ);

% 下层纤维（+45°）：大范围生成，确保边界菱形完整
for c = -Ly:diamond_diag:(Lx+Ly)
    dist_xy = abs(X - Y - c) / sqrt(2);
    
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_fiber_center);
        is_cyl = (dist_xy < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_cyl;
    end
end

% 上层纤维（-45°）：大范围生成
for c = -diamond_diag/2:diamond_diag:(Lx+Ly)
    dist_xy = abs(X + Y - c) / sqrt(2);
    
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_fiber_center);
        is_cyl = (dist_xy < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_cyl;
    end
end

% 球形节点：大范围生成
for c1 = -Ly:diamond_diag:(Lx+Ly)
    for c2 = -diamond_diag/2:diamond_diag:(Lx+Ly)
        x_cross = (c1 + c2) / 2;
        y_cross = (c2 - c1) / 2;
        
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

%% 统计（核心3个cross区域）
core_solid = solid(y_core_start:y_core_end, x_core_start:x_core_end, :);
core_count = sum(core_solid(:));
core_total = (x_core_end-x_core_start+1) * (y_core_end-y_core_start+1) * NZ;
porosity = 1 - core_count / core_total;

fprintf('\n核心区域孔隙率: %.2f%%\n', porosity*100);

%% 可视化：只显示核心区域的固体，但包括延伸到边界外的部分
figure('Name', '完整3个cross隔网', 'Position', [30 30 1600 450]);

% 提取核心区域+边界的固体用于显示
x_display_start = x_core_start - round(r_node/dx);
x_display_end = x_core_end + round(r_node/dx);
y_display_start = y_core_start - round(r_node/dx);
y_display_end = y_core_end + round(r_node/dx);

x_display_start = max(1, x_display_start);
x_display_end = min(NX, x_display_end);
y_display_start = max(1, y_display_start);
y_display_end = min(NY, y_display_end);

display_solid = solid(y_display_start:y_display_end, x_display_start:x_display_end, :);
[ys, xs, zs] = ind2sub(size(display_solid), find(display_solid));
% 坐标调整
xs = xs + x_display_start - 1;
ys = ys + y_display_start - 1;

% XY俯视图
subplot(1,4,1);
scatter(xs, ys, 3, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y');
title(sprintf('XY俯视 3个完整cross (%.1f%%)', porosity*100));
grid on;
hold on;
% 标记核心区域边界
plot([x_core_start x_core_start], [y_core_start y_core_end], 'r-', 'LineWidth', 2);
plot([x_core_end x_core_end], [y_core_start y_core_end], 'r-', 'LineWidth', 2);
plot([x_core_start x_core_end], [y_core_start y_core_start], 'r-', 'LineWidth', 2);
plot([x_core_start x_core_end], [y_core_end y_core_end], 'r-', 'LineWidth', 2);
% 3个cross的分界线
for i = 1:2
    xv = x_core_start + i * round(diamond_diag/dx);
    plot([xv xv], [y_core_start y_core_end], 'g--', 'LineWidth', 1.5);
end
hold off;

% XZ侧视图
subplot(1,4,2);
scatter(xs, zs, 2, 'r', 'filled');
axis equal tight;
xlabel('X'); ylabel('Z');
title('XZ侧视');
grid on;
hold on;
plot([x_core_start x_core_start], [0 NZ], 'r-', 'LineWidth', 2);
plot([x_core_end x_core_end], [0 NZ], 'r-', 'LineWidth', 2);
plot([x_display_start x_display_end], [1.0/dx 1.0/dx], 'g--');
plot([x_display_start x_display_end], [1.22/dx 1.22/dx], 'r--');
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

%% 导出（核心3个cross区域）
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
fprintf('\n已导出核心3个cross: geometry_check.dat\n');
