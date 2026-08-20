%% Simple Flow Visualization
% Quick and dirty 3D flow plot

clear; clc; close all;

% Read data
fid = fopen('spacer_flow_100.dat', 'r');
fgetl(fid); fgetl(fid); fgetl(fid);
data = textscan(fid, '%f %f %f %f %f %f');
fclose(fid);

X = data{1}; Y = data{2}; Z = data{3};
U = data{4}; V = data{5}; W = data{6};

% Grid size
NX = max(X)+1; NY = max(Y)+1; NZ = max(Z)+1;
fprintf('Grid: %d x %d x %d\n', NX, NY, NZ);

%% Plot 1: Velocity vectors (sampled)
figure('Position', [100 100 1000 700]);

% Sample every 10 points to avoid clutter
idx = 1:10:length(X);
quiver3(X(idx), Y(idx), Z(idx), U(idx)*20, V(idx)*20, W(idx)*20, 'b');

xlabel('X'); ylabel('Y'); zlabel('Z');
title('Velocity Field (sampled)');
axis equal tight; grid on;
view(45, 30);

%% Plot 2: Speed contours at Z mid-plane
figure('Position', [150 150 800 600]);

Speed = sqrt(U.^2 + V.^2 + W.^2);

% Extract middle Z plane
z_mid = round(NZ/2);
mask = (Z == z_mid);

scatter(X(mask), Y(mask), 10, Speed(mask), 'filled');
axis equal tight;
xlabel('X'); ylabel('Y');
title(sprintf('Speed at Z=%d (middle plane)', z_mid));
colorbar; colormap jet;

%% Stats
fprintf('Max speed: %.4f\n', max(Speed));
fprintf('Mean speed: %.4f\n', mean(Speed));
