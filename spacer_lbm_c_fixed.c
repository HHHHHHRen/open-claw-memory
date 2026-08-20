/*
 * RO Spacer LBM - Pure C Version with MAT output
 * Compile: clang -O3 spacer_lbm_c.c -o spacer_lbm_c -lm
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <stdint.h>

#define D 3
#define Q 27
#define NX 340
#define NY 113
#define NZ 24
#define NT (NX * NY * NZ)

/* MAT file format constants */
#define MI_INT8    1
#define MI_UINT32  6
#define MI_INT32   5
#define MI_DOUBLE  9
#define MI_MATRIX  14
#define MX_DOUBLE_CLASS 6

/* Geometry Parameters */
const float dx = 0.05f;
const float pitch = 4.0f;
const float r_fiber = 0.5f;
const float r_node = 0.61f;
const float z_fiber_center = 0.5f;

/* LBM Parameters */
const float tau = 0.5015f;

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

/* Global Arrays */
float f[NT][Q];
float fcol[NT][Q];
float rho[NT];
float ux[NT], uy[NT], uz[NT];
char nodeType[NT];

/* Helper Functions */
int getIndex(int x, int y, int z) { return x + y * NX + z * NX * NY; }
int getX(int id) { return id % NX; }
int getY(int id) { return (id / NX) % NY; }
int getZ(int id) { return id / (NX * NY); }
int outRange(int x, int y, int z) {
    return (x < 0) || (x >= NX) || (y < 0) || (y >= NY) || (z < 0) || (z >= NZ);
}

/* ==================== MAT File Writer ==================== */
static int pad_size(int n) { return (8 - (n % 8)) % 8; }

static void write4(FILE *fp, uint32_t val) { fwrite(&val, 4, 1, fp); }

static void write_tag(FILE *fp, int type, int size) {
    write4(fp, (uint32_t)type);
    write4(fp, (uint32_t)size);
}

static void write_array_to_mat(FILE *fp, const char *name, const float *data) {
    int name_len = (int)strlen(name);
    int name_padded = name_len + pad_size(name_len);
    int numel = NX * NY * NZ;
    int data_size = numel * 8;
    int dims_size = 12;
    int flags_size = 8;
    int content_size = flags_size + dims_size + (4 + name_padded) + data_size;
    int i, x, y, z;
    
    write_tag(fp, MI_MATRIX, content_size);
    write_tag(fp, MI_UINT32, 8);
    write4(fp, (MX_DOUBLE_CLASS << 8));
    write4(fp, 0);
    write_tag(fp, MI_INT32, dims_size);
    write4(fp, NZ);
    write4(fp, NY);
    write4(fp, NX);
    write_tag(fp, MI_INT8, name_len);
    fwrite(name, 1, name_len, fp);
    
    for (i = 0; i < pad_size(name_len); i++) fputc(0, fp);
    write_tag(fp, MI_DOUBLE, data_size);
    
    for (z = 0; z < NZ; z++) {
        for (y = 0; y < NY; y++) {
            for (x = 0; x < NX; x++) {
                int idx = x + y * NX + z * NX * NY;
                double val = (double)data[idx];
                fwrite(&val, 8, 1, fp);
            }
        }
    }
}

void output_mat(int step) {
    char filename[256];
    sprintf(filename, "spacer_flow_%04d.mat", step);
    
    FILE *fp = fopen(filename, "wb");
    if (!fp) {
        fprintf(stderr, "Error: Cannot create %s\n", filename);
        return;
    }
    
    char header[128] = {0};
    snprintf(header, 116, "MATLAB 5.0 MAT-file, RO Spacer LBM Step %d", step);
    /* Bytes 116-123: Subsystem data offset (8 bytes, all 0) */
    /* Bytes 124-125: Version (0x0100) */
    header[124] = 0x00;
    header[125] = 0x01;
    /* Bytes 126-127: Endian indicator 'MI' for little-endian */
    header[126] = 'M';
    header[127] = 'I';
    fwrite(header, 128, 1, fp);
    
    write_array_to_mat(fp, "ux", ux);
    write_array_to_mat(fp, "uy", uy);
    write_array_to_mat(fp, "uz", uz);
    write_array_to_mat(fp, "rho", rho);
    
    fclose(fp);
    printf("  [MAT] Saved: %s (ux, uy, uz, rho)\n", filename);
}

/* ==================== LBM Functions ==================== */
void computeFeq(int id, float* feq) {
    float rhoid = rho[id];
    float uid = ux[id];
    float vid = uy[id];
    float wid = uz[id];
    float udotu = uid*uid + vid*vid + wid*wid;
    int j;
    
    for (j = 0; j < Q; j++) {
        float edotu = e[j][0]*uid + e[j][1]*vid + e[j][2]*wid;
        feq[j] = rhoid * w[j] * (1.0 + 3.0*edotu + 4.5*edotu*edotu - 1.5*udotu);
    }
}

