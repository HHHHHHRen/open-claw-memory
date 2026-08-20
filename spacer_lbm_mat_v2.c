/*
 * RO Spacer LBM - MAT Output (Fixed Header)
 * Compile: clang -O3 spacer_lbm_mat.c -o test_mat -lm
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <stdint.h>

#define NX 340
#define NY 113
#define NZ 24
#define NT (NX*NY*NZ)

float rho[NT], ux[NT], uy[NT], uz[NT];

/* MAT v5 Format Constants */
#define MI_INT8    1
#define MI_UINT8   2
#define MI_INT16   3
#define MI_UINT16  4
#define MI_INT32   5
#define MI_UINT32  6
#define MI_SINGLE  7
#define MI_DOUBLE  9
#define MI_MATRIX  14
#define MX_DOUBLE_CLASS 6

typedef struct {
    uint32_t type;
    uint32_t size;
} MatElementTag;

static int pad_to_8(int n) {
    int r = n % 8;
    return r == 0 ? 0 : 8 - r;
}

/* Write a 3D array to MAT file
 * data is stored in C-order [x][y][z], written as MATLAB-order [z][y][x]
 */
void write_mat_array(FILE *fp, const char *name, const float *data) {
    int i, j, k;
    int namelen = strlen(name);
    int namepad = pad_to_8(namelen);
    int nelem = NX * NY * NZ;
    int databytes = nelem * 8;  /* double precision */
    int datapad = pad_to_8(databytes);
    
    /* Sub-element sizes (tag + data) */
    int arrayflags_bytes = 8 + 8;  /* tag(8) + data(8) */
    int dims_bytes = 8 + 12 + pad_to_8(12);  /* tag(8) + 3*int32(12) + pad */
    int name_bytes = 8 + namelen + namepad;  /* tag(8) + name + pad */
    int data_bytes = 8 + databytes + datapad;  /* tag(8) + data + pad */
    
    int total_matrix_bytes = arrayflags_bytes + dims_bytes + name_bytes + data_bytes - 8; /* -8 for outer tag not included */
    
    MatElementTag tag;
    
    /* 1. Matrix element header */
    tag.type = MI_MATRIX;
    tag.size = total_matrix_bytes;
    fwrite(&tag, sizeof(tag), 1, fp);
    
    /* 2. Array Flags (8 bytes data) */
    tag.type = MI_UINT32;
    tag.size = 8;
    fwrite(&tag, sizeof(tag), 1, fp);
    uint32_t flags[2] = {(MX_DOUBLE_CLASS << 8), 0};
    fwrite(flags, sizeof(flags), 1, fp);
    
    /* 3. Dimensions Array */
    tag.type = MI_INT32;
    tag.size = 12;  /* 3 dimensions */
    fwrite(&tag, sizeof(tag), 1, fp);
    int32_t dims[3] = {NZ, NY, NX};  /* MATLAB column-major order */
    fwrite(dims, sizeof(dims), 1, fp);
    /* Padding to 8 bytes */
    for (i = 0; i < pad_to_8(12); i++) fputc(0, fp);
    
    /* 4. Array Name */
    tag.type = MI_INT8;
    tag.size = namelen;
    fwrite(&tag, sizeof(tag), 1, fp);
    fwrite(name, 1, namelen, fp);
    for (i = 0; i < namepad; i++) fputc(0, fp);
    
    /* 5. Real Data */
    tag.type = MI_DOUBLE;
    tag.size = databytes;
    fwrite(&tag, sizeof(tag), 1, fp);
    
    /* Write in column-major order (z changes fastest in MATLAB) */
    for (k = 0; k < NZ; k++) {
        for (j = 0; j < NY; j++) {
            for (i = 0; i < NX; i++) {
                int c_idx = i + j*NX + k*NX*NY;
                double val = (double)data[c_idx];
                fwrite(&val, sizeof(double), 1, fp);
            }
        }
    }
    for (i = 0; i < datapad; i++) fputc(0, fp);
}

void output_mat(int step) {
    char fname[256];
    sprintf(fname, "spacer_flow_%04d.mat", step);
    FILE *fp = fopen(fname, "wb");
    if (!fp) { perror("fopen"); return; }
    
    /* 128-byte header
     * Bytes 0-115:   Descriptive text (116 bytes)
     * Bytes 116-123: Subsystem data offset (uint64, 8 bytes) - must be 0
     * Bytes 124-125: Version (uint16) - 0x0100
     * Bytes 126-127: Endian indicator - "MI" for little-endian
     */
    char header[128];
    memset(header, 0, 128);
    
    /* Text description (max 116 chars) */
    const char *desc = "MATLAB 5.0 MAT-file, Platform: GLNXA64, Created by LBM";
    memcpy(header, desc, strlen(desc));
    
    /* Bytes 116-123: Subsystem data offset (8 bytes, all zeros) - already zeroed by memset */
    
    /* Bytes 124-125: Version = 0x0100 (little-endian: 0x00, 0x01) */
    header[124] = 0x00;
    header[125] = 0x01;
    
    /* Bytes 126-127: Endian indicator "MI" */
    header[126] = 'M';
    header[127] = 'I';
    
    fwrite(header, 128, 1, fp);
    
    /* Write variables */
    write_mat_array(fp, "ux", ux);
    write_mat_array(fp, "uy", uy);
    write_mat_array(fp, "uz", uz);
    write_mat_array(fp, "rho", rho);
    
    fclose(fp);
    printf("[MAT] Saved: %s\n", fname);
}

/* ==================== Test ==================== */
int main() {
    printf("MAT Output Test: %dx%dx%d\n\n", NX, NY, NZ);
    
    /* Fill with recognizable test data */
    for (int i = 0; i < NT; i++) {
        rho[i] = 1.0f;
        ux[i] = 0.1f;
        uy[i] = 0.2f;
        uz[i] = 0.3f;
    }
    /* Put some variation so we can verify */
    ux[0] = 1.0f; ux[NX-1] = 2.0f;
    uy[0] = 3.0f; uy[NY*NX-1] = 4.0f;
    
    output_mat(50);
    
    printf("\nMATLAB verification:\n");
    printf("  data = load('spacer_flow_0050.mat');\n");
    printf("  data.ux(1,1,1)      %% Should be 1.0\n");
    printf("  data.ux(end,1,1)    %% Should be 2.0\n");
    printf("  size(data.ux)       %% Should be [24 113 340]\n");
    
    return 0;
}
