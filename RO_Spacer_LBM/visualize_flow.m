%% RO Spacer LBM 流速可视化
% 加载数据并绘制各种流速图
% Usage: 在MATLAB命令行直接运行 visualize_flow

clear; close all; clc;

%% 1. 加载数据
filename = 'spacer_flow_0050.mat';
if ~exist(filename, 'file')
    error('文件 %s 不存在', filename);
end

data = load(filename);
nx = data.nx; ny = data.ny; nz = data.nz;

fprintf('数据加载成功:\n');
fprintf('  Grid: %d x %d x %d\n', nx, ny, nz);
fprintf('  Fields: rho, ux, uy, uz\n\n');

%% 2. 提取速度场
u = data.ux;  % [nz, ny, nx] - MATLAB是列优先
v = data.uy;
w = data.uz;
rho = data.rho;

%% 3. 计算速度大小（用于着色）
speed = sqrt(u.^2 + v.^2 + w.^2);
fprintf('速度范围: %.4f ~ %.4f\n', min(speed(:)), max(speed(:)));

%% 4. 创建坐标网格
x = linspace(0, nx-1, nx);
y = linspace(0, ny-1, ny);
z = linspace(0, nz-1, nz);
[X, Y, Z] = meshgrid(x, y, z);  % 注意meshgrid的维度顺序

%% 5. 图1: 中心切片速度云图
figure('Name', '速度大小分布', 'Position', [100 100 1200 400]);

% Z方向中间切片
subplot(1,3,1);
z_slice = round(nz/2);
imagesc(x, y, squeeze(speed(z_slice,:,:)));
axis image; colorbar;
title(sprintf('Z=%d 切片 (水平面)', z_slice));
xlabel('X'); ylabel('Y');

% Y方向中间切片
subplot(1,3,2);
y_slice = round(ny/2);
imagesc(x, z, squeeze(speed(:,y_slice,:)));
axis image; colorbar;
title(sprintf('Y=%d 切片 (侧面)', y_slice));
xlabel('X'); ylabel('Z');

% X方向中间切片
subplot(1,3,3);
x_slice = round(nx/2);
imagesc(y, z, squeeze(speed(:,:,x_slice)));
axis image; colorbar;
title(sprintf('X=%d 切片 (端面)', x_slice));
xlabel('Y'); ylabel('Z');

sgtitle('速度大小分布');
colormap(jet);

%% 6. 图2: 3D矢量图（降采样显示）
figure('Name', '3D速度矢量', 'Position', [100 550 800 600]);

% 降采样，避免箭头太多
skip_x = 20;
skip_y = 10;
skip_z = 5;

x_sub = 1:skip_x:nx;
y_sub = 1:skip_y:ny;
z_sub = 1:skip_z:nz;

% 提取子集
u_sub = u(z_sub, y_sub, x_sub);
v_sub = v(z_sub, y_sub, x_sub);
w_sub = w(z_sub, y_sub, x_sub);
speed_sub = speed(z_sub, y_sub, x_sub);

[X_sub, Y_sub, Z_sub] = meshgrid(x(x_sub), y(y_sub), z(z_sub));

% 绘制矢量图
quiver3(X_sub, Y_sub, Z_sub, u_sub, v_sub, w_sub, 2);
axis equal tight;
title('3D速度矢量场（降采样）');
xlabel('X'); ylabel('Y'); zlabel('Z');
grid on; view(3);
colorbar;

%% 7. 图3: 切片+等高线（推荐）
figure('Name', '速度云图+流线', 'Position', [150 100 1000 700]);

% 选择几个Z层
z_levels = [5, round(nz/2), nz-5];

for i = 1:length(z_levels)
    subplot(2, 2, i);
    z_idx = z_levels(i);
    
    % 绘制速度大小
    contourf(x, y, squeeze(speed(z_idx,:,:)), 20, 'LineColor', 'none');
    axis image; colorbar;
    hold on;
    
    % 叠加速度矢量（稀疏显示）
    skip = 10;
    [X2d, Y2d] = meshgrid(x(1:skip:end), y(1:skip:end));
    U2d = squeeze(u(z_idx, 1:skip:end, 1:skip:end));
    V2d = squeeze(v(z_idx, 1:skip:end, 1:skip:end));
    quiver(X2d, Y2d, U2d, V2d, 1.5, 'k');
    
    title(sprintf('Z=%d 切片', z_idx));
    xlabel('X'); ylabel('Y');
end

% 颜色条统一
subplot(2, 2, 4);
axis off;
caxis([min(speed(:)), max(speed(:))]);
colormap(jet);
cb = colorbar('Location', 'west');
ylabel(cb, '速度大小');

sgtitle('速度云图与矢量叠加');

%% 8. 图4: 速度剖面曲线
figure('Name', '速度剖面', 'Position', [200 200 800 500]);

% X方向中心线速度
x_line = 1:nx;
u_center_x = squeeze(u(round(nz/2), round(ny/2), :));

subplot(2,1,1);
plot(x_line, u_center_x, 'b-', 'LineWidth', 2);
xlabel('X'); ylabel('U');
title('X方向中心线速度剖面 (Y=center, Z=center)');
grid on;

% Z方向速度分布
z_line = 1:nz;
w_center_z = squeeze(w(:, round(ny/2), round(nx/2)));

subplot(2,1,2);
plot(z_line, w_center_z, 'r-', 'LineWidth', 2);
xlabel('Z'); ylabel('W');
title('Z方向中心线速度剖面 (X=center, Y=center)');
grid on;

%% 9. 图5: 3D切片可视化（需要较新版本MATLAB）
try
    figure('Name', '3D切片', 'Position', [100 100 900 700]);
    
    % 创建切片位置
    xs = round(nx/2);
    ys = round(ny/2);
    zs = round(nz/2);
    
    % 使用slice函数
    slice(X, Y, Z, speed, xs, ys, zs);
    shading interp;
    axis equal tight;
    view(3);
    camlight;
    lighting gouraud;
    
    xlabel('X'); ylabel('Y'); zlabel('Z');
    title('3D速度大小切片');
    colorbar;
    colormap(jet);
catch
    disp('3D切片图需要足够的内存，跳过');
end

%% 10. 保存图片
saveas(1, 'flow_slice.png');
saveas(2, 'flow_vector3d.png');
saveas(3, 'flow_contour.png');

fprintf('\n可视化完成！\n');
fprintf('图片已保存: flow_slice.png, flow_vector3d.png, flow_contour.png\n');
