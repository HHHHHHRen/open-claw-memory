/*
 * RO Spacer LBM - 体积力驱动版 (文献标准做法)
 * 改用 Guo forcing scheme + 周期边界，tau 可以更低，流动更自然
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <stdint.h>

#define Q 27

const float tau = 0.51f;        /* 更低粘度 */
const float Fx = 1.0e-5f;       /* 体积力驱动 */

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

int NX, NY, NZ, NT;
float (*f)[Q], (*fcol)[Q], *rho, *ux, *uy, *uz;
char *nodeType;

inline int idx(int x, int y, int z) { 
    /* 周期边界处理 */
    x = (x + NX) % NX;
    y = (y + NY) % NY;
    z = (z + NZ) % NZ;
    return x + y*NX + z*NX*NY; 
}
inline int getX(int i) { return i % NX; }
inline int getY(int i) { return (i/NX) % NY; }
inline int getZ(int i) { return i/(NX*NY); }

int allocate_memory() {
    f = (float(*)[Q])calloc(NT*Q, sizeof(float));
    fcol = (float(*)[Q])calloc(NT*Q, sizeof(float));
    rho = (float*)calloc(NT, sizeof(float));
    ux = (float*)calloc(NT, sizeof(float));
    uy = (float*)calloc(NT, sizeof(float));
    uz = (float*)calloc(NT, sizeof(float));
    nodeType = (char*)calloc(NT, sizeof(char));
    return (f && fcol && rho && ux && uy && uz && nodeType);
}
void free_memory() {
    free(f); free(fcol); free(rho); free(ux); free(uy); free(uz); free(nodeType);
}

int load_geometry(const char *filename) {
    FILE *fp = fopen(filename, "rb");
    if (!fp) { printf("无法打开 %s\n", filename); return 0; }
    
    int header[3];
    fread(header, sizeof(int), 3, fp);
    NX = header[0]; NY = header[1]; NZ = header[2];
    NT = NX * NY * NZ;
    printf("网格: %dx%dx%d = %d\n", NX, NY, NZ, NT);
    
    if (!allocate_memory()) { printf("内存失败\n"); fclose(fp); return 0; }
    
    uint8_t *buf = (uint8_t*)malloc(NT);
    fread(buf, sizeof(uint8_t), NT, fp);
    fclose(fp);
    
    int ns=0, nf=0;
    for (int i=0; i<NT; i++) {
        nodeType[i] = (buf[i] == 1) ? 's' : 'f';
        if (buf[i] == 1) ns++; else nf++;
    }
    printf("固体=%d 流体=%d (孔隙率=%.1f%%)\n", ns, nf, 100.0f*nf/NT);
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
        if (nodeType[i]=='s') continue;
        
        /* 带力的宏观速度 */
        float uF = ux[i] + Fx/(2.0f*rho[i]);
        float vF = uy[i];
        float wF = uz[i];
        
        feq(rho[i], uF, vF, wF, fe);
        
        for (int j=0; j<Q; j++) {
            float eu = e[j][0]*ux[i] + e[j][1]*uy[i] + e[j][2]*uz[i];
            float forcing = (1.0f - 1.0f/(2.0f*tau)) * wgt[j] * 
                           (3.0f*(e[j][0]-ux[i]) + 9.0f*e[j][0]*eu) * Fx;
            
            float f_new = f[i][j] - (f[i][j]-fe[j])/tau + forcing;
            if (f_new < 0) f_new = 1e-8f;
            fcol[i][j] = f_new;
        }
    }
}

/* 周期 stream + 固体反弹 */
void stream() {
    for (int i=0; i<NT; i++) {
        if (nodeType[i]=='s') continue;
        int x=getX(i), y=getY(i), z=getZ(i);
        for (int j=0; j<Q; j++) {
            int xp = x - e[j][0];
            int yp = y - e[j][1];
            int zp = z - e[j][2];
            int ip = idx(xp, yp, zp);
            if (nodeType[ip]=='s')
                f[i][j] = fcol[i][(j+3)%6==j?0:(j+3)%6+3*(j/6)]; /* 简化反弹 */
            else
                f[i][j] = fcol[ip][j];
        }
    }
}

