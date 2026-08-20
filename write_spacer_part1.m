%% RO 菱形编织隔网 LBM - CUDA 完整代码
%% 替换原来的简单柱体生成，使用3个cross的菱形编织隔网
%% 边界条件改为周期性

clear; clc;

%% 写入 CUDA 代码文件
fid = fopen('spacer_lbm.cu', 'w');

fprintf(fid, '#include <map>\n');
fprintf(fid, '#include "cuda.h"\n');
fprintf(fid, '#include "cuda_runtime.h"\n');
fprintf(fid, '#include "device_launch_parameters.h"\n');
fprintf(fid, '#include <string>\n');
fprintf(fid, '#include <iostream>\n');
fprintf(fid, '#include <fstream>\n');
fprintf(fid, '#include <sstream>\n');
fprintf(fid, '#include <math.h>\n');
fprintf(fid, '#include <cmath>\n');
fprintf(fid, '#include <cstdlib>\n');
fprintf(fid, '#include <vector>\n');
fprintf(fid, '#include <iomanip>\n');
fprintf(fid, '#include <algorithm>\n');
fprintf(fid, '#include <stdlib.h>\n');
fprintf(fid, '#include <time.h>\n\n');

fprintf(fid, '#define D 3\n');
fprintf(fid, '#define Q 27\n');
fprintf(fid, '#define U 0.1\n');
fprintf(fid, '#define e_mac 2\n');
fprintf(fid, '#define tau_mac 0.5015\n\n');

fprintf(fid, 'using namespace std;\n\n');

fprintf(fid, 'const int angle = 0;\n');
fprintf(fid, 'const string HStype = "CS";\n');
fprintf(fid, 'const int BB = 0;\n\n');

%% ========== 关键修改1：网格尺寸 ==========
fprintf(fid, '// === 隔网几何参数 ===\n');
fprintf(fid, 'const float dx = 0.05f;          // mm\n');
fprintf(fid, 'const float pitch = 4.0f;        // mm，节距\n');
fprintf(fid, 'const float d_fiber = 1.0f;      // mm，纤维直径\n');
fprintf(fid, 'const float r_fiber = 0.5f;      // mm，纤维半径\n');
fprintf(fid, 'const float d_node = 1.22f;      // mm，节点直径\n');
fprintf(fid, 'const float r_node = 0.61f;      // mm，节点半径\n');
fprintf(fid, 'const float diamond_diag = pitch * sqrtf(2.0f); // ≈5.657 mm\n');
fprintf(fid, 'const int num_cross = 3;         // X方向3个cross\n\n');

fprintf(fid, '// 计算域尺寸（格点数）\n');
fprintf(fid, 'const int NX = 339;   // round(3 * 5.657 / 0.05)\n');
fprintf(fid, 'const int NY = 113;   // round(5.657 / 0.05)\n');
fprintf(fid, 'const int NZ = 40;    // round(2.0 / 0.05)\n');
fprintf(fid, 'const int NT = NX * NY * NZ;\n\n');

fprintf(fid, 'const int threadsPerBlock = 128;\n');
fprintf(fid, 'const int blocksPerGrid = (NT + threadsPerBlock - 1) / threadsPerBlock;\n\n');

%% 全局变量声明
fprintf(fid, '// CPU 端的全局变量\n');
fprintf(fid, 'float* h_ux; float* h_uy; float* h_uz;\n');
fprintf(fid, 'float* h_uxA; float* h_uyA; float* h_uzA;\n');
fprintf(fid, 'float* h_TX; float* h_TY; float* h_TXY; float* h_TKE;\n');
fprintf(fid, 'float* h_rho;\n');
fprintf(fid, 'char* h_nodeType;\n\n');

fprintf(fid, 'cudaError_t err;\n');
fprintf(fid, 'inline void printCudaError(string funcName) {\n');
fprintf(fid, '    err = cudaGetLastError();\n');
fprintf(fid, '    if (err != cudaSuccess) {\n');
fprintf(fid, '        cout << funcName << " : " << cudaGetErrorString(err) << endl;\n');
fprintf(fid, '    }\n');
fprintf(fid, '}\n\n');

%% struct varb
fprintf(fid, 'struct varb {\n');
fprintf(fid, '    float* fval[Q]; float* fcol[Q];\n');
fprintf(fid, '    float* rho; float* ux; float* uy; float* uz;\n');
fprintf(fid, '    float* uxA; float* uyA; float* uzA;\n');
fprintf(fid, '    float* TX; float* TY; float* TXY; float* TKE;\n');
fprintf(fid, '    char* nodeType;\n');
fprintf(fid, '};\n\n');

fprintf(fid, '__constant__ varb d[1];\n');
fprintf(fid, 'varb dVar;\n\n');

%% constant memory
fprintf(fid, '__constant__ double w[Q];\n');
fprintf(fid, '__constant__ float eP[8];\n');
fprintf(fid, '__constant__ int eUnit[Q * D];\n');
fprintf(fid, '__constant__ float ePhy[Q * D];\n');
fprintf(fid, '__constant__ int oppoDir[Q];\n');
fprintf(fid, '__constant__ int N[4];\n');
fprintf(fid, '__constant__ float S[Q];\n\n');

%% 函数声明
fprintf(fid, 'void init(); void freeMem();\n');
fprintf(fid, 'void output(int s); void outputAver(int s);\n\n');

fprintf(fid, 'inline int getZ(const int i) { return i / (NX * NY); }\n');
fprintf(fid, 'inline int getX(const int i) { return i %% NX; }\n');
fprintf(fid, 'inline int getY(const int i) { return (i - NX*NY * getZ(i)) / NX; }\n');
fprintf(fid, 'inline int h_getIndex(int x, int y, int z) { return (x + y * NX + z * NX*NY); }\n\n');

%% kernel 声明
fprintf(fid, '__global__ void initDev();\n');
fprintf(fid, '__global__ void initFval();\n');
fprintf(fid, '__global__ void collideMRT();\n');
fprintf(fid, '__global__ void resetAverage();\n');
fprintf(fid, '__global__ void streamAmacro();\n');
fprintf(fid, '__global__ void streamAmacroAver();\n');
fprintf(fid, '__global__ void boundaryPeriodicX();\n');
fprintf(fid, '__global__ void boundaryPeriodicY();\n');
fprintf(fid, '__global__ void boundaryWallZ();\n');
fprintf(fid, '__global__ void error(int* d_flag);\n\n');

fprintf(fid, 'int* h_flag; int* d_flag;\n');
fprintf(fid, 'const int timespan = 60000;\n\n');

fclose(fid);

fprintf('声明部分写入完成\n');
