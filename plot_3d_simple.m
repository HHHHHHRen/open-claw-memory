%% Simple 3D Flow Visualization (Low Memory)
clear; clc;

% Read data
fid = fopen('spacer_flow_100.dat', 'r');
fgetl(fid); fgetl(fid); fgetl(fid);
data = textscan(fid, '%f %f %f %f %f %f');
fclose(fid);

X = data{1}; Y = data{2}; Z = data{3};
U = data{4}; V = data{5}; W = data{6};
Speed = sqrt(U.^2 + V.^2 + W.^2);

% Sample every 50 points to avoid memory issue
idx = 1:50:length(X);

%% 3D Scatter (color = speed)
figure('Position', [100 100 1000 700]);
scatter3(X(idx), Y(idx), Z(idx), 10, Speed(idx), 'filled');
colorbar; colormap jet;
xlabel('X'); ylabel('Y'); zlabel('Z');
title('3D Flow Field (color = speed magnitude)');
axis equal tight; grid on;
view(45, 30);

fprintf('Max speed: %.4f\n', max(Speed));
fprintf('Plotted %d points (sampled)\n', length(idx));
