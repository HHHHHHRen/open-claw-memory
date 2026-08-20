%% RO 菱形编织隔网（精确尺寸版）
clear; clc; close all;

%% 精确尺寸（来自文献）
d_fiber = 1.0;         % mm，纤维直径
r_fiber = 0.5;         % mm，纤维半径

d_node = 1.22;         % mm，球形节点高度（直径）
r_node = d_node / 2;   % 0.61 mm，节点半径

pitch = 4.0;           % mm，节距
dx = 0.05;             % mm

diamond_diag = pitch * sqrt(2);  % ≈ 5.657 mm

%% 计算域：3个cross
num_cross = 3;
Lx = num_cross * diamond_diag;
Ly = diamond_diag;
Lz = 2.0;              % 流道高度要足够容纳节点（>1.22mm）

NX = round(Lx / dx);
NY = round(Ly / dx);
NZ = round(Lz / dx);

fprintf('=== 精确尺寸隔网 ===\n');
fprintf('纤维直径: %.2f mm (半径%.2f)\n', d_fiber, r_fiber);
fprintf('节点直径: %.2f mm (半径%.2f)\n', d_node, r_node);
fprintf('网格: %d×%d×%d\n', NX, NY, NZ);

%% 网格
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
z = (0:NZ-1) * dx;

[X, Y, Z] = meshgrid(x, y, z);

%% 下层纤维位置（贴底放置）
% 纤维底部在 Z=0，顶部在 Z=1.0
% 纤维中心在 Z=0.5
z_fiber_center = r_fiber;  % 0.5 mm

%% 生成下层纤维（+45°）圆柱
d_lower = sqrt(2)/2;  % 水平距离换算系数

solid = false(NY, NX, NZ);

for c = -Ly:diamond_diag:(Lx+Ly)
    dist_xy = abs(X(:,:,1) - Y(:,:,1) - c) / sqrt(2);
    
    for iz = 1:NZ
        z_phys = z(iz);
        % 圆柱：水平距离<0.5 且 垂直距离<0.5（中心在0.5）
        dist_z = abs(z_phys - z_fiber_center);
        is_cyl = (dist_xy < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_cyl;
    end
end

%% 生成上层纤维（-45°）
for c = 0:diamond_diag:(Lx+Ly)
    dist_xy = abs(X(:,:,1) + Y(:,:,1) - c) / sqrt(2);
    
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_fiber_center);
        is_cyl = (dist_xy < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_cyl;
    end
end

%% 关键：生成凸起的球形节点
% 节点中心与纤维中心相同（Z=0.5）
% 但节点半径0.61 > 纤维半径0.5，所以向上凸起最高到1.22mm

for c1 = -Ly:diamond_diag:(Lx+Ly)
    for c2 = 0:diamond_diag:(Lx+Ly)
        x_cross = (c1 + c2) / 2;
        y_cross = (c2 - c1) / 2;
        
        if x_cross >= 0 && x_cross <= Lx && y_cross >= 0 && y_cross <= Ly
            % 节点中心与纤维同高（0.5mm）
            z_node_center = z_fiber_center;
            
            for iz = 1:NZ
                for iy = 1:NY
                    for ix = 1:NX
                        dist = sqrt((x(ix)-x_cross)^2 + (y(iy)-y_cross)^2 + (z(iz)-z_node_center)^2);
                        if dist < r_node  % 0.61mm半径
                            solid(iy, ix, iz) = true;
                        end
                    end
                end
            end
        end
    end
end

%% 统计
solid_count = sum(solid(:));
porosity = 1 - solid_count / (NX*NY*NZ);
fprintf('\n孔隙率: %.2f%%\n', porosity*100);

%% 可视化
figure('Name', '精确尺寸隔网', 'Position', [30 30 1600 450]);

[ys, xs, zs] = ind2sub([NY, NX, NZ], find(solid));

% XY俯视图
subplot(1,4,1);
scatter(xs, ys, 2, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y');
title(sprintf('XY俯视 (%.1f%%)', porosity*100));
grid on;

% XZ侧视图（纤维高1.0，节点高1.22）
subplot(1,4,2);
scatter(xs, zs, 2, 'r', 'filled');
axis equal tight;
xlabel('X'); ylabel('Z');
title('XZ侧视（纤维1.0mm，节点1.22mm）');
grid on;
hold on;
plot([0 NX], [0 0], 'k-');
plot([0 NX], [1.0/dx 1.0/dx], 'g--', 'LineWidth', 2);  % 纤维顶部
plot([0 NX], [1.22/dx 1.22/dx], 'r--', 'LineWidth', 2); % 节点顶部
hold off;

% YZ侧视图
subplot(1,4,3);
scatter(ys, zs, 2, 'g', 'filled');
axis equal tight;
xlabel('Y'); ylabel('Z');
title('YZ侧视');
grid on;

% 3D
subplot(1,4,4);
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
