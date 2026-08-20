/*
 * RO Spacer LBM - HDF5 Output Version
 * MATLAB: data = load('spacer_flow_0050.h5');
 * Compile: clang -O3 spacer_lbm_h5.c -o spacer_lbm -lhdf5 -lm
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <hdf5.h>

#define D 3
#define Q 27
#define NX 340
#define NY 113
#define NZ 24
#define NT (NX * NY * NZ)

/* Parameters */
const float dx = 0.05f, pitch = 4.0f, r_fiber = 0.5f, r_node = 0.61f;
const float z_fiber_center = 0.5f, tau = 0.5015f;

/* D3Q27 */
const double w[Q] = {
 8.0/27, 2.0/27, 2.0/27, 2.0/27, 2.0/27, 2.0/27, 2.0/27,
 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54,
 1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216
};
const int e[Q][3] = {
 {0,0,0}, {1,0,0}, {0,1,0}, {-1,0,0}, {0,-1,0}, {0,0,1}, {0,0,-1},
 {1,1,0}, {-1,1,0}, {-1,-1,0}, {1,-1,0}, {1,0,1}, {0,1,1}, {-1,0,1}, {0,-1,1},
 {1,0,-1}, {0,1,-1}, {-1,0,-1}, {0,-1,-1},
 {1,1,1}, {-1,1,1}, {-1,-1,1}, {1,-1,1}, {1,1,-1}, {-1,1,-1}, {-1,-1,-1}, {1,-1,-1}
};
const int oppoDir[Q] = {0,3,4,1,2,6,5,9,10,7,8,17,18,15,16,13,14,11,12,25,26,23,24,21,22,19,20};

/* Arrays */
float f[NT][Q], fcol[NT][Q], rho[NT], ux[NT], uy[NT], uz[NT];
char nodeType[NT];

/* Helpers */
int idx(int x, int y, int z) { return x + y*NX + z*NX*NY; }
int getX(int i) { return i % NX; }
int getY(int i) { return (i/NX) % NY; }
int getZ(int i) { return i/(NX*NY); }
int out(int x, int y, int z) { return x<0||x>=NX||y<0||y>=NY||z<0||z>=NZ; }

