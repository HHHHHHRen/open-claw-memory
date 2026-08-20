/*
 * RO Spacer LBM - 读取MATLAB几何版本（动态内存版）
 * Compile: clang -O3 spacer_lbm.c -o spacer_lbm -lm
 * Run: ./spacer_lbm [geometry.bin]
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <stdint.h>

#define Q 27

/* LBM参数与单位换算
 * 物理参数:
 *   dx_phys = 0.05 mm = 5.0e-5 m           <- 物理空间分辨率
 *   dt_phys = 1.0e-5 s = 10 μs             <- 物理时间步 (由 U0_lb=0.05 @ u_phys=0.25m/s 确定)
 *   目标物理流速 u_target = 0.25 m/s       <- 可调: 0.25, 0.5, 0.65 m/s
 * 
 * 体积力换算:
 *   体积力 Fx_lb (格子单位) 与物理流速 u_phys 的关系:
 *   Fx_lb = u_target * (tau - 0.5) / (scaling_factor)
 *   其中 scaling_factor 需要通过一次试算标定 (通常 0.1 ~ 0.5 范围内)
 *   
 *   实用标定方法:
 *   1. 先设 Fx = 1.0e-5，跑 5000 步，测量平均速度 u_measured
 *   2. 目标 Fx = Fx_current * (u_target / u_measured)
 *   3. 重新运行
 */
const float tau = 0.55f;                /* 增大粘度，提高稳定性 (原0.5015太接近0.5) */
const float u_target_phys = 0.25f;      /* 目标物理流速 (m/s), 可调 */
const float dx_phys = 5.0e-5f;          /* 0.05 mm */
const float dt_phys = 1.0e-5f;          /* 10 μs @ u=0.25m/s */
const float Fx = 1.0e-6f;               /* 减小体积力，保守起步 */

/* D3Q27权重 */
const double wgt[Q] = {
    8.0/27,
    2.0/27, 2.0/27, 2.0/27, 2.0/27, 2.0/27, 2.0/27,
    1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54,
    1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216
};

const int e[Q][3] = {
    {0,0,0}, {1,0,0}, {0,1,0}, {-1,0,0}, {0,-1,0}, {0,0,1}, {0,0,-1},
    {1,1,0}, {-1,1,0}, {-1,-1,0}, {1,-1,0}, {1,0,1}, {0,1,1}, {-1,0,1}, {0,-1,1},
    {1,0,-1}, {0,1,-1}, {-1,0,-1}, {0,-1,-1},
    {1,1,1}, {-1,1,1}, {-1,-1,1}, {1,-1,1}, {1,1,-1}, {-1,1,-1}, {-1,-1,-1}, {1,-1,-1}
};

const int oppo[Q] = {0,3,4,1,2,6,5,9,10,7,8,17,18,15,16,13,14,11,12,25,26,23,24,21,22,19,20};

/* 全局变量（运行时动态确定） */
int NX, NY, NZ, NT;
float (*f)[Q], (*fcol)[Q];      /* 动态分配: NT x Q */
float *rho, *ux, *uy, *uz;       /* 动态分配: NT */
char *nodeType;                  /* 动态分配: NT */

/* 辅助函数 */
inline int idx(int x, int y, int z) { return x + y * NX + z * NX * NY; }
inline int getX(int i) { return i % NX; }
inline int getY(int i) { return (i / NX) % NY; }
inline int getZ(int i) { return i / (NX * NY); }
inline int out(int x, int y, int z) { return x<0 || x>=NX || y<0 || y>=NY || z<0 || z>=NZ; }

/* ========== 动态内存分配 ========== */
int allocate_memory() {
    f = (float (*)[Q])calloc(NT * Q, sizeof(float));
    fcol = (float (*)[Q])calloc(NT * Q, sizeof(float));
    rho = (float *)calloc(NT, sizeof(float));
    ux = (float *)calloc(NT, sizeof(float));
    uy = (float *)calloc(NT, sizeof(float));
    uz = (float *)calloc(NT, sizeof(float));
    nodeType = (char *)calloc(NT, sizeof(char));
    
    if (!f || !fcol || !rho || !ux || !uy || !uz || !nodeType) {
        printf("错误: 内存分配失败 (需要 %.2f MB)\n", 
               (2.0 * NT * Q + 5.0 * NT) * sizeof(float) / (1024*1024));
        return 0;
    }
    return 1;
}