void collide() {
    float feq[Q];
    int id, j;
    
    for (id = 0; id < NT; id++) {
        if (nodeType[id] == 's') continue;
        computeFeq(id, feq);
        for (j = 0; j < Q; j++) {
            fcol[id][j] = f[id][j] - (f[id][j] - feq[j]) / tau;
        }
    }
}

void stream() {
    int id, j;
    
    for (id = 0; id < NT; id++) {
        if (nodeType[id] == 's' || nodeType[id] == 'o') continue;
        
        int x = getX(id);
        int y = getY(id);
        int z = getZ(id);
        char nt = nodeType[id];
        
        for (j = 0; j < Q; j++) {
            int xpre = x - e[j][0];
            int ypre = y - e[j][1];
            int zpre = z - e[j][2];
            
            if (nt == 'i') {
                if (!outRange(xpre, ypre, zpre)) {
                    int idxpre = getIndex(xpre, ypre, zpre);
                    f[id][j] = fcol[idxpre][j];
                }
            } else if (nt == 'b') {
                if (outRange(xpre, ypre, zpre) || nodeType[getIndex(xpre, ypre, zpre)] == 's') {
                    f[id][j] = fcol[id][oppoDir[j]];
                } else {
                    int idxpre = getIndex(xpre, ypre, zpre);
                    f[id][j] = fcol[idxpre][j];
                }
            }
        }
    }
}

void computeMacro() {
    int id, j;
    
    for (id = 0; id < NT; id++) {
        if (nodeType[id] == 's') continue;
        
        float r = 0, u = 0, v = 0, w = 0;
        for (j = 0; j < Q; j++) {
            r += f[id][j];
            u += e[j][0] * f[id][j];
            v += e[j][1] * f[id][j];
            w += e[j][2] * f[id][j];
        }
        rho[id] = r;
        ux[id] = u / r;
        uy[id] = v / r;
        uz[id] = w / r;
    }
}

void applyBoundary() {
    int x, y, z, j;
    
    for (y = 0; y < NY; y++) {
        for (z = 0; z < NZ; z++) {
            int id_in = getIndex(0, y, z);
            int id_out = getIndex(NX-1, y, z);
            for (j = 0; j < Q; j++) {
                if (e[j][0] > 0) f[id_in][j] = fcol[id_out][j];
                if (e[j][0] < 0) f[id_out][j] = fcol[id_in][j];
            }
        }
    }
    
    for (x = 0; x < NX; x++) {
        for (z = 0; z < NZ; z++) {
            int id_front = getIndex(x, 0, z);
            int id_rear = getIndex(x, NY-1, z);
            for (j = 0; j < Q; j++) {
                if (e[j][1] > 0) f[id_front][j] = fcol[id_rear][j];
                if (e[j][1] < 0) f[id_rear][j] = fcol[id_front][j];
            }
        }
    }
    
    for (x = 0; x < NX; x++) {
        for (y = 0; y < NY; y++) {
            int id_down = getIndex(x, y, 0);
            int id_up = getIndex(x, y, NZ-1);
            for (j = 0; j < Q; j++) {
                if (e[j][2] > 0) f[id_down][j] = fcol[id_down][oppoDir[j]];
                if (e[j][2] < 0) f[id_up][j] = fcol[id_up][oppoDir[j]];
            }
        }
    }
}

