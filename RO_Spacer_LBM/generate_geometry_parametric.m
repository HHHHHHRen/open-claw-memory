%% RO 菱形编织隔网（参数化版本 - 四大核心参数置顶）
clear; clc; close all;

%% ========== 四大核心结构参数（直接修改这里）==========
d_fiber = 1.0;              % mm，纤维圆截面直径
d_node = 1.22;              % mm，球形节点直径  
L_node_horizontal = 5.66;   % mm，两个水平结点的距离（菱形水平对角线）
alpha_diamond = 90;         % °，纤维交叉四边形最左内角

%% ========== 派生参数（自动计算，无需手动修改）==========
r_fiber = d_fiber / 2;                  % 纤维半径
r_node = d_node / 2;                    % 节点半径
% 菱形几何关系：对于内角alpha，节距 = 水平距离 / (2*cos(alpha/2))
% 当alpha=90°时，cos(45°)=√2/2，所以 pitch = L_node_horizontal / √2
pitch = L_node_horizontal / (2 * cosd(alpha_diamond/2));

dx = 0.05;                              % mm，计算网格分辨率

%% 计算域尺寸
num_cross = 3;                          % X方向cross数量
Lx = num_cross * L_node_horizontal;     % X方向总长度
Ly = 2 * L_node_horizontal;             % Y方向长度（确保节点完整）
Lz = d_node;                            % Z方向总高度 = 节点直径

NX = round(Lx / dx);
NY = round(Ly / dx);
NZ = round(Lz / dx);

fprintf('=== 参数化菱形编织隔网 ===\n');
fprintf('【核心参数】\n');
fprintf('  纤维直径: %.2f mm\n', d_fiber);
fprintf('  节点直径: %.2f mm\n', d_node);
fprintf('  水平节距: %.2f mm\n', L_node_horizontal);
fprintf('  菱形内角: %.0f°\n', alpha_diamond);
fprintf('【派生参数】\n');
fprintf('  纤维半径: %.2f mm\n', r_fiber);
fprintf('  节点半径: %.2f mm\n', r_node);
fprintf('  计算节距: %.3f mm\n', pitch);
fprintf('【计算域】\n');
fprintf('  网格: %d × %d × %d\n', NX, NY, NZ);
fprintf('  尺寸: %.2f × %.2f × %.2f mm³\n', Lx, Ly, Lz);

%% 生成网格
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
z = (0:NZ-1) * dx;
[X, Y, Z] = meshgrid(x, y, z);

%% 关键：纤维和节点中心都在流道正中间（Z=0.61mm）
z_center = r_node;

solid = false(NY, NX, NZ);

%% ========== 根据菱形内角计算纤维倾斜角 ==========
theta = alpha_diamond / 2;  % 纤维与水平线夹角（度）

%% 生成下层纤维（+theta 角度）
for c = -Ly:L_node_horizontal:(Lx+Ly)
    % 点到直线的垂直距离（法向距离）
    % 直线方向 +theta，法向量 (sin(theta), -cos(theta))
    dist_xy = abs(X(:,:,1) * sind(theta) - Y(:,:,1) * cosd(theta) - c);
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_center);
        is_cyl = (dist_xy < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_cyl;
    end
end

%% 生成上层纤维（-theta 角度）
for c = 0:L_node_horizontal:(Lx+Ly)
    % 直线方向 -theta，法向量 (sin(theta), cos(theta))
    dist_xy = abs(X(:,:,1) * sind(theta) + Y(:,:,1) * cosd(theta) - c);
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_center);
        is_cyl = (dist_xy < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_cyl;
    end
end

%% 生成球形节点（上下对称，填满d_node高度）
for c1 = -Ly:L_node_horizontal:(Lx+Ly)
    for c2 = 0:L_node_horizontal:(Lx+Ly)
        x_cross = (c1 + c2) / 2;
        y_cross = (c2 - c1) / 2;
        
        if x_cross >= 0 && x_cross <= Lx && y_cross >= 0 && y_cross <= Ly
            z_node_center = z_center;
            dist_sq = (X - x_cross).^2 + (Y - y_cross).^2 + (Z - z_node_center).^2;
            solid(dist_sq < r_node^2) = true;
        end
    end
end

%% 统计
solid_count = sum(solid(:));
porosity = 1 - solid_count / (NX*NY*NZ);
fprintf('\n孔隙率: %.2f%%\n', porosity*100);

%% 可视化
figure('Name', '参数化隔网结构', 'Position', [30 30 1600 450]);

[ys, xs, zs] = ind2sub([NY, NX, NZ], find(solid));

% XY俯视图
subplot(1,4,1);
scatter(xs, ys, 2, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y');
title(sprintf('XY俯视 (孔隙率%.1f%%)', porosity*100));
grid on;

% XZ侧视图
subplot(1,4,2);
scatter(xs, zs, 2, 'r', 'filled');
axis equal tight;
xlabel('X'); ylabel('Z (mm)');
title('XZ侧视');
grid on;
hold on;
z_center_idx = z_center / dx;
z_fiber_top_idx = (z_center + r_fiber) / dx;
z_fiber_bot_idx = (z_center - r_fiber) / dx;
plot([0 NX], [z_center_idx z_center_idx], 'g--', 'LineWidth', 2);
plot([0 NX], [z_fiber_top_idx z_fiber_top_idx], 'b:', 'LineWidth', 1.5);
plot([0 NX], [z_fiber_bot_idx z_fiber_bot_idx], 'b:', 'LineWidth', 1.5);
plot([0 NX], [0 0], 'k-', 'LineWidth', 2);
plot([0 NX], [NZ-1 NZ-1], 'k-', 'LineWidth', 2);
hold off;

% YZ侧视图
subplot(1,4,3);
scatter(ys, zs, 2, 'g', 'filled');
axis tight;
xlabel('Y'); ylabel('Z');
title('YZ侧视');
grid on;

% 3D实体图
subplot(1,4,4);
solid_double = double(solid);
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
title('3D实体');
rotate3d on;

%% 导出
save('geometry_parametric.mat', 'solid', 'x', 'y', 'z', 'NX', 'NY', 'NZ', ...
     'd_fiber', 'd_node', 'L_node_horizontal', 'alpha_diamond', 'pitch', ...
     'r_fiber', 'r_node', 'dx', 'porosity', 'z_center');

fid = fopen('geometry_parametric.dat', 'w');
fprintf(fid, 'TITLE="Parametric Spacer Geometry"\n');
fprintf(fid, 'VARIABLES="X","Y","Z"\n');
fprintf(fid, 'ZONE I=%d, J=%d, K=%d, F=POINT\n', NX, NY, NZ);
for i = 1:length(xs)
    fprintf(fid, '%d %d %d\n', xs(i)-1, ys(i)-1, zs(i)-1);
end
fclose(fid);

fprintf('\n已保存: geometry_parametric.mat / .dat\n');
fprintf('提示：修改顶部四个参数即可改变结构\n');