void free_memory() {
    free(f); free(fcol); free(rho); free(ux); free(uy); free(uz); free(nodeType);
}

/* ========== 从MATLAB读取几何 ========== */
int load_geometry(const char *filename) {
    FILE *fp = fopen(filename, "rb");
    if (!fp) {
        printf("错误: 无法打开 %s\n", filename);
        return 0;
    }
    
    /* 读取文件头 */
    int header[3];
    if (fread(header, sizeof(int), 3, fp) != 3) {
        printf("错误: 无法读取文件头\n");
        fclose(fp);
        return 0;
    }
    
    NX = header[0];
    NY = header[1];
    NZ = header[2];
    NT = NX * NY * NZ;
    
    printf("========================================\n");
    printf("文件头: %d x %d x %d = %d 单元\n", NX, NY, NZ, NT);
    
    /* 检查合理性 */
    if (NX <= 0 || NY <= 0 || NZ <= 0 || NT <= 0) {
        printf("错误: 无效的网格尺寸\n");
        fclose(fp);
        return 0;
    }
    
    /* 分配内存 */
    if (!allocate_memory()) {
        fclose(fp);
        return 0;
    }
    
    /* 读取节点类型 */
    uint8_t *buffer = (uint8_t*)malloc(NT * sizeof(uint8_t));
    if (!buffer) {
        printf("错误: 临时缓冲区分配失败\n");
        fclose(fp);
        return 0;
    }
    
    size_t nread = fread(buffer, sizeof(uint8_t), NT, fp);
    fclose(fp);
    
    if (nread != NT) {
        printf("错误: 数据不完整 (期望 %d, 实际 %zu)\n", NT, nread);
        free(buffer);
        return 0;
    }
    
    /* 转换为字符数组并统计 */
    int nSolid = 0, nBoundary = 0, nOutlet = 0, nFluid = 0;
    for (int i = 0; i < NT; i++) {
        switch (buffer[i]) {
            case 0: nodeType[i] = 'i'; nFluid++; break;
            case 1: nodeType[i] = 's'; nSolid++; break;
            case 2: nodeType[i] = 'b'; nBoundary++; break;
            case 3: nodeType[i] = 'o'; nOutlet++; break;
            default: nodeType[i] = 'i'; nFluid++;
        }
    }
    
    /* 标记边界节点: 流体('i')紧邻固体('s') -> 'b' */
    for (int i = 0; i < NT; i++) {
        if (nodeType[i] != 'i') continue;
        
        int x = getX(i), y = getY(i), z = getZ(i);
        int is_boundary = 0;
        
        for (int j = 1; j < Q; j++) {  /* skip (0,0,0) */
            int xb = x + e[j][0];
            int yb = y + e[j][1];
            int zb = z + e[j][2];
            if (out(xb, yb, zb)) continue;
            if (nodeType[idx(xb, yb, zb)] == 's') {
                is_boundary = 1;
                break;
            }
        }
        
        if (is_boundary) {
            nodeType[i] = 'b';
            nBoundary++;
            nFluid--;
        }
    }
    
    free(buffer);
    
    float porosity = 100.0f * nFluid / NT;
    printf("几何统计:\n");
    printf("  流体: %d (%.1f%%)\n", nFluid, porosity);
    printf("  固体: %d (%.1f%%)\n", nSolid, 100.0f*nSolid/NT);
    printf("  边界: %d (%.1f%%)\n", nBoundary, 100.0f*nBoundary/NT);
    printf("  出口: %d (%.1f%%)\n", nOutlet, 100.0f*nOutlet/NT);
    
    return 1;
}

/* ========== 输出函数 ========== */
void output_binary(int step) {
    char fname[256];
    sprintf(fname, "spacer_flow_%04d.bin", step);
    FILE *fp = fopen(fname, "wb");
    int header[4] = {NX, NY, NZ, 4};
    fwrite(header, sizeof(int), 4, fp);
    fwrite(rho, sizeof(float), NT, fp);
    fwrite(ux, sizeof(float), NT, fp);
    fwrite(uy, sizeof(float), NT, fp);
    fwrite(uz, sizeof(float), NT, fp);
    fclose(fp);
    printf("  [BIN] Saved: %s\n", fname);
}

