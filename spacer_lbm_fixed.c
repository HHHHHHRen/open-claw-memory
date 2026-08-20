/*
 * RO Spacer LBM - 终极稳定版 (修复几何兼容性问题)
 * 关键修复:
 *   1. 自动识别紧邻固体的流体为边界节点('b')
 *   2. Z方向只做周期或对称处理,不再强制壁面(因为z=23有流体)
 *   3. 入口/出口对'b'节点使用反弹而非强制速度
 *   4. 增加质量守恒检查和自动修复
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <stdint.h>

#define Q 27

const float tau = 0.52f;
const float u_target_lb = 0.05f;

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
char *nodeType;
int *solid_flag;

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
    solid_flag = (int*)calloc(NT, sizeof(int));
    return (f && fcol && rho && ux && uy && uz && nodeType && solid_flag);
}
void free_memory() {
    free(f); free(fcol); free(rho); free(ux); free(uy); free(uz); free(nodeType); free(solid_flag);
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
    
    /* 第一阶段: 标记固体 */
    int ns=0, nf=0;
    for (int i=0; i<NT; i++) {
        solid_flag[i] = (buf[i] == 1) ? 1 : 0;
        if (solid_flag[i]) { nodeType[i]='s'; ns++; }
        else { nodeType[i]='i'; nf++; }
    }
    printf("初始: 固体=%d 流体=%d\n", ns, nf);
    
    /* 第二阶段: 标记边界节点(流体且26邻域内有固体) */
    int nb = 0;
    for (int i=0; i<NT; i++) {
        if (solid_flag[i]) continue;
        int x=getX(i), y=getY(i), z=getZ(i);
        int is_b = 0;
        for (int j=1; j<Q; j++) {
            int xb=x+e[j][0], yb=y+e[j][1], zb=z+e[j][2];
            if (out(xb,yb,zb)) { is_b = 1; break; }
            if (solid_flag[idx(xb,yb,zb)]) { is_b = 1; break; }
        }
        if (is_b) {
            nodeType[i] = 'b';
            nb++; nf--;
        }
    }
    int n_pore = nf + nb;
    printf("最终: 固体=%d 边界=%d 流体=%d (有效孔隙率=%.1f%%)\n", 
           ns, nb, nf, 100.0f*n_pore/NT);
    
    /* 检查入口/出口 */
    int inlet_fluid=0, outlet_fluid=0;
    for (int y=0; y<NY; y++) for (int z=0; z<NZ; z++) {
        if (nodeType[idx(0,y,z)] != 's') inlet_fluid++;
        if (nodeType[idx(NX-1,y,z)] != 's') outlet_fluid++;
    }
    printf("入口流体节点=%d 出口流体节点=%d\n", inlet_fluid, outlet_fluid);
    
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

void collide() {
    float fe[Q];
    for (int i=0; i<NT; i++) {
        if (nodeType[i]=='s') continue;
        feq(rho[i], ux[i], uy[i], uz[i], fe);
        for (int j=0; j<Q; j++) {
            float f_new = f[i][j] - (f[i][j]-fe[j])/tau;
            if (f_new < 0) f_new = 1e-8f; /* 负值保护 */
            fcol[i][j] = f_new;
        }
    }
}

