%% RO 菱形编织隔网（单层对称结构 - 总高1.22mm）
clear; clc; close all;

%% 精确尺寸
d_fiber = 1.0;        % mm，纤维直径
r_fiber = 0.5;        % mm，纤维半径
d_node = 1.22;        % mm，节点直径（总高度！）
r_node = d_node / 2;  % 0.61 mm，节点半径（也是总高度的一半）

pitch = 4.0;          % mm，节距
dx = 0.05;            % mm

diamond_diag = pitch * sqrt(2);  % ≈ 5.657 mm

%% 计算域：增加Y方向长度，确保节点完整
num_cross = 3;
Lx = num_cross * diamond_diag;
Ly = 2 * diamond_diag;  % 原来是1个，现在2个节距，确保Y方向有完整cross
Lz = d_node;          % 关键：总高度 = 节点直径 = 1.22mm

NX = round(Lx / dx);
NY = round(Ly / dx);
NZ = round(Lz / dx);

fprintf('=== 单层对称隔网（总高=节点直径）===\n');
fprintf('纤维直径: %.2f mm (半径%.2f)\n', d_fiber, r_fiber);
fprintf('节点直径: %.2f mm (半径%.2f) ← 也是总高度\n', d_node, r_node);
fprintf('网格: %d×%d×%d\n', NX, NY, NZ);
fprintf('总高度 Lz = %.2f mm\n', Lz);

%% 生成网格
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
z = (0:NZ-1) * dx;
[X, Y, Z] = meshgrid(x, y, z);

%% 关键：纤维和节点中心都在流道正中间（Z=0.61mm）
z_center = r_node;  % 0.61mm，正好是一半高度

solid = false(NY, NX, NZ);

