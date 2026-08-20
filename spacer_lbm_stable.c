/*
 * RO Spacer LBM - 超稳定版
 * 改进点:
 *   1. 入口直接覆盖平衡分布 (数值最稳)
 *   2. 出口零梯度但带固体保护
 *   3. tau=0.6 确保足够粘性
 *   4. 每500步打印 rho_min/rho_max 监控发散
 *   5. stream() 对所有越界/撞固体统一用反弹
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <stdint.h>

#define Q 27

const float tau = 0.6f;
const float u_target_lb = 0.05f;
const float dx_phys = 5.0e-5f;

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

int NX, NY, NZ, NT;
float (*f)[Q], (*fcol)[Q];
float *rho, *ux, *uy, *uz;
char *nodeType;

inline int idx(int x, int y, int z) { return x + y*NX + z*NX*NY; }
inline int getX(int i) { return i % NX; }
inline int getY(int i) { return (i/NX) % NY; }
inline int getZ(int i) { return i/(NX*NY); }
inline int out(int x, int y, int z) { return x<0||x>=NX||y<0||y>=NY||z<0||z>=NZ; }

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

/* ========== 读取几何 ========== */
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
    
    int ns=0, nb=0, nf=0;
    for (int i=0; i<NT; i++) {
        if (buf[i]==1) { nodeType[i]='s'; ns++; }
        else { nodeType[i]='i'; nf++; }
    }
    free(buf);
    
    /* 标记边界 */
    for (int i=0; i<NT; i++) {
        if (nodeType[i]!='i') continue;
        int x=getX(i), y=getY(i), z=getZ(i);
        for (int j=1; j<Q; j++) {
            int xb=x+e[j][0], yb=y+e[j][1], zb=z+e[j][2];
            if (out(xb,yb,zb)) continue;
            if (nodeType[idx(xb,yb,zb)]=='s') { nodeType[i]='b'; nb++; nf--; break; }
        }
    }
    printf("固体=%d 边界=%d 流体=%d (孔隙率=%.1f%%)\n", ns, nb, nf, 100.0f*nf/NT);
    return 1;
}

void computeFeq(int id, float *feq) {
    float rh=rho[id], u=ux[id], v=uy[id], w=uz[id];
    float u2 = u*u+v*v+w*w;
    for (int j=0; j<Q; j++) {
        float eu = e[j][0]*u + e[j][1]*v + e[j][2]*w;
        feq[j] = rh * wgt[j] * (1.0f + 3.0f*eu + 4.5f*eu*eu - 1.5f*u2);
    }
}

void collide() {
    float feq[Q];
    for (int i=0; i<NT; i++) {
        if (nodeType[i]=='s') continue;
        computeFeq(i, feq);
        for (int j=0; j<Q; j++)
            fcol[i][j] = f[i][j] - (f[i][j]-feq[j])/tau;
    }
}

/* 统一处理: 越界或撞固体都反弹 */
void stream() {
    for (int i=0; i<NT; i++) {
        if (nodeType[i]=='s') continue;
        int x=getX(i), y=getY(i), z=getZ(i);
        for (int j=0; j<Q; j++) {
            int xp=x-e[j][0], yp=y-e[j][1], zp=z-e[j][2];
            if (out(xp,yp,zp) || nodeType[idx(xp,yp,zp)]=='s')
                f[i][j] = fcol[i][oppo[j]];
            else
                f[i][j] = fcol[idx(xp,yp,zp)][j];
        }
    }
}

void computeMacro() {
    for (int i=0; i<NT; i++) {
        if (nodeType[i]=='s') continue;
        float r=0,u=0,v=0,w=0;
        for (int j=0; j<Q; j++) {
            r += f[i][j]; u += e[j][0]*f[i][j];
            v += e[j][1]*f[i][j]; w += e[j][2]*f[i][j];
        }
        if (r < 1e-6f || r > 10.0f || isnan(r)) r=1.0f;
        rho[i]=r; ux[i]=u/r; uy[i]=v/r; uz[i]=w/r;
        /* 速度截断，防止极端值 */
        if (ux[i] > 1.0f) ux[i]=1.0f; if (ux[i] < -1.0f) ux[i]=-1.0f;
        if (uy[i] > 1.0f) uy[i]=1.0f; if (uy[i] < -1.0f) uy[i]=-1.0f;
        if (uz[i] > 1.0f) uz[i]=1.0f; if (uz[i] < -1.0f) uz[i]=-1.0f;
    }
}