void output_tecplot(int step) {
    char fname[256];
    sprintf(fname, "spacer_flow_%04d.dat", step);
    FILE *fp = fopen(fname, "w");
    fprintf(fp, "TITLE=\"RO Spacer LBM - Step %d\"\n", step);
    fprintf(fp, "VARIABLES=\"X\",\"Y\",\"Z\",\"RHO\",\"U\",\"V\",\"W\"\n");
    fprintf(fp, "ZONE T=\"FlowField\", I=%d, J=%d, K=%d, F=POINT\n", NX, NY, NZ);
    
    for (int i = 0; i < NT; i++) {
        if (nodeType[i] == 's')
            fprintf(fp, "%d %d %d 1.0 0.0 0.0 0.0\n", getX(i), getY(i), getZ(i));
        else
            fprintf(fp, "%d %d %d %.6f %.6f %.6f %.6f\n", 
                    getX(i), getY(i), getZ(i), rho[i], ux[i], uy[i], uz[i]);
    }
    fclose(fp);
    printf("  [DAT] Saved: %s\n", fname);
}

void output(int step) {
    printf("Output at step %d:\n", step);
    output_binary(step);
    output_tecplot(step);
}

/* ========== LBM核心函数 ========== */
void computeFeq(int id, float *feq) {
    float rh = rho[id];
    float u = ux[id];
    float v = uy[id];
    float w = uz[id];
    float u2 = u*u + v*v + w*w;
    
    for (int j = 0; j < Q; j++) {
        float eu = e[j][0]*u + e[j][1]*v + e[j][2]*w;
        feq[j] = rh * wgt[j] * (1.0f + 3.0f*eu + 4.5f*eu*eu - 1.5f*u2);
    }
}

void collide() {
    float feq[Q];
    for (int i = 0; i < NT; i++) {
        if (nodeType[i] == 's') continue;
        computeFeq(i, feq);
        float rh = rho[i];
        for (int j = 0; j < Q; j++) {
            /* 碰撞 + 体积力 (Guo forcing scheme) */
            float force = wgt[j] * rh * (3.0f * e[j][0] * Fx);
            fcol[i][j] = f[i][j] - (f[i][j] - feq[j]) / tau + force;
        }
    }
}

void stream() {
    for (int i = 0; i < NT; i++) {
        if (nodeType[i] == 's' || nodeType[i] == 'o') continue;
        
        int x = getX(i), y = getY(i), z = getZ(i);
        char nt = nodeType[i];
        
        for (int j = 0; j < Q; j++) {
            int xp = x - e[j][0];
            int yp = y - e[j][1];
            int zp = z - e[j][2];
            
            if (nt == 'i') {
                if (!out(xp, yp, zp))
                    f[i][j] = fcol[idx(xp, yp, zp)][j];
            } else if (nt == 'b') {
                if (out(xp, yp, zp) || nodeType[idx(xp, yp, zp)] == 's')
                    f[i][j] = fcol[i][oppo[j]];
                else
                    f[i][j] = fcol[idx(xp, yp, zp)][j];
            }
        }
    }
}

void computeMacro() {
    for (int i = 0; i < NT; i++) {
        if (nodeType[i] == 's') continue;
        
        float r = 0, u = 0, v = 0, w = 0;
        for (int j = 0; j < Q; j++) {
            r += f[i][j];
            u += e[j][0] * f[i][j];
            v += e[j][1] * f[i][j];
            w += e[j][2] * f[i][j];
        }
        
        /* 保护：防止 rho 接近 0 */
        if (r < 1e-6f) {
            r = 1.0f;  /* 重置为参考密度 */
            u = v = w = 0;
            printf("警告: 节点 %d (x=%d,y=%d,z=%d) 密度异常,已重置\n", 
                   i, getX(i), getY(i), getZ(i));
        }
        
        rho[i] = r;
        /* Guo forcing: 速度需加上半步力修正 */
        ux[i] = (u + 0.5f * Fx * r) / r;
        uy[i] = v / r;
        uz[i] = w / r;
    }
}

