%% RO 菱形编织隔网（正确参数化版本）
clear; clc; close all;

%% ========== 四大核心参数 ==========
d_fiber = 1.0;              % mm，纤维直径
d_node = 1.22;              % mm，球形节点直径  
L_horizontal = 5.66;        % mm，水平方向相邻节点距离（菱形水平对角线）
alpha = 90;                 % °，菱形内角（纤维交叉角）

%% ========== 派生参数 ==========
r_fiber = d_fiber / 2;
r_node = d_node / 2;
theta = alpha / 2;                      % 纤维与水平线夹角

% 菱形几何：
% - 水平对角线 = L_horizontal
% - 垂直对角线 = L_horizontal * tan(theta)
% - 相邻同向纤维法向间距 = L_horizontal * sin(theta)

L_vertical = L_horizontal * tand(theta);
pitch_normal = L_horizontal * sind(theta);  % 关键：法向间距

dx = 0.05;

%% 计算域
num_units = 3;
Lx = num_units * L_horizontal;
Ly = 2 * L_vertical + 2 * d_node;  % 多留边距确保完整
Lz = d_node;

NX = round(Lx / dx);
NY = round(Ly / dx);
NZ = round(Lz / dx);

fprintf('=== 菱形编织隔网（内角%.0f°）===\n', alpha);
fprintf('水平对角线: %.2f mm, 垂直对角线: %.2f mm\n', L_horizontal, L_vertical);
fprintf('纤维倾角: %.1f°, 法向节距: %.3f mm\n', theta, pitch_normal);
fprintf('网格: %d × %d × %d\n', NX, NY, NZ);

%% 网格
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
z = (0:NZ-1) * dx;
[X, Y, Z] = meshgrid(x, y, z);

z_center = r_node;
solid = false(NY, NX, NZ);

%% ========== 下层纤维（+theta角度）==========
% 纤维方向向量: (cos(theta), sin(theta))
% 法向量: (-sin(theta), cos(theta))
% 通过原点 (0,0) 的纤维，以及沿法向偏移的平行纤维

n_fibers = ceil((Ly + Lx) / pitch_normal) + 2;
for n = -n_fibers:n_fibers
    % 纤维直线的偏移量（沿法向）
    c = n * pitch_normal;
    
    % 点到直线的距离 = | -x*sin + y*cos - c |
    dist_line = abs(-X(:,:,1) * sind(theta) + Y(:,:,1) * cosd(theta) - c);
    
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_center);
        is_cyl = (dist_line < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_cyl;
    end
end

%% ========== 上层纤维（-theta角度）==========
% 纤维方向向量: (cos(theta), -sin(theta))
% 法向量: (sin(theta), cos(theta))

for n = -n_fibers:n_fibers
    c = n * pitch_normal;
    
    % 点到直线的距离 = | x*sin + y*cos - c |
    dist_line = abs(X(:,:,1) * sind(theta) + Y(:,:,1) * cosd(theta) - c);
    
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_center);
        is_cyl = (dist_line < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_cyl;
    end
end

%% ========== 生成球形节点（纤维交叉点）==========
% 交叉点：下层纤维n与上层纤维m的交点
% 下层: -x*sin + y*cos = c1 = n * pitch_normal
% 上层:  x*sin + y*cos = c2 = m * pitch_normal
% 相加: 2*y*cos = c1+c2 => y = (c1+c2)/(2*cos)
% 相减: -2*x*sin = c1-c2 => x = (c2-c1)/(2*sin)

for n = -n_fibers:n_fibers
    c1 = n * pitch_normal;
    for m = -n_fibers:n_fibers
        c2 = m * pitch_normal;
        
        % 计算交叉点坐标
        if abs(cosd(theta)) > 0.001
            y_cross = (c1 + c2) / (2 * cosd(theta));
        else
            continue;  % theta=90°时特殊处理
        end
        
        if abs(sind(theta)) > 0.001
            x_cross = (c2 - c1) / (2 * sind(theta));
        else
            x_cross = 0;  % theta=0°退化情况
        end
        
        % 只保留在计算域内的节点
        if x_cross >= -d_node && x_cross <= Lx+d_node && ...
           y_cross >= -d_node && y_cross <= Ly+d_node
            
            dist_sq = (X - x_cross).^2 + (Y - y_cross).^2 + (Z - z_center).^2;
            solid(dist_sq < r_node^2) = true;
        end
    end
end

%% ========== 统计和可视化 ==========
solid_count = sum(solid(:));
porosity = 1 - solid_count / (NX*NY*NZ);
fprintf('孔隙率: %.2f%%\n', porosity*100);

figure('Name', sprintf('隔网（内角%.0f°）', alpha), 'Position', [30 30 1400 400]);
[ys, xs, zs] = ind2sub([NY, NX, NZ], find(solid));

subplot(1,3,1);
scatter(xs, ys, 1.5, 'b', 'filled');
axis equal tight; xlabel('X'); ylabel('Y');
title(sprintf('XY俯视 (%.1f%%)', porosity*100)); grid on;

subplot(1,3,2);
scatter(xs, zs, 1.5, 'r', 'filled');
axis equal tight; xlabel('X'); ylabel('Z');
title('XZ侧视'); grid on;

subplot(1,3,3);
scatter(ys, zs, 1.5, 'g', 'filled');
axis equal tight; xlabel('Y'); ylabel('Z');
title('YZ侧视'); grid on;

%% 3D图
figure('Name', '3D视图', 'Position', [100 100 600 500]);
solid_double = double(solid);
solid_smooth = smooth3(solid_double, 'gaussian', 5, 1.0);
p = patch(isosurface(solid_smooth, 0.5));
isonormals(solid_smooth, p);
p.FaceColor = [0.3 0.6 0.9]; p.EdgeColor = 'none'; p.FaceAlpha = 0.9;
daspect([1 1 1]); view(45, 30); camlight; lighting gouraud;
axis tight; xlabel('X'); ylabel('Y'); zlabel('Z');
title(sprintf('3D实体（内角%.0f°）', alpha)); rotate3d on;

%% 导出
save('geometry.mat', 'solid', 'x', 'y', 'z', 'NX', 'NY', 'NZ', 'alpha', 'porosity');
fid = fopen('geometry.dat', 'w');
for i = 1:length(xs)
    fprintf(fid, '%d %d %d\n', xs(i)-1, ys(i)-1, zs(i)-1);
end
fclose(fid);
fprintf('已保存: geometry.mat / geometry.dat\n');
