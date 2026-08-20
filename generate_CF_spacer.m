%% RO 菱形编织隔网（CF - 带柱状节点）
% 基于论文 SI Figure S1 参数：
%   纤维直径 d = 0.4 mm
%   柱状节点直径 D = 0.566 mm
%   隔网厚度 h = 0.787 mm (31 mil)
%   纤维间距 pitch = 2.6 mm
%   编织角 alpha = 90°
%
% 修改日志：
%   1. 节点直径改为 0.566 mm（论文值）
%   2. 节点形状改为圆柱形（Z向贯穿全高）
%   3. 计算域 Z 范围改为隔网厚度 h_spacer
%   4. 纤维与节点布尔并集优化（避免重叠区重复标记）
%   5. 纤维生成向量化，去除冗余 Z 循环
%
clear; clc; close all;

%% ========== 核心参数（论文 CF 值） ==========
d_fiber  = 0.4;         % mm，纤维直径
d_node   = 0.566;       % mm，柱状节点直径（SI 明确值）
h_spacer = 0.787;       % mm，隔网厚度 = 柱高（31 mil）
L_horizontal = 2.6;     % mm，菱形水平对角线
alpha = 90;             % °，菱形内角（纤维交叉角）

%% ========== 派生参数 ==========
r_fiber = d_fiber / 2;
r_node  = d_node / 2;
theta = alpha / 2;      % 纤维与水平线夹角

% 菱形几何
L_vertical   = L_horizontal * tand(theta);      % 垂直对角线
pitch_normal = L_horizontal * sind(theta);       % 相邻同向纤维法向间距

%% 网格分辨率
dx = 0.05;              % mm，空间步长

%% 计算域
num_units = 3;
Lx = num_units * L_horizontal;      % X方向：3个单胞
Ly = L_vertical;                    % Y方向：1个单胞高度
Lz = h_spacer;                      % Z方向：隔网厚度（圆柱节点全高）

NX = round(Lx / dx);
NY = round(Ly / dx);
NZ = round(Lz / dx);

fprintf('=== CF 菱形编织隔网（内角%.0f°）===\n', alpha);
fprintf('纤维直径: %.2f mm, 节点直径: %.2f mm\n', d_fiber, d_node);
fprintf('隔网厚度: %.2f mm (%.0f mil)\n', h_spacer, round(h_spacer/0.0254));
fprintf('水平对角线: %.2f mm, 垂直对角线: %.2f mm\n', L_horizontal, L_vertical);
fprintf('纤维倾角: %.1f°, 法向间距: %.3f mm\n', theta, pitch_normal);
fprintf('网格分辨率: %.3f mm\n', dx);
fprintf('网格尺寸: %d × %d × %d = %.2e 格点\n', NX, NY, NZ, NX*NY*NZ);

%% ========== 生成网格坐标 ==========
x = (0:NX-1) * dx;
y = (0:NY-1) * dx;
z = (0:NZ-1) * dx;

% 预分配固体掩膜
fiber_mask = false(NY, NX, NZ);
node_mask  = false(NY, NX, NZ);

z_center = Lz / 2;      % 截面中心（纤维和柱轴都在中截面）

%% ========== 步骤1：生成圆柱形节点（纤维交叉点）==========
% 交叉点几何：
%   下层纤维 n: -x*sin(theta) + y*cos(theta) = c1 = n * pitch_normal
%   上层纤维 m:  x*sin(theta) + y*cos(theta) = c2 = m * pitch_normal
%   联立求解交点坐标

n_fibers = ceil((Ly + Lx) / pitch_normal) + 4;  % 裕量，确保覆盖边界

for n = -n_fibers:n_fibers
    c1 = n * pitch_normal;
    for m = -n_fibers:n_fibers
        c2 = m * pitch_normal;
        
        % 求解交点 (x_cross, y_cross)
        denom_cos = 2 * cosd(theta);
        denom_sin = 2 * sind(theta);
        
        if abs(denom_cos) < 1e-6 || abs(denom_sin) < 1e-6
            continue;  % 退化情况（theta=0°或90°理论上不会触发）
        end
        
        y_cross = (c1 + c2) / denom_cos;
        x_cross = (c2 - c1) / denom_sin;
        
        % 边界检查：只保留计算域附近（含边缘节点）
        margin = d_node;
        if x_cross < -margin || x_cross > Lx + margin || ...
           y_cross < -margin || y_cross > Ly + margin
            continue;
        end
        
        % === 圆柱形节点 ===
        % 定义：XY平面内距交叉点 < r_node 的所有点，Z方向全高（0 ~ Lz）
        % 向量化：直接对整个 3D 场标记
        for ix = 1:NX
            dx2 = (x(ix) - x_cross)^2;
            if dx2 > r_node^2, continue; end  % 快速跳过远场
            for iy = 1:NY
                dy2 = (y(iy) - y_cross)^2;
                if dx2 + dy2 > r_node^2, continue; end
                % 该 (ix,iy) 列的所有 Z 层都标记为节点
                node_mask(iy, ix, :) = true;
            end
        end
    end
end