void applyBoundary() {
    /* X方向: 周期边界 (只应用于非固体节点) */
    for (int y = 0; y < NY; y++) {
        for (int z = 0; z < NZ; z++) {
            int inl = idx(0, y, z);
            int out = idx(NX-1, y, z);
            for (int j = 0; j < Q; j++) {
                if (e[j][0] > 0 && nodeType[inl] != 's') 
                    f[inl][j] = fcol[out][j];
                if (e[j][0] < 0 && nodeType[out] != 's') 
                    f[out][j] = fcol[inl][j];
            }
        }
    }
    
    /* Y方向周期 (只应用于非固体节点) */
    for (int x = 0; x < NX; x++) {
        for (int z = 0; z < NZ; z++) {
            int fr = idx(x, 0, z);
            int ba = idx(x, NY-1, z);
            for (int j = 0; j < Q; j++) {
                if (e[j][1] > 0 && nodeType[fr] != 's') 
                    f[fr][j] = fcol[ba][j];
                if (e[j][1] < 0 && nodeType[ba] != 's') 
                    f[ba][j] = fcol[fr][j];
            }
        }
    }
    
    /* Z方向壁面（反弹） */
    for (int x = 0; x < NX; x++) {
        for (int y = 0; y < NY; y++) {
            int dn = idx(x, y, 0);
            int up = idx(x, y, NZ-1);
            for (int j = 0; j < Q; j++) {
                if (e[j][2] > 0) f[dn][j] = fcol[dn][oppo[j]];
                if (e[j][2] < 0) f[up][j] = fcol[up][oppo[j]];
            }
        }
    }
}

/* ========== 初始化 ========== */
void init() {
    float feq[Q];
    for (int i = 0; i < NT; i++) {
        rho[i] = 1.0f;
        ux[i] = uy[i] = uz[i] = 0.0f;
        
        if (nodeType[i] == 's') {
            for (int j = 0; j < Q; j++) f[i][j] = 0.0f;
        } else {
            computeFeq(i, feq);
            for (int j = 0; j < Q; j++) f[i][j] = feq[j];
        }
    }
}

/* ========== 统计平均速度（用于标定 Fx） ========== */
float getAverageVelocity() {
    double u_sum = 0.0;
    double u_sq_sum = 0.0;
    int n_fluid = 0;
    
    for (int i = 0; i < NT; i++) {
        if (nodeType[i] == 's') continue;
        u_sum += ux[i];
        u_sq_sum += ux[i] * ux[i];
        n_fluid++;
    }
    
    if (n_fluid == 0) return 0.0f;
    
    float u_mean = (float)(u_sum / n_fluid);
    float u_rms = (float)sqrt(u_sq_sum / n_fluid);
    
    /* 换算物理速度 */
    float u_mean_phys = u_mean * dx_phys / dt_phys;
    float u_rms_phys = u_rms * dx_phys / dt_phys;
    
    printf("   格子平均速度: %.6f | RMS: %.6f | 物理平均: %.4f m/s | 物理RMS: %.4f m/s\n",
           u_mean, u_rms, u_mean_phys, u_rms_phys);
    
    return u_mean_phys;
}

/* ========== 主函数 ========== */
int main(int argc, char *argv[]) {
    const char *geom_file = (argc > 1) ? argv[1] : "geometry.bin";
    
    /* 读取几何 */
    if (!load_geometry(geom_file)) {
        printf("用法: %s [geometry.bin]\n", argv[0]);
        return 1;
    }
    
    /* 初始化 */
    init();
    
    /* 仿真参数 */
    int maxStep = 5000;
    int outputInterval = 500;
    int statsInterval = 500;   /* 每500步输出一次平均速度 */
    
    printf("\n开始仿真: maxStep=%d, tau=%.4f, Fx=%.2e\n", maxStep, tau, Fx);
    printf("目标物理流速: %.2f m/s\n", u_target_phys);
    printf("========================================\n");
    
    /* 主循环 */
    for (int step = 1; step <= maxStep; step++) {
        collide();
        stream();
        applyBoundary();
        computeMacro();
        
        if (step % statsInterval == 0) {
            printf("Step %d / %d:\n", step, maxStep);
            getAverageVelocity();
        }
        
        if (step % outputInterval == 0) {
            output(step);
        }
    }
    
    printf("========================================\n");
    printf("仿真完成!\n");
    printf("\n标定提示:\n");
    printf("  如果最终平均速度 u_meas = X m/s，而目标是 %.2f m/s，\n", u_target_phys);
    printf("  则新的 Fx = %.2e * (%.2f / X)\n", Fx, u_target_phys);
    printf("  例如: u_meas=0.10 m/s 时, Fx_new = %.2e * (%.2f/0.10) = %.2e\n",
           Fx, u_target_phys, Fx * u_target_phys / 0.10f);
    printf("输出文件: spacer_flow_*.bin, spacer_flow_*.dat\n");
    
    /* 清理 */
    free_memory();
    
    return 0;
}
