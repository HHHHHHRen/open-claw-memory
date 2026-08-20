%% RO Spacer 几何可视化
% 读取 geometry.dat 并绘制3D间隔网结构

clear; close all; clc;

%% 1. 读取几何文件
filename = 'geometry.dat';
if ~exist(filename, 'file')
    error('文件 %s 不存在，请先运行 LBM 仿真生成几何文件', filename);
end

% 读取数据 (跳过前3行header)
fid = fopen(filename, 'r');
for i = 1:3
    fgetl(fid);  % 跳过标题行
end

% 读取所有数据 [X, Y, Z, Type]
data = fscanf(fid, '%d %d %d %d', [4, Inf])';
fclose(fid);

x = data(:,1);
y = data(:,2);
z = data(:,3);
type = data(:,4);  % 0=fluid, 1=solid, 2=boundary

fprintf('几何数据加载成功:\n');
fprintf('  总单元数: %d\n', length(x));
fprintf('  固体单元: %d\n', sum(type==1));
fprintf('  边界单元: %d\n', sum(type==2));
fprintf('  流体单元: %d\n', sum(type==0));

%% 2. 图1: 3D散点图 - 不同类型的单元
figure('Name', 'Spacer Geometry 3D', 'Position', [100 100 1200 500]);

% 固体纤维
subplot(1,3,1);
idx_solid = find(type == 1);
scatter3(x(idx_solid), y(idx_solid), z(idx_solid), 10, 'b', 'filled');
axis equal tight;
title(sprintf('Solid Fibers (n=%d)', length(idx_solid)));
xlabel('X'); ylabel('Y'); zlabel('Z');
grid on; view(3);

% 边界节点
subplot(1,3,2);
idx_bnd = find(type == 2);
scatter3(x(idx_bnd), y(idx_bnd), z(idx_bnd), 10, 'r', 'filled');
axis equal tight;
title(sprintf('Boundary Nodes (n=%d)', length(idx_bnd)));
xlabel('X'); ylabel('Y'); zlabel('Z');
grid on; view(3);

% 叠加显示
subplot(1,3,3);
hold on;
if ~isempty(idx_solid)
    scatter3(x(idx_solid), y(idx_solid), z(idx_solid), 8, 'b', 'filled', 'DisplayName', 'Solid');
end
if ~isempty(idx_bnd)
    scatter3(x(idx_bnd), y(idx_bnd), z(idx_bnd), 8, 'r', 'filled', 'DisplayName', 'Boundary');
end
axis equal tight;
title('Combined Geometry');
xlabel('X'); ylabel('Y'); zlabel('Z');
legend;
grid on; view(3);
rotate3d on;

%% 3. 图2: 切片视图 (看内部结构)
figure('Name', 'Geometry Slices', 'Position', [100 550 900 400]);

nx = max(x)+1; ny = max(y)+1; nz = max(z)+1;

% 创建3D类型数组
geom = zeros(nx, ny, nz);
for i = 1:length(x)
    geom(x(i)+1, y(i)+1, z(i)+1) = type(i);
end

% Z方向切片
subplot(1,3,1);
z_slice = round(nz/2);
imagesc(squeeze(geom(:,:,z_slice))');
axis image; colormap([0.9 0.9 0.9; 0 0 1; 1 0 0]);
title(sprintf('Z=%d 切片 (灰=流体, 蓝=固体, 红=边界)', z_slice-1));
xlabel('X'); ylabel('Y');
caxis([0 2]);

% Y方向切片
subplot(1,3,2);
y_slice = round(ny/2);
imagesc(squeeze(geom(:,y_slice,:))');
axis image; colormap([0.9 0.9 0.9; 0 0 1; 1 0 0]);
title(sprintf('Y=%d 切片', y_slice-1));
xlabel('X'); ylabel('Z');
caxis([0 2]);

% X方向切片
subplot(1,3,3);
x_slice = round(nx/2);
imagesc(squeeze(geom(x_slice,:,:))');
axis image; colormap([0.9 0.9 0.9; 0 0 1; 1 0 0]);
title(sprintf('X=%d 切片', x_slice-1));
xlabel('Y'); ylabel('Z');
caxis([0 2]);

sgtitle('Spacer Geometry Slices');

%% 4. 图3: 孔隙率验证 (沿Z方向)
figure('Name', 'Porosity Profile', 'Position', [350 300 600 400]);

porosity_z = zeros(nz, 1);
for k = 1:nz
    slice_type = geom(:,:,k);
    porosity_z(k) = sum(slice_type(:)==0) / (nx*ny);
end

plot(0:nz-1, porosity_z*100, 'b-o', 'LineWidth', 2);
xlabel('Z');
ylabel('Porosity (%)');
title('沿Z方向的孔隙率分布');
grid on;
fprintf('\n平均孔隙率: %.2f%%\n', mean(porosity_z)*100);

%% 5. 保存图片
saveas(1, 'geometry_3d.png');
saveas(2, 'geometry_slices.png');
saveas(3, 'porosity_profile.png');

%% 6. 保存为MAT文件（方便后续加载）
geometry_data = struct();
geometry_data.NX = nx;
geometry_data.NY = ny;
geometry_data.NZ = nz;
geometry_data.x = x;
geometry_data.y = y;
geometry_data.z = z;
geometry_data.type = type;  % 0=fluid, 1=solid, 2=boundary
geometry_data.solid_mask = (type == 1);  % 逻辑数组，true表示固体
geometry_data.boundary_mask = (type == 2);  % 逻辑数组，true表示边界
geometry_data.porosity = mean(porosity_z);

save('geometry.mat', '-struct', 'geometry_data');
fprintf('\n几何数据已保存: geometry.mat\n');
fprintf('  加载方式: geom = load(''geometry.mat'');\n');

fprintf('\n几何可视化完成！\n');