void init() {
    int id, x, y, z, j;
    float feq[Q];
    int solid_count = 0;
    
    printf("========================================\n");
    printf("RO Spacer LBM - Pure C Version\n");
    printf("Grid: %d x %d x %d = %d cells\n", NX, NY, NZ, NT);
    printf("========================================\n");
    
    for (id = 0; id < NT; id++) {
        rho[id] = 1.0f;
        ux[id] = uy[id] = uz[id] = 0.0f;
        nodeType[id] = 'i';
        x = getX(id); y = getY(id); z = getZ(id);
        if (z == 0 || x == 0 || y == 0 || x == NX-1 || y == NY-1 || z == NZ-1) {
            nodeType[id] = 'o';
        }
    }
    
    printf("Generating spacer geometry...\n");
    
    for (id = 0; id < NT; id++) {
        x = getX(id); y = getY(id); z = getZ(id);
        float x_phys = x * dx;
        float y_phys = y * dx;
        float z_phys = z * dx;
        int isSolid = 0;
        float c, c1, c2;
        float diamond_diag_val = pitch * sqrtf(2.0f);
        
        for (c = -NY*dx; c <= NX*dx + NY*dx; c += diamond_diag_val) {
            float dist_xy = fabsf(x_phys - y_phys - c) / sqrtf(2.0f);
            float dist_z = fabsf(z_phys - z_fiber_center);
            if (dist_xy < r_fiber && dist_z < r_fiber) { isSolid = 1; break; }
        }
        if (isSolid) goto mark_solid;
        
        for (c = 0; c <= NX*dx + NY*dx; c += diamond_diag_val) {
            float dist_xy = fabsf(x_phys + y_phys - c) / sqrtf(2.0f);
            float dist_z = fabsf(z_phys - z_fiber_center);
            if (dist_xy < r_fiber && dist_z < r_fiber) { isSolid = 1; break; }
        }
        if (isSolid) goto mark_solid;
        
        for (c1 = -NY*dx; c1 <= NX*dx + NY*dx; c1 += diamond_diag_val) {
            for (c2 = 0; c2 <= NX*dx + NY*dx; c2 += diamond_diag_val) {
                float x_cross = (c1 + c2) / 2.0f;
                float y_cross = (c2 - c1) / 2.0f;
                if (x_cross >= 0 && x_cross <= NX*dx && y_cross >= 0 && y_cross <= NY*dx) {
                    float dist = sqrtf((x_phys-x_cross)*(x_phys-x_cross) + 
                                      (y_phys-y_cross)*(y_phys-y_cross) + 
                                      (z_phys-z_fiber_center)*(z_phys-z_fiber_center));
                    if (dist < r_node) { isSolid = 1; break; }
                }
            }
            if (isSolid) break;
        }
        
    mark_solid:
        if (isSolid) { nodeType[id] = 's'; solid_count++; }
    }
    
    for (id = 0; id < NT; id++) {
        if (nodeType[id] != 's') {
            x = getX(id); y = getY(id); z = getZ(id);
            for (j = 0; j < Q; j++) {
                int xnb = x + e[j][0];
                int ynb = y + e[j][1];
                int znb = z + e[j][2];
                if (outRange(xnb, ynb, znb)) continue;
                if (nodeType[getIndex(xnb, ynb, znb)] == 's') { nodeType[id] = 'b'; break; }
            }
        }
    }
    
    float porosity = 1.0f - (float)solid_count / NT;
    printf("Solid nodes: %d / %d\n", solid_count, NT);
    printf("Porosity: %.2f%%\n", porosity * 100.0f);
    printf("========================================\n");
    
    for (id = 0; id < NT; id++) {
        if (nodeType[id] == 's') {
            for (j = 0; j < Q; j++) f[id][j] = 0;
            continue;
        }
        computeFeq(id, feq);
        for (j = 0; j < Q; j++) f[id][j] = feq[j];
    }
}

void output_dat(int step) {
    char name[256];
    FILE* fp;
    int id;
    
    sprintf(name, "spacer_flow_%04d.dat", step);
    fp = fopen(name, "w");
    
    fprintf(fp, "TITLE=\"RO Spacer Flow - Step %d\"\n", step);
    fprintf(fp, "VARIABLES=\"X\",\"Y\",\"Z\",\"U\",\"V\",\"W\",\"RHO\"\n");
    fprintf(fp, "ZONE T=\"FLOW\", I=%d, J=%d, K=%d, F=POINT\n", NX, NY, NZ);
    
    for (id = 0; id < NT; id++) {
        fprintf(fp, "%d %d %d %f %f %f %f\n", 
                getX(id), getY(id), getZ(id),
                ux[id], uy[id], uz[id], rho[id]);
    }
    fclose(fp);
    printf("  [DAT] Saved: %s\n", name);
}

void output(int step) {
    output_dat(step);
    output_mat(step);
}

void outputGeometry() {
    FILE* fp = fopen("geometry.dat", "w");
    int id;
    
    fprintf(fp, "TITLE=\"Spacer Geometry\"\n");
    fprintf(fp, "VARIABLES=\"X\",\"Y\",\"Z\",\"Type\"\n");
    fprintf(fp, "ZONE T=\"GEOM\", I=%d, J=%d, K=%d, F=POINT\n", NX, NY, NZ);
    
    for (id = 0; id < NT; id++) {
        int type = 0;
        if (nodeType[id] == 's') type = 1;
        else if (nodeType[id] == 'b') type = 2;
        fprintf(fp, "%d %d %d %d\n", getX(id), getY(id), getZ(id), type);
    }
    fclose(fp);
    printf("Geometry output: geometry.dat\n");
}

int main() {
    int step, maxStep = 100, outputInterval = 50;
    
    init();
    outputGeometry();
    
    printf("\nStarting simulation (100 steps test)...\n");
    printf("Output format: .dat (Tecplot) + .mat (MATLAB)\n\n");
    
    for (step = 1; step <= maxStep; step++) {
        collide();
        stream();
        applyBoundary();
        computeMacro();
        
        if (step % 10 == 0) printf("Step %d / %d\n", step, maxStep);
        if (step % outputInterval == 0) output(step);
    }
    
    printf("\n========================================\n");
    printf("Simulation complete!\n");
    printf("Max step: %d\n", maxStep);
    printf("Output files: spacer_flow_*.dat, spacer_flow_*.mat, geometry.dat\n");
    printf("========================================\n");
    
    return 0;
}
