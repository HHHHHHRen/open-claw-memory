/*
 * RO Spacer LBM - 读取MATLAB几何版本 (自适应网格)
 * Compile: clang -O3 spacer_lbm.c -o spacer_lbm -lm
 * Usage:   ./spacer_lbm  (需要同目录下有 geometry.bin)
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <stdint.h>  /* for uint8_t */

/* 最大允许网格尺寸 (可根据需要调整) */
#define MAX_NX 512
#define MAX_NY 256
#define MAX_NZ 128
#define MAX_NT (MAX_NX*MAX_NY*MAX_NZ)
#define Q 27

/* 实际网格尺寸 (从文件读取) */
int NX, NY, NZ, NT;

const float tau = 0.5015f;
const float dx = 0.05f;

/* D3Q27 Weights */
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

/* Global Arrays - 动态分配 */
float (*f)[Q], (*fcol)[Q];
float *rho, *ux, *uy, *uz;
char *nodeType;

/* Helper Functions */
inline int idx(int x, int y, int z) { return x + y*NX + z*NX*NY; }
inline int getX(int i) { return i % NX; }
inline int getY(int i) { return (i / NX) % NY; }
inline int getZ(int i) { return i / (NX * NY); }
inline int out(int x, int y, int z) { return x<0 || x>=NX || y<0 || y>=NY || z<0 || z>=NZ; }

/* ==================== Output Functions ==================== */
void output_binary(int step) {
    char fname[256];
    sprintf(fname, "spacer_flow_%04d.bin", step);
    FILE *fp = fopen(fname, "wb");
    if (!fp) { perror("fopen"); return; }
    
    int header[4] = {NX, NY, NZ, 4};
    fwrite(header, sizeof(int), 4, fp);
    fwrite(rho, sizeof(float), NT, fp);
    fwrite(ux, sizeof(float), NT, fp);
    fwrite(uy, sizeof(float), NT, fp);
    fwrite(uz, sizeof(float), NT, fp);
    fclose(fp);
    printf("[BIN] Saved: %s\n", fname);
}

void output_tecplot(int step) {
    char fname[256];
    sprintf(fname, "spacer_flow_%04d.dat", step);
    FILE *fp = fopen(fname, "w");
    if (!fp) { perror("fopen"); return; }
    
    fprintf(fp, "TITLE=\"RO Spacer LBM - Step %d\"\n", step);
    fprintf(fp, "VARIABLES=\"X\",\"Y\",\"Z\",\"RHO\",\"U\",\"V\",\"W\"\n");
    fprintf(fp, "ZONE I=%d,J=%d,K=%d,F=POINT\n", NX, NY, NZ);
    
    for (int i=0; i<NT; i++) {
        if (nodeType[i] == 's')
            fprintf(fp, "%d %d %d 0.0 0.0 0.0 0.0\n", getX(i), getY(i), getZ(i));
        else
            fprintf(fp, "%d %d %d %.6f %.6f %.6f %.6f\n", 
                    getX(i), getY(i), getZ(i), rho[i], ux[i], uy[i], uz[i]);
    }
    fclose(fp);
    printf("[DAT] Saved: %s\n", fname);
}

void output(int step) {
    printf("Output at step %d:\n", step);
    output_binary(step);
    output_tecplot(step);
}

/* ==================== LBM Core Functions ==================== */
void computeFeq(int id, float *feq) {
    float rh = rho[id];
    float u = ux[id];
    float v = uy[id];
    float w = uz[id];
    float u2 = u*u + v*v + w*w;
    
    for (int j=0; j<Q; j++) {
        float eu = e[j][0]*u + e[j][1]*v + e[j][2]*w;
        feq[j] = rh * wgt[j] * (1.0f + 3.0f*eu + 4.5f*eu*eu - 1.5f*u2);
    }
}

void collide() {
    float feq[Q];
    for (int i=0; i<NT; i++) {
        if (nodeType[i] == 's') continue;
        computeFeq(i, feq);
        for (int j=0; j<Q; j++)
            fcol[i][j] = f[i][j] - (f[i][j] - feq[j]) / tau;
    }
}