/* ========== 边界条件 ========== */
void applyInletEquilibrium(int inl) {
    /* 直接覆盖平衡分布 - 最稳定 */
    float rh=1.0f, ux0=u_target_lb, u2=ux0*ux0;
    for (int j=0; j<Q; j++) {
        float eu = e[j][0]*ux0;
        f[inl][j] = rh * wgt[j] * (1.0f + 3.0f*eu + 4.5f*eu*eu - 1.5f*u2);
    }
}

void applyOutletConvective(int out) {
    /* 找左边最近的流体节点作为参考 */
    int ref = out - 1;
    while (ref >= out - 5 && ref >= 0 && nodeType[ref]=='s') ref--;
    
    if (ref >= 0 && nodeType[ref]!='s') {
        for (int j=0; j<Q; j++) if (e[j][0] < 0) f[out][j] = fcol[ref][j];
    }
    else {
        /* 兜底: 用u=0的平衡分布 */
        for (int j=0; j<Q; j++) f[out][j] = wgt[j];
    }
}

void applyBoundary() {
    /* X入口 */
    for (int y=0; y<NY; y++) for (int z=0; z<NZ; z++) {
        int inl=idx(0,y,z);
        if (nodeType[inl]!='s') applyInletEquilibrium(inl);
    }
    /* X出口 */
    for (int y=0; y<NY; y++) for (int z=0; z<NZ; z++) {
        int out=idx(NX-1,y,z);
        if (nodeType[out]!='s') applyOutletConvective(out);
    }
    /* Y周期 */
    for (int x=0; x<NX; x++) for (int z=0; z<NZ; z++) {
        int fr=idx(x,0,z), ba=idx(x,NY-1,z);
        for (int j=0; j<Q; j++) {
            if (e[j][1]>0 && nodeType[fr]!='s') f[fr][j]=fcol[ba][j];
            if (e[j][1]<0 && nodeType[ba]!='s') f[ba][j]=fcol[fr][j];
        }
    }
    /* Z壁面 */
    for (int x=0; x<NX; x++) for (int y=0; y<NY; y++) {
        int dn=idx(x,y,0), up=idx(x,y,NZ-1);
        for (int j=0; j<Q; j++) {
            if (e[j][2]>0) f[dn][j]=fcol[dn][oppo[j]];
            if (e[j][2]<0) f[up][j]=fcol[up][oppo[j]];
        }
    }
}

void output(int step) {
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
    printf("  [BIN] %s\n", fname);
}

void getStats() {
    double u_sum=0; int n=0;
    float rmin=1e10, rmax=-1e10;
    for (int i=0; i<NT; i++) {
        if (nodeType[i]=='s') continue;
        u_sum += ux[i]; n++;
        if (rho[i] < rmin) rmin = rho[i];
        if (rho[i] > rmax) rmax = rho[i];
    }
    if (n==0) { printf("无流体节点\n"); return; }
    float u_avg = (float)(u_sum/n);
    printf("   u_avg=%.5f (%.4f m/s), rho_min=%.4f, rho_max=%.4f\n",
           u_avg, u_avg*dx_phys/1e-5f, rmin, rmax);
}

void init() {
    float feq[Q];
    for (int i=0; i<NT; i++) {
        if (nodeType[i]=='s') { for (int j=0; j<Q; j++) f[i][j]=0; continue; }
        
        /* 只有纯流体节点给非零初速，边界节点用u=0的平衡态 */
        float u_init = 0.0f;
        if (nodeType[i]=='i') {
            int x=getX(i);
            u_init = u_target_lb * ((float)x / (NX-1));
        }
        
        rho[i]=1.0f; ux[i]=u_init; uy[i]=uz[i]=0;
        float u2=u_init*u_init;
        for (int j=0; j<Q; j++) {
            float eu=e[j][0]*u_init;
            feq[j]=wgt[j]*(1.0f+3.0f*eu+4.5f*eu*eu-1.5f*u2);
        }
        for (int j=0; j<Q; j++) f[i][j]=feq[j];
    }
}

int main(int argc, char *argv[]) {
    const char *geom_file = (argc>1) ? argv[1] : "geometry.bin";
    if (!load_geometry(geom_file)) return 1;
    
    init();
    
    int maxStep=5000, outInterval=500;
    printf("\n开始: tau=%.2f, u_target=%.3f\n", tau, u_target_lb);
    printf("="*40 + "\n");
    
    for (int step=1; step<=maxStep; step++) {
        collide();
        stream();
        applyBoundary();
        computeMacro();
        
        if (step%500==0) { printf("Step %d: ", step); getStats(); }
        if (step%outInterval==0) output(step);
    }
    
    printf("="*40 + "\n完成!\n");
    free_memory();
    return 0;
}