%% 生成下层纤维（+45°）
for c = -Ly:diamond_diag:(Lx+Ly)
    dist_xy = abs(X(:,:,1) - Y(:,:,1) - c) / sqrt(2);
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_center);
        is_cyl = (dist_xy < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_cyl;
    end
end

%% 生成上层纤维（-45°）
for c = 0:diamond_diag:(Lx+Ly)
    dist_xy = abs(X(:,:,1) + Y(:,:,1) - c) / sqrt(2);
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_center);
        is_cyl = (dist_xy < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_cyl;
    end
end

%% 生成球形节点（上下对称，填满1.22mm高度）
for c1 = -Ly:diamond_diag:(Lx+Ly)
    for c2 = 0:diamond_diag:(Lx+Ly)
        x_cross = (c1 + c2) / 2;
        y_cross = (c2 - c1) / 2;
        
        if x_cross >= 0 && x_cross <= Lx && y_cross >= 0 && y_cross <= Ly
            % 节点中心在流道正中间
            z_node_center = z_center;
            
            % 球体：上下对称，半径0.61mm刚好到顶和底
            dist_sq = (X - x_cross).^2 + (Y - y_cross).^2 + (Z - z_node_center).^2;
            solid(dist_sq < r_node^2) = true;
        end
    end
end

%% 统计
solid_count = sum(solid(:));
porosity = 1 - solid_count / (NX*NY*NZ);
fprintf('\n孔隙率: %.2f%%\n', porosity*100);
fprintf('几何验证:\n');
fprintf('  纤维中心: Z=%.2f mm\n', z_center);
fprintf('  纤维范围: %.2f ~ %.2f mm (直径1.0mm)\n', z_center-r_fiber, z_center+r_fiber);
fprintf('  节点范围: %.2f ~ %.2f mm (直径1.22mm，填满)\n', z_center-r_node, z_center+r_node);
fprintf('  节点顶部/底部刚好在流道边界！\n');

%% 可视化
figure('Name', '单层对称隔网（总高1.22mm）', 'Position', [30 30 1600 450]);

[ys, xs, zs] = ind2sub([NY, NX, NZ], find(solid));

% XY俯视图
subplot(1,4,1);
scatter(xs, ys, 2, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y');
title(sprintf('XY俯视 (%.1f%%)', porosity*100));
grid on;

% XZ侧视图 - 关键验证图
subplot(1,4,2);
scatter(xs, zs, 2, 'r', 'filled');
axis equal tight;
xlabel('X'); ylabel('Z (mm)');
title('XZ侧视（总高1.22mm）');
grid on;
hold on;
% 标记关键位置（转换为网格坐标）
z_center_idx = z_center / dx;
z_fiber_top_idx = (z_center + r_fiber) / dx;
z_fiber_bot_idx = (z_center - r_fiber) / dx;
plot([0 NX], [z_center_idx z_center_idx], 'g--', 'LineWidth', 2); % 中心
plot([0 NX], [z_fiber_top_idx z_fiber_top_idx], 'b:', 'LineWidth', 1.5); % 纤维顶
plot([0 NX], [z_fiber_bot_idx z_fiber_bot_idx], 'b:', 'LineWidth', 1.5); % 纤维底
plot([0 NX], [0 0], 'k-', 'LineWidth', 2); % 底边界
plot([0 NX], [NZ-1 NZ-1], 'k-', 'LineWidth', 2); % 顶边界
hold off;
legend('', '中心', '纤维顶/底', '', '流道边界');

% YZ侧视图
subplot(1,4,3);
scatter(ys, zs, 2, 'g', 'filled');
axis tight;
xlabel('Y'); ylabel('Z');
title('YZ侧视');
grid on;

% 3D实体图 - 使用平滑让节点更圆润
subplot(1,4,4);
solid_double = double(solid);
% 关键：使用smooth3平滑，消除锯齿，凸显球状节点
solid_smooth = smooth3(solid_double, 'gaussian', 5, 1.0);
p = patch(isosurface(solid_smooth, 0.5));
isonormals(solid_smooth, p);
p.FaceColor = [0.3 0.6 0.9];
p.EdgeColor = 'none';
p.FaceAlpha = 0.9;
daspect([1 1 1]);
view(45, 30);
camlight; lighting gouraud;
axis tight;
xlabel('X'); ylabel('Y'); zlabel('Z');
title('3D实体（平滑后）');
rotate3d on;

%% 导出
save('geometry_single_layer.mat', 'solid', 'x', 'y', 'z', 'NX', 'NY', 'NZ', ...
     'd_fiber', 'r_fiber', 'd_node', 'r_node', 'pitch', 'dx', 'porosity', 'z_center');

fid = fopen('geometry_single_layer.dat', 'w');
fprintf(fid, 'X Y Z Type\n');
for i = 1:length(xs)
    fprintf(fid, '%d %d %d 1\n', xs(i)-1, ys(i)-1, zs(i)-1);
end
fclose(fid);

fprintf('\n已保存: geometry_single_layer.mat / .dat\n');

%% 额外验证：单独显示一个节点截面，确认是圆形
figure('Name', '节点截面验证', 'Position', [200 200 600 300]);

% 找到第一个cross点附近的切片
c1_test = 0; c2_test = diamond_diag;
x_test = (c1_test + c2_test) / 2;
y_test = (c2_test - c1_test) / 2;
x_idx = round(x_test / dx) + 1;
y_idx = round(y_test / dx) + 1;

% 显示该位置的XZ截面（通过cross点）
subplot(1,2,1);
imagesc(squeeze(solid(:, y_idx, :))');
axis image; colormap([1 1 1; 0 0 1]);
title(sprintf('XZ截面 @ Y=%.1f (cross点)', y_test));
xlabel('X'); ylabel('Z');

% 显示YZ截面
subplot(1,2,2);
imagesc(squeeze(solid(x_idx, :, :))');
axis image; colormap([1 1 1; 0 0 1]);
title(sprintf('YZ截面 @ X=%.1f', x_test));
xlabel('Y'); ylabel('Z');

sgtitle('节点截面验证（应是圆形）');
