%% RO 菱形编织隔网（3D交织结构）
clear; clc; close all;

%% 参数
pitch = 4.0;           % mm，节距
d_fiber = 1.0;         % mm，纤维直径
r_fiber = 0.5;         % mm，纤维半径

dx = 0.05;             % mm

diamond_diag = pitch * sqrt(2);  % ≈ 5.657 mm

% 计算域：3个cross
Lx = 3 * diamond_diag;
Ly = diamond_diag;
Lz = 1.2;              % 流道高度

NX = round(Lx / dx);
NY = round(Ly / dx);
NZ = round(Lz / dx);

fprintf('=== 3D编织隔网 ===\n');
fprintf('纤维直径: %.2f mm\n', d_fiber);
fprintf('网格: %d×%d×%d\n', NX, NY, NZ);

%% 生成3D网格
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
z = (0:NZ-1) * dx;

[X, Y, Z] = meshgrid(x, y, z);

%% 定义下层纤维（+45°方向）的位置
% 位于 Z = r_fiber 处（底部向上半根纤维）
z_lower = r_fiber;  % 下层纤维中心高度

%% 定义上层纤维（-45°方向）的位置  
% 位于 Z = Lz - r_fiber 处（顶部向下半根纤维）
z_upper = Lz - r_fiber;  % 上层纤维中心高度

%% 生成固体区域
solid = false(NY, NX, NZ);

% 下层纤维（+45°）：圆柱形，中心在 z_lower
for c = -Ly:diamond_diag:(Lx+Ly)
    % 到直线 x-y=c 的水平距离
    dist_xy = abs(X(:,:,1) - Y(:,:,1) - c) / sqrt(2);
    
    % 在Z方向，以 z_lower 为中心，半径 r_fiber 的圆柱
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_lower);
        
        % 圆柱判断：水平距离 < r_fiber 且 垂直距离 < r_fiber
        is_fiber = (dist_xy < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_fiber;
    end
end

% 上层纤维（-45°）：圆柱形，中心在 z_upper
for c = 0:diamond_diag:(Lx+Ly)
    dist_xy = abs(X(:,:,1) + Y(:,:,1) - c) / sqrt(2);
    
    for iz = 1:NZ
        z_phys = z(iz);
        dist_z = abs(z_phys - z_upper);
        
        is_fiber = (dist_xy < r_fiber) & (dist_z < r_fiber);
        solid(:, :, iz) = solid(:, :, iz) | is_fiber;
    end
end

%% 关键：添加交叉节点（球形）
% 在上下层纤维交叉处，形成球形节点

% 找到所有交叉点
for c1 = -Ly:diamond_diag:(Lx+Ly)      % 下层纤维
    for c2 = 0:diamond_diag:(Lx+Ly)    % 上层纤维
        % 交叉点：解 x-y=c1 和 x+y=c2
        % x = (c1+c2)/2, y = (c2-c1)/2
        x_cross = (c1 + c2) / 2;
        y_cross = (c2 - c1) / 2;
        
        % 检查是否在计算域内
        if x_cross >= 0 && x_cross <= Lx && y_cross >= 0 && y_cross <= Ly
            % 节点中心在上下层中间
            z_cross = (z_lower + z_upper) / 2;
            
            % 标记球形节点（半径略大于纤维半径，模拟交织凸起）
            r_node = r_fiber * 1.2;  % 节点稍大
            
            for iz = 1:NZ
                for iy = 1:NY
                    for ix = 1:NX
                        dist_node = sqrt((x(ix)-x_cross)^2 + (y(iy)-y_cross)^2 + (z(iz)-z_cross)^2);
                        if dist_node < r_node
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
figure('Name', '3D编织隔网', 'Position', [30 30 1600 450]);

[ys, xs, zs] = ind2sub([NY, NX, NZ], find(solid));

% XY俯视图
subplot(1,4,1);
scatter(xs, ys, 2, 'b', 'filled');
axis equal tight;
xlabel('X'); ylabel('Y');
title(sprintf('XY俯视 (%.1f%%)', porosity*100));
grid on;

% XZ侧视图（应该看到上下两层+中间节点）
subplot(1,4,2);
scatter(xs, zs, 2, 'r', 'filled');
axis equal tight;
xlabel('X'); ylabel('Z');
title('XZ侧视（两层+节点）');
grid on;

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