fprintf('节点掩膜完成: %d 格点\n', sum(node_mask(:)));

%% ========== 步骤2：生成下层纤维（+theta 角度）==========
% 纤维几何：到直线距离 < r_fiber，且 |z - z_center| < r_fiber
% 布尔优化：只在 node_mask == false 的区域添加纤维

for n = -n_fibers:n_fibers
    c = n * pitch_normal;
    
    % 2D 距离场：点到直线的距离
    for iy = 1:NY
        for ix = 1:NX
            dist_line = abs(-x(ix)*sind(theta) + y(iy)*cosd(theta) - c);
            if dist_line >= r_fiber
                continue;  % 快速跳过
            end
            
            % Z 方向：纤维截面有限高度
            for iz = 1:NZ
                if abs(z(iz) - z_center) < r_fiber && ~node_mask(iy, ix, iz)
                    fiber_mask(iy, ix, iz) = true;
                end
            end
        end
    end
end

%% ========== 步骤3：生成上层纤维（-theta 角度）==========
for n = -n_fibers:n_fibers
    c = n * pitch_normal;
    
    for iy = 1:NY
        for ix = 1:NX
            dist_line = abs(x(ix)*sind(theta) + y(iy)*cosd(theta) - c);
            if dist_line >= r_fiber
                continue;
            end
            
            for iz = 1:NZ
                if abs(z(iz) - z_center) < r_fiber && ~node_mask(iy, ix, iz)
                    fiber_mask(iy, ix, iz) = true;
                end
            end
        end
    end
end

fprintf('纤维掩膜完成: %d 格点\n', sum(fiber_mask(:)));

%% ========== 步骤4：布尔并集合并 ==========
solid = fiber_mask | node_mask;
solid_count = sum(solid(:));
porosity = 1 - solid_count / (NX * NY * NZ);

fprintf('总固体格点: %d\n', solid_count);
fprintf('孔隙率: %.2f%%\n', porosity * 100);

%% ========== 可视化 ==========
[ys, xs, zs] = ind2sub([NY, NX, NZ], find(solid));

figure('Name', sprintf('CF隔网（内角%.0f°）', alpha), 'Position', [50 50 1400 420]);

subplot(1,3,1);
scatter(xs, ys, 2, 'b', 'filled');
axis equal tight; xlabel('X'); ylabel('Y');
title(sprintf('XY俯视 (孔隙率 %.1f%%)', porosity*100)); 
grid on; box on;

subplot(1,3,2);
scatter(xs, zs, 2, 'r', 'filled');
axis equal tight; xlabel('X'); ylabel('Z');
title('XZ侧视'); 
grid on; box on;

subplot(1,3,3);
scatter(ys, zs, 2, 'g', 'filled');
axis equal tight; xlabel('Y'); ylabel('Z');
title('YZ侧视'); 
grid on; box on;

% 3D 实体图
figure('Name', 'CF 3D视图', 'Position', [100 100 650 550]);
solid_double = double(solid);
solid_smooth = smooth3(solid_double, 'gaussian', 5, 1.0);
p = patch(isosurface(solid_smooth, 0.5));
isonormals(solid_smooth, p);
p.FaceColor = [0.3 0.6 0.9]; 
p.EdgeColor = 'none'; 
p.FaceAlpha = 0.85;
daspect([1 1 1]); 
view(45, 30); 
camlight('headlight'); 
lighting gouraud;
axis tight; 
xlabel('X'); ylabel('Y'); zlabel('Z');
title(sprintf('CF 3D实体（内角%.0f°，节点φ%.2f）', alpha, d_node));
rotate3d on;

%% ========== 导出 ==========
% MATLAB 格式
save('geometry_CF.mat', 'solid', 'x', 'y', 'z', 'NX', 'NY', 'NZ', ...
     'alpha', 'porosity', 'd_fiber', 'd_node', 'h_spacer');

% 文本坐标列表（C代码可读）
[ys_dat, xs_dat, zs_dat] = ind2sub([NY, NX, NZ], find(solid));
fid = fopen('geometry_CF.dat', 'w');
for i = 1:length(xs_dat)
    fprintf(fid, '%d %d %d\n', xs_dat(i)-1, ys_dat(i)-1, zs_dat(i)-1);
end
fclose(fid);

% 二进制格式（C代码直接读取）
% 结构：[NX, NY, NZ, 0] int32 头部 + uint8 数据（0=流体, 1=固体）
solid_c = permute(solid, [2, 1, 3]);  % 转置为 C-order（X 变化最快）
fid = fopen('geometry_CF.bin', 'wb');
fwrite(fid, [NX, NY, NZ, 0], 'int32');
fwrite(fid, uint8(solid_c(:)), 'uint8');
fclose(fid);

fprintf('\n导出完成:\n');
fprintf('  geometry_CF.mat   - MATLAB 工作区\n');
fprintf('  geometry_CF.dat   - 坐标文本列表\n');
fprintf('  geometry_CF.bin   - C代码二进制（%.2f MB）\n', ...
        (4*4 + NX*NY*NZ*1)/1024/1024);
