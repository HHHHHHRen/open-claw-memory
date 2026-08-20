%% RO 菱形编织隔网（凸点节点版）
clear; clc; close all;

%% 参数
pitch = 4.0;           % mm，节距
d_fiber = 1.0;         % mm，纤维直径
r_fiber = 0.5;         % mm，纤维半径

dx = 0.05;             % mm

diamond_diag = pitch * sqrt(2);

Lx = 3 * diamond_diag;
Ly = diamond_diag;
Lz = 1.2;

NX = round(Lx / dx);
NY = round(Ly / dx);
NZ = round(Lz / dx);

fprintf('=== 凸点节点隔网 ===\n');
fprintf('网格: %d×%d×%d\n', NX, NY, NZ);

%% 生成3D网格
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
z = (0:NZ-1) * dx;

[X, Y, Z] = meshgrid(x, y, z);

%% 纤维中心高度
z_lower = r_fiber;           % 下层纤维中心（贴底）
z_upper = Lz - r_fiber;      % 上层纤维中心（贴顶）

%% 生成分离的圆柱纤维（不预填充）
lower_fiber = false(NY, NX, NZ);
upper_fiber = false(NY, NX, NZ);

% 下层圆柱（+45°）
for c = -Ly:diamond_diag:(Lx+Ly)
    dist_xy = abs(X(:,:,1) - Y(:,:,1) - c) / sqrt(2);
    for iz = 1:NZ
        dist_z = abs(z(iz) - z_lower);
        is_cyl = (dist_xy < r_fiber) & (dist_z < r_fiber);
        lower_fiber(:, :, iz) = lower_fiber(:, :, iz) | is_cyl;
    end
end

% 上层圆柱（-45°）
for c = 0:diamond_diag:(Lx+Ly)
    dist_xy = abs(X(:,:,1) + Y(:,:,1) - c) / sqrt(2);
    for iz = 1:NZ
        dist_z = abs(z(iz) - z_upper);
        is_cyl = (dist_xy < r_fiber) & (dist_z < r_fiber);
        upper_fiber(:, :, iz) = upper_fiber(:, :, iz) | is_cyl;
    end
end

%% 关键：生成凸起的球形节点
% 在交叉点处，节点向上凸起，高于圆柱纤维
nodes = false(NY, NX, NZ);

for c1 = -Ly:diamond_diag:(Lx+Ly)
    for c2 = 0:diamond_diag:(Lx+Ly)
        x_cross = (c1 + c2) / 2;
        y_cross = (c2 - c1) / 2;
        
        if x_cross >= 0 && x_cross <= Lx && y_cross >= 0 && y_cross <= Ly
            % 节点中心：向上凸起，高于下层纤维
            z_node = z_lower + r_fiber * 1.5;  % 凸起到纤维顶部以上
            
            % 节点半径：比纤维稍大
            r_node = r_fiber * 1.3;
            
            for iz = 1:NZ
                for iy = 1:NY
                    for ix = 1:NX
                        dist = sqrt((x(ix)-x_cross)^2 + (y(iy)-y_cross)^2 + (z(iz)-z_node)^2);
                        if dist < r_node
                            nodes(iy, ix, iz) = true;
                        end
                    end
                end
            end
        end
    end
end

%% 合并：圆柱 + 节点（节点覆盖圆柱）
solid = lower_fiber | upper_fiber | nodes;

%% 统计
solid_count = sum(solid(:));
porosity = 1 - solid_count / (NX*NY*NZ);
fprintf('\n孔隙率: %.2f%%\n', porosity*100);

%% 可视化
figure('Name', '凸点节点隔网', 'Position', [30 30 1600 450]);

[ys, xs, zs] = ind2sub([NY, NX, NZ], find(solid));

% XY俯视图
subplot(1,4,1);
scatter(xs, ys, 2, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y');
title(sprintf('XY俯视 (%.1f%%)', porosity*100));
grid on;

% XZ侧视图（应该看到下层+凸起的节点）
subplot(1,4,2);
scatter(xs, zs, 2, 'r', 'filled');
axis equal tight;
xlabel('X'); ylabel('Z');
title('XZ侧视（下层+凸点）');
grid on;
hold on;
plot([0 NX], [z_lower/dx z_lower/dx], 'b--');  % 下层中心线
plot([0 NX], [z_node/dx z_node/dx], 'r--');     % 节点中心线
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
