%% RO Spacer 3D Flow Visualization
% Read spacer_flow_*.dat and geometry.dat

clear; clc; close all;

%% 1. Read flow data
filename = 'spacer_flow_100.dat';  % Change to your file

% Read data (skip first 3 header lines)
fid = fopen(filename, 'r');
for i = 1:3
    fgetl(fid);
end
data = textscan(fid, '%f %f %f %f %f %f');
fclose(fid);

X = data{1};
Y = data{2};
Z = data{3};
U = data{4};
V = data{5};
W = data{6};

% Get grid size
NX = max(X) + 1;
NY = max(Y) + 1;
NZ = max(Z) + 1;

fprintf('Grid size: %d x %d x %d\n', NX, NY, NZ);
fprintf('Total cells: %d\n', length(X));

%% 2. Reshape to 3D arrays
U_3D = reshape(U, [NX, NY, NZ]);
V_3D = reshape(V, [NX, NY, NZ]);
W_3D = reshape(W, [NX, NY, NZ]);

U_3D = permute(U_3D, [2, 1, 3]);
V_3D = permute(V_3D, [2, 1, 3]);
W_3D = permute(W_3D, [2, 1, 3]);

Speed = sqrt(U_3D.^2 + V_3D.^2 + W_3D.^2);

%% 3. Read geometry (optional)
has_geometry = false;
try
    fid = fopen('geometry.dat', 'r');
    for i = 1:3
        fgetl(fid);
    end
    geom = textscan(fid, '%f %f %f %f');
    fclose(fid);
    
    X_geom = geom{1};
    Y_geom = geom{2};
    Z_geom = geom{3};
    Type_geom = geom{4};
    
    solid_mask = (Type_geom == 1);
    X_solid = X_geom(solid_mask);
    Y_solid = Y_geom(solid_mask);
    Z_solid = Z_geom(solid_mask);
    
    has_geometry = true;
    fprintf('Geometry loaded, solid cells: %d\n', sum(solid_mask));
catch
    fprintf('Warning: geometry.dat not found, showing flow only\n');
end

%% 4. Figure 1: 3D Velocity Vectors
figure('Name', '3D Velocity Field', 'Position', [100 100 1200 800]);

skip = 5;
[x_idx, y_idx, z_idx] = meshgrid(1:skip:NX, 1:skip:NY, 1:skip:NZ);
sample_idx = sub2ind([NY, NX, NZ], y_idx(:), x_idx(:), z_idx(:));

X_sample = X(sample_idx);
Y_sample = Y(sample_idx);
Z_sample = Z(sample_idx);
U_sample = U(sample_idx);
V_sample = V(sample_idx);
W_sample = W(sample_idx);

quiver3(X_sample, Y_sample, Z_sample, U_sample*10, V_sample*10, W_sample*10, 
        'Color', [0.2 0.4 0.8], 'LineWidth', 0.8);
hold on;

if has_geometry
    solid_skip = 3;
    solid_sample = 1:solid_skip:length(X_solid);
    scatter3(X_solid(solid_sample), Y_solid(solid_sample), Z_solid(solid_sample), 
             5, 'r', 'filled');
end

xlabel('X'); ylabel('Y'); zlabel('Z');
title('3D Velocity Field');
axis equal tight;
grid on;
view(45, 30);

%% 5. Figure 2: Velocity Isosurfaces
figure('Name', 'Velocity Isosurface', 'Position', [150 150 1200 800]);

[x_grid, y_grid, z_grid] = meshgrid(0:NX-1, 0:NY-1, 0:NZ-1);

speed_threshold = 0.05;
p = patch(isosurface(x_grid, y_grid, z_grid, Speed, speed_threshold));
isonormals(x_grid, y_grid, z_grid, Speed, p);
p.FaceColor = 'red';
p.EdgeColor = 'none';
p.FaceAlpha = 0.5;

hold on;

speed_threshold_low = 0.01;
p2 = patch(isosurface(x_grid, y_grid, z_grid, Speed, speed_threshold_low));
isonormals(x_grid, y_grid, z_grid, Speed, p2);
p2.FaceColor = 'blue';
p2.EdgeColor = 'none';
p2.FaceAlpha = 0.2;

camlight;
lighting gouraud;

xlabel('X'); ylabel('Y'); zlabel('Z');
title('Velocity Isosurfaces');
axis equal tight;
grid on;
view(45, 30);

%% 6. Figure 3: Slices
figure('Name', 'Velocity Slices', 'Position', [200 200 1400 500]);

subplot(1, 3, 1);
slice(X, Y, Z, Speed, [NX/2], [], []);
shading interp;
axis equal tight;
xlabel('X'); ylabel('Y'); zlabel('Z');
title('X-Z Plane');
view(0, 0);
colorbar;
colormap jet;

subplot(1, 3, 2);
slice(X, Y, Z, Speed, [], [NY/2], []);
shading interp;
axis equal tight;
xlabel('X'); ylabel('Y'); zlabel('Z');
title('Y-Z Plane');
view(90, 0);
colorbar;

subplot(1, 3, 3);
slice(X, Y, Z, Speed, [], [], [NZ/2]);
shading interp;
axis equal tight;
xlabel('X'); ylabel('Y'); zlabel('Z');
title('X-Y Plane');
view(0, 90);
colorbar;

%% 7. Figure 4: Statistics
figure('Name', 'Velocity Statistics', 'Position', [250 250 800 400]);

subplot(1, 2, 1);
histogram(Speed(:), 50);
xlabel('Velocity Magnitude');
ylabel('Count');
title('Velocity Distribution');

subplot(1, 2, 2);
max_u = max(abs(U));
max_v = max(abs(V));
max_w = max(abs(W));
bar([max_u, max_v, max_w]);
set(gca, 'XTickLabel', {'U', 'V', 'W'});
ylabel('Max Velocity');
title('Max Velocity Components');

fprintf('\nStatistics:\n');
fprintf('Max speed: %.4f\n', max(Speed(:)));
fprintf('Mean speed: %.4f\n', mean(Speed(:)));
fprintf('Max U: %.4f, Max V: %.4f, Max W: %.4f\n', max_u, max_v, max_w);

%% 8. Save figures
saveas(figure(1), 'velocity_3d_vector.png');
saveas(figure(2), 'velocity_isosurface.png');
saveas(figure(3), 'velocity_slices.png');
saveas(figure(4), 'velocity_stats.png');
fprintf('\nFigures saved!\n');