void stream() {
    for (int i=0; i<NT; i++) {
        if (nodeType[i] == 's' || nodeType[i] == 'o') continue;
        
        int x = getX(i), y = getY(i), z = getZ(i);
        char nt = nodeType[i];
        
        for (int j=0; j<Q; j++) {
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
    for (int i=0; i<NT; i++) {
        if (nodeType[i] == 's') continue;
        
        float r=0, u=0, v=0, w=0;
        for (int j=0; j<Q; j++) {
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
    int x, y, z, j;
    
    /* X方向: 周期边界 */
    for (y=0; y<NY; y++) for (z=0; z<NZ; z++) {
        int inl = idx(0, y, z);
        int out = idx(NX-1, y, z);
        for (j=0; j<Q; j++) {
            if (e[j][0] > 0) f[inl][j] = fcol[out][j];
            if (e[j][0] < 0) f[out][j] = fcol[inl][j];
        }
    }
    
    /* Y方向: 周期边界 */
    for (x=0; x<NX; x++) for (z=0; z<NZ; z++) {
        int fr = idx(x, 0, z);
        int ba = idx(x, NY-1, z);
        for (j=0; j<Q; j++) {
            if (e[j][1] > 0) f[fr][j] = fcol[ba][j];
            if (e[j][1] < 0) f[ba][j] = fcol[fr][j];
        }
    }
    
    /* Z方向: 壁面反弹 */
    for (x=0; x<NX; x++) for (y=0; y<NY; y++) {
        int dn = idx(x, y, 0);
        int up = idx(x, y, NZ-1);
        for (j=0; j<Q; j++) {
            if (e[j][2] > 0) f[dn][j] = fcol[dn][oppo[j]];
            if (e[j][2] < 0) f[up][j] = fcol[up][oppo[j]];
        }
    }
}

/* ==================== NEW: Read Geometry from MATLAB ==================== */
void init_from_file() {
    printf("========================================\n");
    printf("RO Spacer LBM - Reading geometry from file\n");
    printf("========================================\n");
    
    /* Open geometry file */
    FILE *fp = fopen("geometry.bin", "rb");
    if (!fp) {
        printf("\nError: Cannot open 'geometry.bin'\n");
        printf("Please run MATLAB export first!\n\n");
        exit(1);
    }
    
    /* Read grid dimensions from file */
    int header[4];
    if (fread(header, sizeof(int), 4, fp) != 4) {
        printf("Error: Failed to read header\n");
        fclose(fp);
        exit(1);
    }
    
    NX = header[0];
    NY = header[1];
    NZ = header[2];
    NT = NX * NY * NZ;
    
    printf("File header: %d x %d x %d = %d cells\n", NX, NY, NZ, NT);
    
    /* Check limits */
    if (NX > MAX_NX || NY > MAX_NY || NZ > MAX_NZ) {
        printf("\nError: Grid exceeds maximum limits!\n");
        printf("  Max allowed: %d x %d x %d\n", MAX_NX, MAX_NY, MAX_NZ);
        printf("  File:        %d x %d x %d\n", NX, NY, NZ);
        printf("\nPlease increase MAX_NX/NY/NZ in the code.\n");
        fclose(fp);
        exit(1);
    }
    
    /* Allocate memory */
    f = (float (*)[Q])malloc(NT * sizeof(float) * Q);
    fcol = (float (*)[Q])malloc(NT * sizeof(float) * Q);
    rho = (float*)malloc(NT * sizeof(float));
    ux = (float*)malloc(NT * sizeof(float));
    uy = (float*)malloc(NT * sizeof(float));
    uz = (float*)malloc(NT * sizeof(float));
    nodeType = (char*)malloc(NT * sizeof(char));
    
    if (!f || !fcol || !rho || !ux || !uy || !uz || !nodeType) {
        printf("Error: Memory allocation failed\n");
        fclose(fp);
        exit(1);
    }
    
    /* Read solid mask */
    uint8_t *solid_mask = (uint8_t*)malloc(NT * sizeof(uint8_t));
    if (!solid_mask) {
        printf("Error: Memory allocation failed\n");
        fclose(fp);
        exit(1);
    }
    
    size_t nread = fread(solid_mask, sizeof(uint8_t), NT, fp);
    fclose(fp);
    
    if (nread != NT) {
        printf("Error: Expected %d bytes, got %zu\n", NT, nread);
        free(solid_mask);
        exit(1);
    }
    
    printf("Geometry data loaded: %.2f MB\n", NT / (1024.0*1024.0));
    
    /* Initialize fields and classify nodes */
    int solid = 0, boundary = 0, fluid = 0;
    
    for (int i=0; i<NT; i++) {
        rho[i] = 1.0f;
        ux[i] = uy[i] = uz[i] = 0.0f;
        
        int x = getX(i), y = getY(i), z = getZ(i);
        
        /* Domain boundaries -> outlet/periodic */
        if (x==0 || x==NX-1 || y==0 || y==NY-1 || z==0 || z==NZ-1) {
            nodeType[i] = 'o';
        }
        /* Solid from file */
        else if (solid_mask[i]) {
            nodeType[i] = 's';
            solid++;
        }
        /* Fluid (temporary) */
        else {
            nodeType[i] = 'i';
            fluid++;
        }
    }
    
    /* Mark boundary nodes (fluid adjacent to solid) */
    for (int i=0; i<NT; i++) {
        if (nodeType[i] != 'i') continue;
        
        int x = getX(i), y = getY(i), z = getZ(i);
        int is_boundary = 0;
        
        for (int j=1; j<Q; j++) {  /* skip (0,0,0) */
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
            boundary++;
            fluid--;
        }
    }
    
    free(solid_mask);
    
    /* Summary */
    float porosity = 100.0f * (float)fluid / NT;
    printf("\nNode classification:\n");
    printf("  Solid:    %d (%.1f%%)\n", solid, 100.0f*solid/NT);
    printf("  Boundary: %d (%.1f%%)\n", boundary, 100.0f*boundary/NT);
    printf("  Fluid:    %d (%.1f%%)\n", fluid, 100.0f*fluid/NT);
    printf("  Porosity: %.2f%%\n", porosity);
    
    /* Initialize equilibrium distribution */
    float feq[Q];
    for (int i=0; i<NT; i++) {
        if (nodeType[i] == 's') {
            for (int j=0; j<Q; j++) f[i][j] = 0.0f;
            continue;
        }
        computeFeq(i, feq);
        for (int j=0; j<Q; j++) f[i][j] = feq[j];
    }
    
    printf("========================================\n");
}

/* ==================== Main ==================== */
int main() {
    /* Read geometry from MATLAB-generated file */
    init_from_file();
    
    /* Run simulation */
    int maxStep = 100;
    int outputInterval = 50;
    
    printf("\nStarting simulation...\n");
    printf("Max steps: %d, Output interval: %d\n\n", maxStep, outputInterval);
    
    for (int s=1; s<=maxStep; s++) {
        collide();
        stream();
        applyBoundary();
        computeMacro();
        
        if (s % 10 == 0) {
            printf("Step %d / %d\n", s, maxStep);
        }
        
        if (s % outputInterval == 0) {
            output(s);
        }
    }
    
    printf("\n========================================\n");
    printf("Simulation complete!\n");
    printf("Convert to MATLAB: python3 bin2mat.py spacer_flow_0050.bin\n");
    printf("========================================\n");
    
    return 0;
}