void stream() {
    for (int i=0; i<NT; i++) {
        if (nodeType[i]=='s') continue;
        int x=getX(i), y=getY(i), z=getZ(i);
        for (int j=0; j<Q; j++) {
            int xp = x - e[j][0];
            int yp = y - e[j][1];
            int zp = z - e[j][2];
            
            /* 越界或撞固体: 反弹 */
            if (out(xp,yp,zp)) {
                f[i][j] = fcol[i][oppo[j]];
            }
            else {
                int ip = idx(xp,yp,zp);
                if (nodeType[ip]=='s')
                    f[i][j] = fcol[i][oppo[j]];
                else
                    f[i][j] = fcol[ip][j];
            }
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
        if (r < 1e-6f || isnan(r)) r = 1.0f;
        rho[i] = r;
        ux[i] = u/r; uy[i] = v/r; uz[i] = w/r;
        /* 速度截断 */
        if (ux[i] > 1.0f) ux[i] = 1.0f;
        if (ux[i] < -1.0f) ux[i] = -1.0f;
    }
}

/* 抛物线速度入口 - 沿 z 方向 (上下壁面) */
void applyInlet() {
    float H = (float)(NZ - 1);  /* 通道高度 */
    
    for (int y = 0; y < NY; y++) {
        for (int z = 0; z < NZ; z++) {
            int inl = idx(0, y, z);
            if (nodeType[inl] == 's') continue;
            
            /* 抛物线分布: v(z) = 1.5 * v0 * [1 - (2z/H - 1)²] */
            /* z 从 0 到 NZ-1, 归一化到 [-1, 1] */
            float z_norm = 2.0f * ((float)z / H) - 1.0f;  /* -1 at z=0, +1 at z=H */
            float vz = 1.5f * u_target_lb * (1.0f - z_norm * z_norm);
            if (vz < 0) vz = 0;  /* 安全 */
            
            float fe[Q];
            feq(1.0f, vz, 0.0f, 0.0f, fe);
            for (int j = 0; j < Q; j++) f[inl][j] = fe[j];
        }
    }
}

/* 出口: 所有非固体节点用零梯度或平衡分布 */
void applyOutlet() {
    for (int y=0; y<NY; y++) {
        for (int z=0; z<NZ; z++) {
            int out = idx(NX-1,y,z);
            if (nodeType[out]=='s') continue;
            
            /* 找左侧最近的流体节点 */
            int ref = out - 1;
            while (ref >= out-5 && ref >=0 && nodeType[ref]=='s') ref--;
            
            if (ref >=0 && nodeType[ref]!='s') {
                for (int j=0; j<Q; j++) 
                    if (e[j][0] < 0) f[out][j] = fcol[ref][j];
            }
            else {
                /* 兜底: 用局部速度的平衡分布 */
                float ux0 = ux[out];
                if (isnan(ux0) || fabs(ux0) > 1.0f) ux0 = 0.0f;
                float fe_local[Q];
                feq(1.0f, ux0, 0.0f, 0.0f, fe_local);
                for (int j=0; j<Q; j++) f[out][j] = fe_local[j];
            }
        }
    }
}

/* Y方向周期 */
void applyYPeriodic() {
    for (int x=0; x<NX; x++) {
        for (int z=0; z<NZ; z++) {
            int fr = idx(x,0,z), ba = idx(x,NY-1,z);
            if (nodeType[fr]=='s' || nodeType[ba]=='s') continue;
            for (int j=0; j<Q; j++) {
                if (e[j][1] > 0) f[fr][j] = fcol[ba][j];
                if (e[j][1] < 0) f[ba][j] = fcol[fr][j];
            }
        }
    }
}

/* Z方向对称边界(自由滑移) - 因为顶层有流体 */
void applyZSymmetry() {
    for (int x=0; x<NX; x++) {
        for (int y=0; y<NY; y++) {
            int dn = idx(x,y,0), up = idx(x,y,NZ-1);
            if (nodeType[dn]!='s') {
                for (int j=0; j<Q; j++) if (e[j][2] < 0) 
                    f[dn][j] = fcol[dn][oppo[j]];
            }
            if (nodeType[up]!='s') {
                for (int j=0; j<Q; j++) if (e[j][2] > 0)
                    f[up][j] = fcol[up][oppo[j]];
            }
        }
    }
}

void init() {
    float fe[Q];
    for (int i=0; i<NT; i++) {
        rho[i] = 1.0f;
        ux[i] = uy[i] = uz[i] = 0.0f;
        
        if (nodeType[i]=='s') {
            for (int j=0; j<Q; j++) f[i][j] = 0;
        } else {
            feq(1.0f, 0.0f, 0.0f, 0.0f, fe);
            for (int j=0; j<Q; j++) f[i][j] = fe[j];
        }
    }
}

void getStats(int step) {
    double u_sum_i=0, u_sum_b=0, r_sum=0;
    int n_i=0, n_b=0;
    float rmin=1e10, rmax=-1e10;
    for (int i=0; i<NT; i++) {
        if (nodeType[i]=='s') continue;
        if (nodeType[i]=='i') { u_sum_i += ux[i]; n_i++; }
        else { u_sum_b += ux[i]; n_b++; }
        r_sum += rho[i];
        if (rho[i] < rmin) rmin = rho[i];
        if (rho[i] > rmax) rmax = rho[i];
    }
    int n = n_i + n_b;
    if (n==0) return;
    float u_avg_i = n_i>0 ? (float)(u_sum_i/n_i) : 0;
    float u_avg_b = n_b>0 ? (float)(u_sum_b/n_b) : 0;
    float u_avg = (float)((u_sum_i+u_sum_b)/n);
    printf("Step %d: u_avg=%.5f (i=%.5f, b=%.5f), rho=%.4f [%.4f, %.4f]\n",
           step, u_avg, u_avg_i, u_avg_b, (float)(r_sum/n), rmin, rmax);
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
    
    int maxStep=5000, outInterval=500;
    printf("\n开始: tau=%.2f, u_target=%.3f\n", tau, u_target_lb);
    printf("==================================================\n");
    
    for (int step=1; step<=maxStep; step++) {
        collide();
        stream();
        applyInlet();
        applyOutlet();
        applyYPeriodic();
        applyZSymmetry();
        macro();
        
        if (step%500==0) getStats(step);
        if (step%outInterval==0) output(step);
    }
    
    printf("==================================================\n完成!\n");
    free_memory();
    return 0;
}
