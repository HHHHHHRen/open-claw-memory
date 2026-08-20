/*
 * RO Spacer LBM - 读取MATLAB几何版本
 * Compile: clang -O3 spacer_lbm.c -o spacer_lbm -lm
 * Run: ./spacer_lbm
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <stdint.h>

/* 最大网格尺寸（可根据需要调整） */
#define MAX_NX 500
#define MAX_NY 200
#define MAX_NZ 100
#define MAX_NT (MAX_NX*MAX_NY*MAX_NZ)
#define Q 27

/* LBM参数 */
const float tau = 0.5015f;

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

/* 全局变量 */
int NX, NY, NZ, NT;
float f[MAX_NT][Q], fcol[MAX_NT][Q];
float rho[MAX_NT], ux[MAX_NT], uy[MAX_NT], uz[MAX_NT];
char nodeType[MAX_NT];  /* 0=i, 1=s, 2=b, 3=o */

/* 辅助函数 */
inline int idx(int x, int y, int z) { return x + y * NX + z * NX * NY; }
inline int getX(int i) { return i % NX; }
inline int getY(int i) { return (i / NX) % NY; }
inline int getZ(int i) { return i / (NX * NY); }
inline int out(int x, int y, int z) { return x<0 || x>=NX || y<0 || y>=NY || z<0 || z>=NZ; }

/* ========== 从MATLAB读取几何 ========== */
int load_geometry(const char *filename) {
    FILE *fp = fopen(filename, "rb");
    if (!fp) {
        printf("错误: 无法打开 %s\n", filename);
        return 0;
    }
    
    int header[3];
    fread(header, sizeof(int), 3, fp);
    NX = header[0];
    NY = header[1];
    NZ = header[2];
    
    if (NX > MAX_NX || NY > MAX_NY || NZ > MAX_NZ) {
        printf("错误: 网格太大 (%dx%dx%d)，超过限制 (%dx%dx%d)\n", 
               NX, NY, NZ, MAX_NX, MAX_NY, MAX_NZ);
        fclose(fp);
        return 0;
    }
    
    NT = NX * NY * NZ;
    printf("从 %s 读取几何...\n", filename);
    printf("网格尺寸: %d x %d x d = %d 单元\n", NX, NY, NZ, NT);
    
    /* 读取节点类型 */
    uint8_t *buffer = (uint8_t*)malloc(NT * sizeof(uint8_t));
    fread(buffer, sizeof(uint8_t), NT, fp);
    fclose(fp);
    
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
        for (int j = 0; j < Q; j++) {
            fcol[i][j] = f[i][j] - (f[i][j] - feq[j]) / tau;
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
        rho[i] = r;
        ux[i] = u / r;
        uy[i] = v / r;
        uz[i] = w / r;
    }
}

void applyBoundary() {
    /* X方向周期 */
    for (int y = 0; y < NY; y++) {
        for (int z = 0; z < NZ; z++) {
            int inl = idx(0, y, z);
            int out = idx(NX-1, y, z);
            for (int j = 0; j < Q; j++) {
                if (e[j][0] > 0) f[inl][j] = fcol[out][j];
                if (e[j][0] < 0) f[out][j] = fcol[inl][j];
            }
        }
    }
    
    /* Y方向周期 */
    for (int x = 0; x < NX; x++) {
        for (int z = 0; z < NZ; z++) {
            int fr = idx(x, 0, z);
            int ba = idx(x, NY-1, z);
            for (int j = 0; j < Q; j++) {
                if (e[j][1] > 0) f[fr][j] = fcol[ba][j];
                if (e[j][1] < 0) f[ba][j] = fcol[fr][j];
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
            /* 初始化平衡分布 */
            computeFeq(i, feq);
            for (int j = 0; j < Q; j++) f[i][j] = feq[j];
        }
    }
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
    int maxStep = 1000;
    int outputInterval = 100;
    
    printf("\n开始仿真: maxStep=%d, tau=%.4f\n", maxStep, tau);
    printf("========================================\n");
    
    /* 主循环 */
    for (int step = 1; step <= maxStep; step++) {
        collide();
        stream();
        applyBoundary();
        computeMacro();
        
        if (step % 100 == 0) {
            printf("Step %d / %d\n", step, maxStep);
        }
        
        if (step % outputInterval == 0) {
            output(step);
        }
    }
    
    printf("========================================\n");
    printf("仿真完成!\n");
    printf("输出文件: spacer_flow_*.bin, spacer_flow_*.dat\n");
    printf("转换MAT: python3 bin2mat.py spacer_flow_0xxx.bin\n");
    
    return 0;
}
