%% RO隔网压降分析 - 精简版（体积力法 + 无量纲数）
% 适用于：周期性边界 + Guo forcing scheme + 编织隔网LBM结果
% 作者：Kimi Claw for 美丽的桃花公主
% 维度匹配：geometry.mat solid是(Y,X,Z)，flow mat是(Z,Y,X)

clear; clc; close all;

%% ========== 参数设置 ==========
d_fiber_phys = 1.0e-3;      % m，纤维直径
dx_phys = 0.05e-3;          % m，网格尺寸
tau = 0.505;                % 必须与LBM代码一致
Fx_lb = 1.0e-4;             % 体积力 [lb]
rho_phys = 1000.0;          % kg/m³，水密度
nu_phys = 1.0e-6;           % m²/s，水运动粘度
cs2 = 1.0/3.0;              % LBM声速平方

%% ========== 加载数据 ==========
flow = load('spacer_flow_10000.mat');
geom = load('geometry.mat');

% 维度对齐 (Z,Y,X) -> (Y,X,Z)
ux = permute(flow.ux, [2, 3, 1]);
rho = permute(flow.rho, [2, 3, 1]);
solid = geom.solid;

[NY, NX, NZ] = size(solid);
NT = NX*NY*NZ;
Lx_phys = NX * dx_phys;

fluid_mask = ~solid;
n_fluid = sum(fluid_mask(:));
porosity = n_fluid / NT;

%% ========== 基础统计 ==========
ux_fluid = ux(fluid_mask);
rho_fluid = rho(fluid_mask);

U_avg = mean(ux_fluid);                     % 格子平均速度
U_max = max(abs(ux_fluid));
rho_mean = mean(rho_fluid);

% 格子粘度
nu_lb = cs2 * (tau - 0.5);

% 水力直径 (湿表面积法)
neighbors = [1,0,0; -1,0,0; 0,1,0; 0,-1,0; 0,0,1; 0,0,-1];
A_wetted = 0;
for k = 1:NZ
    for j = 1:NY
        for i = 1:NX
            if ~solid(j,i,k), continue; end
            for d = 1:6
                ni = mod(i+neighbors(d,1)-1, NX)+1;
                nj = mod(j+neighbors(d,2)-1, NY)+1;
                nk = mod(k+neighbors(d,3)-1, NZ)+1;
                if ~solid(nj,ni,nk), A_wetted = A_wetted + 1; end
            end
        end
    end
end
A_wetted = A_wetted/2;
V_void = n_fluid;
D_h_lb = 4 * V_void / A_wetted;

% 雷诺数
Re_h = abs(U_avg) * D_h_lb / nu_lb;

%% ========== 压降计算：体积力法 ==========
% 周期性边界理论：dp/dx = rho * Fx
dpdx_lb = rho_mean * Fx_lb;         % 格子单位压降梯度
dP_lb = dpdx_lb * NX;               % 格子单位全程压降

% 物理单位换算
dt = nu_lb * dx_phys^2 / nu_phys;   % 时间步长
Fx_phys = Fx_lb * dx_phys / dt^2;   % 物理体积力

dPdx_phys = rho_phys * Fx_phys;     % Pa/m
dP_total_phys = dPdx_phys * Lx_phys;% Pa
dP_bar = dP_total_phys / 1e5;       % bar
dP_kPa = dP_total_phys / 1e3;       % kPa

%% ========== 无量纲压降参数 ==========
% 物理速度
U_avg_phys = U_avg * dx_phys / dt;

% 1. 欧拉数 (Euler number) - 压降与动能之比
Eu = dP_total_phys / (rho_phys * U_avg_phys^2);

% 2. Fanning摩擦因子
% f = ΔP * D_h / (2 * ρ * U² * L)
f_fanning = dP_lb * D_h_lb / (2 * rho_mean * U_avg^2 * NX);
% 或物理单位等价：f = dP_total_phys * D_h_phys / (2 * rho_phys * U_avg_phys^2 * Lx_phys)

% 3. Darcy摩擦因子 (λ = 4f)
darcy_lambda = 4 * f_fanning;

