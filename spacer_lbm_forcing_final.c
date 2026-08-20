/*
 * RO Spacer LBM - 体积力驱动最终版
 * Guo forcing scheme + 全周期边界 (X/Y/Z)
 * 这是多孔介质流动的标准做法
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <stdint.h>

#define Q 27

/* 可调参数 */
const float tau = 0.505f;       /* 低粘度 */
const float Fx = 2.0e-5f;       /* 体积力 - 调整这个控制速度 */

const double wgt[Q] = {8.0/27,
    2.0/27,2.0/27,2.0/27,2.0/27,2.0/27,2.0/27,
    1.0/54,1.0/54,1.0/54,1.0/54,1.0/54,1.0/54,1.0/54,1.0/54,1.0/54,1.0/54,1.0/54,1.0/54,
    1.0/216,1.0/216,1.0/216,1.0/216,1.0/216,1.0/216,1.0/216,1.0/216};

const int e[Q][3] = {
    {0,0,0},{1,0,0},{0,1,0},{-1,0,0},{0,-1,0},{0,0,1},{0,0,-1},
    {1,1,0},{-1,1,0},{-1,-1,0},{1,-1,0},{1,0,1},{0,1,1},{-1,0,1},{0,-1,1},
    {1,0,-1},{0,1,-1},{-1,0,-1},{0,-1,-1},
    {1,1,1},{-1,1,1},{-1,-1,1},{1,-1,1},{1,1,-1},{-1,1,-1},{-1,-1,-1},{1,-1,-1}
};
const int oppo[Q] = {0,3,4,1,2,6,5,9,10,7,8,17,18,15,16,13,14,11,12,25,26,23,24,21,22,19,20};

int NX, NY, NZ, NT;
float (*f)[Q], (*fcol)[Q], *rho, *ux, *uy, *uz;
char *nodeType;  /* 's'=固体, 'f'=流体 */

/* 周期索引 */
inline int idx(int x, int y, int z) {
    x = (x + NX) % NX;
    y = (y + NY) % NY;
    z = (z + NZ) % NZ;
    return x + y*NX + z*NX*NY;
}
inline int getX(int i) { return i % NX; }
inline int getY(int i) { return (i/NX) % NY; }
inline int getZ(int i) { return i/(NX*NY); }

int allocate() {
    f = (float(*)[Q])calloc(NT*Q, sizeof(float));
    fcol = (float(*)[Q])calloc(NT*Q, sizeof(float));
    rho = (float*)calloc(NT, sizeof(float));
    ux = (float*)calloc(NT, sizeof(float));
    uy = (float*)calloc(NT, sizeof(float));
    uz = (float*)calloc(NT, sizeof(float));
    nodeType = (char*)calloc(NT, sizeof(char));
    return (f && fcol && rho && ux && uy && uz && nodeType);
}
void free_mem() {
    free(f); free(fcol); free(rho); free(ux); free(uy); free(uz); free(nodeType);
}

int load_geom(const char *fn) {
    FILE *fp = fopen(fn, "rb");
    if (!fp) { printf("打不开 %s\n", fn); return 0; }
    int h[3]; fread(h, sizeof(int), 3, fp);
    NX=h[0]; NY=h[1]; NZ=h[2]; NT=NX*NY*NZ;
    printf("网格: %d x %d x %d = %d\n", NX, NY, NZ, NT);
    
    if (!allocate()) { printf("内存失败\n"); fclose(fp); return 0; }
    
    uint8_t *buf = (uint8_t*)malloc(NT);
    size_t nread = fread(buf, 1, NT, fp);
    fclose(fp);
    printf("读取字节: %zu (期望 %d)\n", nread, NT);
    
    int ns=0, nf=0;
    for (int i=0; i<NT; i++) {
        nodeType[i] = (buf[i] == 1) ? 's' : 'f';
        if (buf[i] == 1) ns++; else nf++;
    }
    printf("固体: %d, 流体: %d (孔隙率 %.1f%%)\n", ns, nf, 100.0f*nf/NT);
    free(buf);
    return 1;
}

void feq(float rh, float u, float v, float w, float *fe) {
    float u2 = u*u+v*v+w*w;
    for (int j=0; j<Q; j++) {
        float eu = e[j][0]*u + e[j][1]*v + e[j][2]*w;
        fe[j] = rh * wgt[j] * (1.0f + 3.0f*eu + 4.5f*eu*eu - 1.5f*u2);
    }
}