/* 正确的反弹索引 */
const int oppo[Q] = {0,3,4,1,2,6,5,9,10,7,8,17,18,15,16,13,14,11,12,25,26,23,24,21,22,19,20};

void stream_correct() {
    for (int i=0; i<NT; i++) {
        if (nodeType[i]=='s') continue;
        int x=getX(i), y=getY(i), z=getZ(i);
        for (int j=0; j<Q; j++) {
            int xp = x - e[j][0], yp = y - e[j][1], zp = z - e[j][2];
            int ip = idx(xp, yp, zp);
            if (nodeType[ip]=='s')
                f[i][j] = fcol[i][oppo[j]];
            else
                f[i][j] = fcol[ip][j];
        }
    }
}

void macro() {
    for (int i=0; i<NT; i++) {
        if (nodeType[i]=='s') continue;
        float r=0,u=0,v=0,w=0;
        for (int j=0; j<Q; j++) {
            r += f[i][j]; 
            u += e[j][0]*f[i][j];
            v += e[j][1]*f[i][j];
            w += e[j][2]*f[i][j];
        }
        /* 加上体积力贡献 */
        u += 0.5f * Fx;
        
        if (r < 1e-6f || isnan(r)) r = 1.0f;
        rho[i] = r;
        ux[i] = u/r; uy[i] = v/r; uz[i] = w/r;
    }
}

void init() {
    float fe[Q];
    for (int i=0; i<NT; i++) {
        rho[i] = 1.0f;
        ux[i] = 0.01f;  /* 给一个小初速 */
        uy[i] = uz[i] = 0.0f;
        
        if (nodeType[i]=='s') {
            for (int j=0; j<Q; j++) f[i][j] = 0;
        } else {
            feq(1.0f, 0.01f, 0.0f, 0.0f, fe);
            for (int j=0; j<Q; j++) f[i][j] = fe[j];
        }
    }
}

void getStats(int step) {
    double u_sum=0; int n=0;
    float rmin=1e10, rmax=-1e10;
    for (int i=0; i<NT; i++) {
        if (nodeType[i]=='s') continue;
        u_sum += ux[i]; n++;
        if (rho[i] < rmin) rmin = rho[i];
        if (rho[i] > rmax) rmax = rho[i];
    }
    if (n==0) return;
    printf("Step %d: u_avg=%.5f (目标~0.05), rho=[%.4f, %.4f]\n", 
           step, (float)(u_sum/n), rmin, rmax);
}

void output(int step) {
    char fname[256]; sprintf(fname, "spacer_flow_%04d.bin", step);
    FILE *fp = fopen(fname, "wb");
    int header[4] = {NX, NY, NZ, 4};
    fwrite(header, sizeof(int), 4, fp);
    fwrite(rho, sizeof(float), NT, fp);
    fwrite(ux, sizeof(float), NT, fp);
    fwrite(uy, sizeof(float), NT, fp);
    fwrite(uz, sizeof(float), NT, fp);
    fclose(fp);
    printf("  [BIN] %s\n", fname);
}

int main(int argc, char *argv[]) {
    const char *geom_file = (argc>1) ? argv[1] : "geometry.bin";
    if (!load_geometry(geom_file)) return 1;
    init();
    printf("\n体积力驱动: tau=%.3f, Fx=%.2e\n", tau, Fx);
    printf("==================================================\n");
    
    for (int step=1; step<=10000; step++) {
        collide();
        stream_correct();
        macro();
        
        if (step%500==0) getStats(step);
        if (step%1000==0) output(step);
    }
    printf("==================================================\n完成!\n");
    free_memory();
    return 0;
}
