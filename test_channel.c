/*
 * 极简LBM测试: 空通道，无固体
 * 如果这能跑通，说明框架正确，问题在geometry.bin
 * Compile: clang -O3 test_channel.c -o test_channel -lm
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#define NX 64
#define NY 16
#define NZ 8
#define NT (NX*NY*NZ)
#define Q 27

const float tau = 0.6f;
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

float f[NT][Q], fcol[NT][Q], rho[NT], ux[NT];

inline int idx(int x, int y, int z) { return x+y*NX+z*NX*NY; }
inline int out(int x, int y, int z) { return x<0||x>=NX||y<0||y>=NY||z<0||z>=NZ; }

void feq(int i, float *fe) {
    float u = ux[i], eu;
    for (int j=0; j<Q; j++) {
        eu = e[j][0]*u;
        fe[j] = wgt[j]*(1.0f + 3.0f*eu + 4.5f*eu*eu - 1.5f*u*u);
    }
}

void collide() {
    float fe[Q];
    for (int i=0; i<NT; i++) {
        feq(i, fe);
        for (int j=0; j<Q; j++)
            fcol[i][j] = f[i][j] - (f[i][j]-fe[j])/tau;
    }
}

void stream() {
    for (int i=0; i<NT; i++) {
        int x=i%NX, y=(i/NX)%NY, z=i/(NX*NY);
        for (int j=0; j<Q; j++) {
            int xp=x-e[j][0], yp=y-e[j][1], zp=z-e[j][2];
            if (out(xp,yp,zp)) f[i][j] = fcol[i][oppo[j]];
            else f[i][j] = fcol[idx(xp,yp,zp)][j];
        }
    }
}

void macro() {
    for (int i=0; i<NT; i++) {
        float r=0, u=0;
        for (int j=0; j<Q; j++) { r += f[i][j]; u += e[j][0]*f[i][j]; }
        rho[i] = r; ux[i] = u/r;
    }
}

/* 入口平衡分布，u=0.05 */
void inlet() {
    float u=0.05f, u2=u*u;
    for (int y=0; y<NY; y++) for (int z=0; z<NZ; z++) {
        int inl = idx(0,y,z);
        for (int j=0; j<Q; j++) {
            float eu=e[j][0]*u;
            f[inl][j] = wgt[j]*(1.0f+3.0f*eu+4.5f*eu*eu-1.5f*u2);
        }
    }
}

/* 出口零梯度 */
void outlet() {
    for (int y=0; y<NY; y++) for (int z=0; z<NZ; z++) {
        int out=idx(NX-1,y,z);
        for (int j=0; j<Q; j++) if (e[j][0]<0)
            f[out][j] = fcol[out-1][j];
    }
}

int main() {
    /* 初始化: u=0.02 */
    for (int i=0; i<NT; i++) {
        ux[i] = 0.02f;
        float fe[Q]; feq(i, fe);
        for (int j=0; j<Q; j++) f[i][j] = fe[j];
    }
    
    for (int step=1; step<=2000; step++) {
        collide(); stream(); inlet(); outlet(); macro();
        if (step%500==0) {
            double u_sum=0;
            for (int i=0; i<NT; i++) u_sum += ux[i];
            printf("Step %d: u_avg=%.5f, rho at center=%.4f\n",
                   step, (float)(u_sum/NT), rho[idx(NX/2,NY/2,NZ/2)]);
        }
    }
    return 0;
}