% 4. f·Re 乘积（多孔介质层流经典关联）
f_Re = f_fanning * Re_h;

% 5. 无量纲压降系数 (K = ΔP / (0.5·ρ·U²))
K_coeff = dP_total_phys / (0.5 * rho_phys * U_avg_phys^2);

%% ========== 输出结果 ==========
fprintf('╔══════════════════════════════════════════╗\n');
fprintf('║     RO隔网压降分析 - 体积力法             ║\n');
fprintf('╠══════════════════════════════════════════╣\n');
fprintf('║ 几何参数                                 ║\n');
fprintf('║   通道长度 Lx = %.3f mm                ║\n', Lx_phys*1e3);
fprintf('║   水力直径 Dh = %.2f lb (%.3f mm)     ║\n', D_h_lb, D_h_lb*dx_phys*1e3);
fprintf('║   孔隙率 ε   = %.4f (%.2f%%)           ║\n', porosity, porosity*100);
fprintf('║   纤维直径 d = %.1f lb (%.2f mm)       ║\n', d_fiber_phys/dx_phys, d_fiber_phys*1e3);
fprintf('╠══════════════════════════════════════════╣\n');
fprintf('║ 流动参数                                 ║\n');
fprintf('║   平均速度 U = %.6f lb                ║\n', U_avg);
fprintf('║            = %.4f m/s = %.2f mm/s     ║\n', U_avg_phys, U_avg_phys*1e3);
fprintf('║   最大速度   = %.6f lb                ║\n', U_max);
fprintf('║   密度 ρ     = %.6f lb               ║\n', rho_mean);
fprintf('║   运动粘度 ν = %.6f lb               ║\n', nu_lb);
fprintf('║   雷诺数 Re  = %.2f                    ║\n', Re_h);
fprintf('╠══════════════════════════════════════════╣\n');
fprintf('║ 压降结果                                 ║\n');
fprintf('║   压降梯度   = %.2f Pa/m              ║\n', dPdx_phys);
fprintf('║   全程压降   = %.2f Pa                ║\n', dP_total_phys);
fprintf('║             = %.4f kPa                ║\n', dP_kPa);
fprintf('║             = %.6f bar                ║\n', dP_bar);
fprintf('╠══════════════════════════════════════════╣\n');
fprintf('║ 无量纲参数                               ║\n');
fprintf('║   欧拉数 Eu   = %.2f                  ║\n', Eu);
fprintf('║   Fanning f   = %.5f                 ║\n', f_fanning);
fprintf('║   Darcy λ     = %.5f                 ║\n', darcy_lambda);
fprintf('║   f·Re        = %.2f                  ║\n', f_Re);
fprintf('║   阻力系数 K  = %.2f                  ║\n', K_coeff);
fprintf('╚══════════════════════════════════════════╝\n');

%% ========== 与文献对比 ==========
fprintf('\n========== 文献对比参考 ==========\n');
fprintf('空管层流理论 (Hagen-Poiseuille):  f·Re = 16\n');
fprintf('空管湍流 (Blasius):              f = 0.0791·Re^(-0.25)\n');
fprintf('编织隔网典型范围:                f·Re = 50-400\n');
fprintf('你的结果:                       f·Re = %.2f\n', f_Re);

if f_Re > 16 && f_Re < 500
    fprintf('→ f·Re 落在典型多孔介质层流范围 ✅\n');
else
    fprintf('→ f·Re 偏离典型范围，检查参数设定 ⚠️\n');
end

%% ========== 保存结果 ==========
results = struct();
results.dP_Pa = dP_total_phys;
results.dP_kPa = dP_kPa;
results.dP_bar = dP_bar;
results.Eu = Eu;
results.f_fanning = f_fanning;
results.darcy_lambda = darcy_lambda;
results.f_Re = f_Re;
results.K_coeff = K_coeff;
results.Re_h = Re_h;
results.U_avg_m_s = U_avg_phys;
results.D_h_mm = D_h_lb * dx_phys * 1e3;
results.porosity = porosity;

save('pressure_drop_nondim.mat', '-struct', 'results');
fprintf('\n结果已保存: pressure_drop_nondim.mat\n');