/* Guo forcing scheme */
void collide() {
    float fe[Q];
    for (int i=0; i<NT; i++) {
        if (nodeType[i] == 's') continue;
        
        /* 带力的等效速度 */
        float uF = ux[i] + Fx/(2.0f*rho[i]);
        feq(rho[i], uF, uy[i], uz[i], fe);
        
        for (int j=0; j<Q; j++) {
            float eu = e[j][0]*ux[i] + e[j][1]*uy[i] + e[j][2]*uz[i];
            float forcing = (1.0f - 0.5f/tau) * wgt[j] * 
                           (3.0f*(e[j][0]-ux[i]) + 9.0f*e[j][0]*eu) * Fx;
            
            float fnew = f[i][j] - (f[i][j]-fe[j])/tau + forcing;
            if (fnew < 0) fnew = 1e-10f;
            fcol[i][j] = fnew;
        }
    }
}

void stream() {
    for (int i=0; i<NT; i++) {
        if (nodeType[i] == 's') continue;
        int x=getX(i), y=getY(i), z=getZ(i);
        for (int j=0; j<Q; j++) {
            int ip = idx(x-e[j][0], y-e[j][1], z-e[j][2]);
            if (nodeType[ip] == 's')
                f[i][j] = fcol[i][oppo[j]];  /* 固体反弹 */
            else
                f[i][j] = fcol[ip][j];        /* 正常传播 */
        }
    }
}

void macro() {
    for (int i=0; i<NT; i++) {
        if (nodeType[i] == 's') continue;
        float r=0, u=0, v=0, w=0;
        for (int j=0; j<Q; j++) {
            r += f[i][j];
            u += e[j][0]*f[i][j];
            v += e[j][1]*f[i][j];
            w += e[j][2]*f[i][j];
        }
        u += 0.5f * Fx * r;  /* 力的贡献 */
        
        if (r < 1e-6f || isnan(r)) r = 1.0f;
        rho[i] = r;
        ux[i] = u/r; uy[i] = v/r; uz[i] = w/r;
    }
}

void init() {
    float fe[Q];
    for (int i=0; i<NT; i++) {
        rho[i] = 1.0f;
        ux[i] = 0.001f; uy[i] = uz[i] = 0.0f;
        if (nodeType[i] == 's') {
            for (int j=0; j<Q; j++) f[i][j] = 0;
        } else {
            feq(1.0f, 0.001f, 0.0f, 0.0f, fe);
            for (int j=0; j<Q; j++) f[i][j] = fe[j];
        }
    }
}

void stats(int step) {
    double usum=0, rsum=0;
    int n=0;
    float rmin=1e10, rmax=-1e10, umax=-1e10;
    for (int i=0; i<NT; i++) {
        if (nodeType[i]=='s') continue;
        usum += ux[i]; rsum += rho[i]; n++;
        if (rho[i] < rmin) rmin = rho[i];
        if (rho[i] > rmax) rmax = rho[i];
        if (fabs(ux[i]) > umax) umax = fabs(ux[i]);
    }
    if (n==0) return;
    printf("Step %d: u_avg=%.5f, u_max=%.4f, rho=[%.4f, %.4f]\n",
           step, (float)(usum/n), umax, rmin, rmax);
}

void output(int step) {
    char fn[256]; sprintf(fn, "spacer_flow_%04d.bin", step);
    FILE *fp = fopen(fn, "wb");
    int h[4] = {NX, NY, NZ, 4};
    fwrite(h, sizeof(int), 4, fp);
    fwrite(rho, sizeof(float), NT, fp);
    fwrite(ux, sizeof(float), NT, fp);
    fwrite(uy, sizeof(float), NT, fp);
    fwrite(uz, sizeof(float), NT, fp);
    fclose(fp);
    printf("  -> %s\n", fn);
}

int main(int argc, char *argv[]) {
    const char *gfile = (argc>1) ? argv[1] : "geometry.bin";
    if (!load_geom(gfile)) return 1;
    init();
    
    printf("\n体积力驱动: tau=%.3f, Fx=%.2e\n", tau, Fx);
    printf("==================================================\n");
    
    for (int step=1; step<=10000; step++) {
        collide();
        stream();
        macro();
        
        if (step%500==0) stats(step);
        if (step%1000==0) output(step);
    }
    
    printf("==================================================\n完成!\n");
    free_mem();
    return 0;
}