/* ==================== HDF5 Output ==================== */
void write_hdf5(int step) {
    char fname[256];
    sprintf(fname, "spacer_flow_%04d.h5", step);
    
    hid_t file = H5Fcreate(fname, H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
    if (file < 0) { printf("HDF5 create failed\n"); return; }
    
    hsize_t dims[3] = {NZ, NY, NX};
    hid_t dataspace = H5Screate_simple(3, dims, NULL);
    
    /* Convert to double for MATLAB compatibility */
    double *ux_d = malloc(NT * sizeof(double));
    double *uy_d = malloc(NT * sizeof(double));
    double *uz_d = malloc(NT * sizeof(double));
    double *rho_d = malloc(NT * sizeof(double));
    
    for (int i = 0; i < NT; i++) {
        ux_d[i] = ux[i]; uy_d[i] = uy[i]; uz_d[i] = uz[i]; rho_d[i] = rho[i];
    }
    
    hid_t dataset;
    dataset = H5Dcreate(file, "ux", H5T_NATIVE_DOUBLE, dataspace, 
                        H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    H5Dwrite(dataset, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, ux_d);
    H5Dclose(dataset);
    
    dataset = H5Dcreate(file, "uy", H5T_NATIVE_DOUBLE, dataspace, 
                        H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    H5Dwrite(dataset, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, uy_d);
    H5Dclose(dataset);
    
    dataset = H5Dcreate(file, "uz", H5T_NATIVE_DOUBLE, dataspace, 
                        H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    H5Dwrite(dataset, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, uz_d);
    H5Dclose(dataset);
    
    dataset = H5Dcreate(file, "rho", H5T_NATIVE_DOUBLE, dataspace, 
                        H5P_DEFAULT, H5P_DEFAULT, H5P_DEFAULT);
    H5Dwrite(dataset, H5T_NATIVE_DOUBLE, H5S_ALL, H5S_ALL, H5P_DEFAULT, rho_d);
    H5Dclose(dataset);
    
    H5Sclose(dataspace);
    H5Fclose(file);
    
    free(ux_d); free(uy_d); free(uz_d); free(rho_d);
    printf("  [HDF5] Saved: %s\n", fname);
}

/* ==================== LBM ==================== */
void feq(int id, float *fe) {
    float rh = rho[id], u = ux[id], v = uy[id], w = uz[id];
    float uu = u*u + v*v + w*w;
    for (int j = 0; j < Q; j++) {
        float eu = e[j][0]*u + e[j][1]*v + e[j][2]*w;
        fe[j] = rh * w[j] * (1.0 + 3*eu + 4.5*eu*eu - 1.5*uu);
    }
}

void collide() {
    float fe[Q];
    for (int i = 0; i < NT; i++) {
        if (nodeType[i] == 's') continue;
        feq(i, fe);
        for (int j = 0; j < Q; j++)
            fcol[i][j] = f[i][j] - (f[i][j] - fe[j])/tau;
    }
}

void stream() {
    for (int i = 0; i < NT; i++) {
        if (nodeType[i] == 's' || nodeType[i] == 'o') continue;
        int x = getX(i), y = getY(i), z = getZ(i);
        for (int j = 0; j < Q; j++) {
            int xp = x - e[j][0], yp = y - e[j][1], zp = z - e[j][2];
            if (nodeType[i] == 'i') {
                if (!out(xp, yp, zp)) f[i][j] = fcol[idx(xp,yp,zp)][j];
            } else if (nodeType[i] == 'b') {
                if (out(xp,yp,zp) || nodeType[idx(xp,yp,zp)] == 's')
                    f[i][j] = fcol[i][oppoDir[j]];
                else
                    f[i][j] = fcol[idx(xp,yp,zp)][j];
            }
        }
    }
}

void macro() {
    for (int i = 0; i < NT; i++) {
        if (nodeType[i] == 's') continue;
        float r = 0, u = 0, v = 0, w = 0;
        for (int j = 0; j < Q; j++) {
            r += f[i][j];
            u += e[j][0]*f[i][j];
            v += e[j][1]*f[i][j];
            w += e[j][2]*f[i][j];
        }
        rho[i] = r; ux[i] = u/r; uy[i] = v/r; uz[i] = w/r;
    }
}

void bc() {
    for (int y = 0; y < NY; y++) for (int z = 0; z < NZ; z++) {
        int inl = idx(0,y,z), out = idx(NX-1,y,z);
        for (int j = 0; j < Q; j++) {
            if (e[j][0] > 0) f[inl][j] = fcol[out][j];
            if (e[j][0] < 0) f[out][j] = fcol[inl][j];
        }
    }
    for (int x = 0; x < NX; x++) for (int z = 0; z < NZ; z++) {
        int fr = idx(x,0,z), ba = idx(x,NY-1,z);
        for (int j = 0; j < Q; j++) {
            if (e[j][1] > 0) f[fr][j] = fcol[ba][j];
            if (e[j][1] < 0) f[ba][j] = fcol[fr][j];
        }
    }
    for (int x = 0; x < NX; x++) for (int y = 0; y < NY; y++) {
        int dn = idx(x,y,0), up = idx(x,y,NZ-1);
        for (int j = 0; j < Q; j++) {
            if (e[j][2] > 0) f[dn][j] = fcol[dn][oppoDir[j]];
            if (e[j][2] < 0) f[up][j] = fcol[up][oppoDir[j]];
        }
    }
}

void init() {
    int solid = 0;
    printf("Grid: %dx%dx%d = %d\n", NX, NY, NZ, NT);
    for (int i = 0; i < NT; i++) {
        rho[i] = 1; ux[i] = uy[i] = uz[i] = 0; nodeType[i] = 'i';
        int x = getX(i), y = getY(i), z = getZ(i);
        if (x==0||x==NX-1||y==0||y==NY-1||z==0||z==NZ-1) nodeType[i] = 'o';
    }
    float diag = pitch * sqrtf(2.0f);
    for (int i = 0; i < NT; i++) {
        int x = getX(i), y = getY(i), z = getZ(i);
        float px = x*dx, py = y*dx, pz = z*dx;
        int is = 0;
        for (float c = -NY*dx; c <= NX*dx+NY*dx && !is; c += diag) {
            float dxy = fabsf(px-py-c)/sqrtf(2.0f);
            if (dxy < r_fiber && fabsf(pz-z_fiber_center) < r_fiber) is = 1;
        }
        if (is) goto mark;
        for (float c = 0; c <= NX*dx+NY*dx && !is; c += diag) {
            float dxy = fabsf(px+py-c)/sqrtf(2.0f);
            if (dxy < r_fiber && fabsf(pz-z_fiber_center) < r_fiber) is = 1;
        }
        if (is) goto mark;
        for (float c1 = -NY*dx; c1 <= NX*dx+NY*dx && !is; c1 += diag) {
            for (float c2 = 0; c2 <= NX*dx+NY*dx; c2 += diag) {
                float xc = (c1+c2)/2, yc = (c2-c1)/2;
                if (xc >= 0 && xc <= NX*dx && yc >= 0 && yc <= NY*dx) {
                    float d = sqrtf((px-xc)*(px-xc)+(py-yc)*(py-yc)+(pz-z_fiber_center)*(pz-z_fiber_center));
                    if (d < r_node) { is = 1; break; }
                }
            }
        }
    mark:
        if (is) { nodeType[i] = 's'; solid++; }
    }
    for (int i = 0; i < NT; i++) if (nodeType[i] != 's') {
        int x = getX(i), y = getY(i), z = getZ(i);
        for (int j = 0; j < Q; j++) {
            int xb = x+e[j][0], yb = y+e[j][1], zb = z+e[j][2];
            if (!out(xb,yb,zb) && nodeType[idx(xb,yb,zb)] == 's') { nodeType[i] = 'b'; break; }
        }
    }
    printf("Porosity: %.2f%%\n", 100*(1-(float)solid/NT));
    float fe[Q];
    for (int i = 0; i < NT; i++) {
        if (nodeType[i] == 's') { for (int j = 0; j < Q; j++) f[i][j] = 0; continue; }
        feq(i, fe); for (int j = 0; j < Q; j++) f[i][j] = fe[j];
    }
}

void output_dat(int step) {
    char n[256]; sprintf(n, "spacer_flow_%04d.dat", step);
    FILE *fp = fopen(n, "w");
    fprintf(fp, "VARIABLES=\"X\",\"Y\",\"Z\",\"U\",\"V\",\"W\",\"RHO\"\n");
    fprintf(fp, "ZONE I=%d,J=%d,K=%d,F=POINT\n", NX, NY, NZ);
    for (int i = 0; i < NT; i++)
        fprintf(fp, "%d %d %d %f %f %f %f\n", getX(i), getY(i), getZ(i), ux[i], uy[i], uz[i], rho[i]);
    fclose(fp);
    printf("  [DAT] %s\n", n);
}

void output_geom() {
    FILE *fp = fopen("geometry.dat", "w");
    fprintf(fp, "ZONE I=%d,J=%d,K=%d\n", NX, NY, NZ);
    for (int i = 0; i < NT; i++) {
        int t = (nodeType[i]=='s') ? 1 : (nodeType[i]=='b') ? 2 : 0;
        fprintf(fp, "%d %d %d %d\n", getX(i), getY(i), getZ(i), t);
    }
    fclose(fp);
}

int main() {
    init(); output_geom();
    printf("Running 100 steps...\n");
    for (int s = 1; s <= 100; s++) {
        collide(); stream(); bc(); macro();
        if (s % 10 == 0) printf("Step %d\n", s);
        if (s % 50 == 0) { output_dat(s); write_hdf5(s); }
    }
    printf("Done.\n");
    return 0;
}
