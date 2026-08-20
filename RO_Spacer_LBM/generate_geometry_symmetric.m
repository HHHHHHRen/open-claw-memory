%% RO 菱形编织隔网（上下对称节点版）
clear; clc; close all;

%% 精确尺寸
d_fiber = 1.0; r_fiber = 0.5;
d_node = 1.22; r_node = d_node / 2;  % 0.61 mm
pitch = 4.0; dx = 0.05;
diamond_diag = pitch * sqrt(2);

%% 计算域
num_cross = 3;
Lx = num_cross * diamond_diag;
Ly = diamond_diag;
Lz = 3.0;  % 增加高度，确保节点上下都有空间 (需要 > 1.22*2 + 纤维间隙)

NX = round(Lx / dx);
NY = round(Ly / dx);
NZ = round(Lz / dx);

fprintf('=== 上下对称节点隔网 ===\n');
fprintf('网格: %d×%d×%d\n', NX, NY, NZ);

%% 生成网格
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
z = (0:NZ-1) * dx;
[X, Y, Z] = meshgrid(x, y, z);

%% ========== 关键修改：纤维放在流道中间，实现上下对称 ==========
z_fiber_center = Lz / 2;  % 流道中心（原来是 r_fiber = 贴底）

solid = false(NY, NX, NZ);

%% 下层纤维（+45°）
for c = -Ly:diamond_diag:(Lx+Ly)
    dist_xy = abs(X(:,:,1) - Y(:,:,1) - c) / sqrt(2);
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_fiber_center);
        is_cyl = (dist_xy < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_cyl;
    end
end

%% 上层纤维（-45°）
for c = 0:diamond_diag:(Lx+Ly)
    dist_xy = abs(X(:,:,1) + Y(:,:,1) - c) / sqrt(2);
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_fiber_center);
        is_cyl = (dist_xy < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_cyl;
    end
end

%% ========== 上下对称的球形节点 ==========
% 节点中心与纤维同高，向上下两个方向对称凸起
for c1 = -Ly:diamond_diag:(Lx+Ly)
    for c2 = 0:diamond_diag:(Lx+Ly)
        x_cross = (c1 + c2) / 2;
        y_cross = (c2 - c1) / 2;
        
        if x_cross >= 0 && x_cross <= Lx && y_cross >= 0 && y_cross <= Ly
            % 节点中心在纤维中心（流道中间）
            z_node_center = z_fiber_center;
            
            % 向量化计算球体（上下对称）
            dist_sq = (X - x_cross).^2 + (Y - y_cross).^2 + (Z - z_node_center).^2;
            solid(dist_sq < r_node^2) = true;
        end
    end
end

%% 统计
solid_count = sum(solid(:));
porosity = 1 - solid_count / (NX*NY*NZ);
fprintf('孔隙率: %.2f%%\n', porosity*100);
fprintf('纤维中心高度: %.2f mm (流道中间)\n', z_fiber_center);
fprintf('节点向上延伸到: %.2f mm\n', z_fiber_center + r_node);
fprintf('节点向下延伸到: %.2f mm\n', z_fiber_center - r_node);

%% 可视化
figure('Name', '上下对称隔网', 'Position', [30 30 1600 450]);

[ys, xs, zs] = ind2sub([NY, NX, NZ], find(solid));

% XY俯视图
subplot(1,4,1);
scatter(xs, ys, 2, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y');
title(sprintf('XY俯视 (%.1f%%)', porosity*100));
grid on;

% XZ侧视图 - 关键：现在能看到上下对称的节点！
subplot(1,4,2);
scatter(xs, zs, 2, 'r', 'filled');
axis equal tight;
xlabel('X'); ylabel('Z');
title('XZ侧视（上下对称节点）');
grid on;
hold on;
plot([0 NX], [z_fiber_center/dx z_fiber_center/dx], 'g--', 'LineWidth', 2); % 纤维中心
plot([0 NX], [(z_fiber_center+r_node)/dx (z_fiber_center+r_node)/dx], 'r--', 'LineWidth', 1); % 节点顶部
plot([0 NX], [(z_fiber_center-r_node)/dx (z_fiber_center-r_node)/dx], 'r--', 'LineWidth', 1); % 节点底部（新增！）
hold off;

% YZ侧视图
subplot(1,4,3);
scatter(ys, zs, 2, 'g', 'filled');
axis equal tight;
xlabel('Y'); ylabel('Z');
title('YZ侧视');
grid on;

% 3D实体图（isosurface）
subplot(1,4,4);
solid_double = double(solid);
p = patch(isosurface(solid_double, 0.5));
isonormals(solid_double, p);
p.FaceColor = [0.3 0.6 0.9];
p.EdgeColor = 'none';
p.FaceAlpha = 0.8;
daspect([1 1 1]);
view(45, 30);
camlight; lighting gouraud;
axis tight;
xlabel('X'); ylabel('Y'); zlabel('Z');
title('3D实体（上下对称）');
rotate3d on;

%% 导出
save('geometry_symmetric.mat', 'solid', 'x', 'y', 'z', 'NX', 'NY', 'NZ', ...
     'd_fiber', 'r_fiber', 'd_node', 'r_node', 'pitch', 'dx', 'porosity', 'z_fiber_center');

fid = fopen('geometry_symmetric.dat', 'w');
fprintf(fid, 'X Y Z\n');
for i = 1:length(xs)
    fprintf(fid, '%d %d %d\n', xs(i)-1, ys(i)-1, zs(i)-1);
end
fclose(fid);

fprintf('\n已保存: geometry_symmetric.mat / .dat\n');
fprintf('关键修改：纤维位于流道中心 (Z=%.2f)，节点上下对称凸起\n', z_fiber_center);
