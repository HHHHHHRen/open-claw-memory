/*
 * RO Spacer LBM - Diamond Pattern Spacer (3 crosses)
 * Fiber diameter: 1.0mm, Node diameter: 1.22mm, Pitch: 4.0mm
 * Grid: 339 x 113 x 40, Periodic BC in X/Y, Wall BC in Z
 * 
 * Compile: nvcc -O3 spacer_lbm.cu -o spacer_lbm
 * Run: ./spacer_lbm
 */

#include <map>
#include "cuda.h"
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <string>
#include <iostream>
#include <fstream>
#include <sstream>
#include <math.h>
#include <cmath>
#include <cstdlib>
#include <vector>
#include <iomanip>
#include <algorithm>
#include <stdlib.h>
#include <time.h>

#define D 3
#define Q 27
#define U 0.1f
#define e_mac 2.0f
#define tau_mac 0.5015f

using namespace std;

// ========== Geometry Parameters ==========
const float dx = 0.05f;           // mm, grid spacing
const float pitch = 4.0f;         // mm, fiber pitch
const float d_fiber = 1.0f;       // mm, fiber diameter
const float r_fiber = 0.5f;       // mm, fiber radius
const float d_node = 1.22f;       // mm, node diameter
const float r_node = 0.61f;       // mm, node radius
const float diamond_diag = pitch * sqrtf(2.0f);  // ~5.657 mm
const int num_cross = 3;          // 3 crosses in X direction

// Grid dimensions
const int NX = 339;   // round(3 * 5.657 / 0.05)
const int NY = 113;   // round(5.657 / 0.05)
const int NZ = 40;    // round(2.0 / 0.05)
const int NT = NX * NY * NZ;

const int threadsPerBlock = 128;
const int blocksPerGrid = (NT + threadsPerBlock - 1) / threadsPerBlock;

// ========== Global Variables ==========
float* h_ux; float* h_uy; float* h_uz;
float* h_uxA; float* h_uyA; float* h_uzA;
float* h_TX; float* h_TY; float* h_TXY; float* h_TKE;
float* h_rho;
char* h_nodeType;

int* h_flag;
int* d_flag;

cudaError_t err;
inline void printCudaError(string funcName) {
    err = cudaGetLastError();
    if (err != cudaSuccess) {
        cout << funcName << " : " << cudaGetErrorString(err) << endl;
    }
}

// ========== Structure ==========
struct varb {
    float* fval[Q];
    float* fcol[Q];
    float* rho;
    float* ux;
    float* uy;
    float* uz;
    float* uxA;
    float* uyA;
    float* uzA;
    float* TX;
    float* TY;
    float* TXY;
    float* TKE;
    char* nodeType;
};

__constant__ varb d[1];
varb dVar;

// ========== Constant Memory ==========
__constant__ double w[Q];
__constant__ float eP[8];
__constant__ int eUnit[Q * D];
__constant__ float ePhy[Q * D];
__constant__ int oppoDir[Q];
__constant__ int N[4];

// ========== Inline Functions ==========
inline int getZ(const int i) { return i / (NX * NY); }
inline int getX(const int i) { return i % NX; }
inline int getY(const int i) { return (i - NX * NY * getZ(i)) / NX; }
inline int h_getIndex(int x, int y, int z) { return (x + y * NX + z * NX * NY); }

__device__ __inline__ int getIndex(int x, int y, int z) { 
    return (x + y * NX + z * NX * NY); 
}

__device__ __inline__ bool outRange(int x, int y, int z) {
    return (x < 0) || (x > NX - 1) || (y < 0) || (y > NY - 1) || (z < 0) || (z > NZ - 1);
}

// ========== Device Functions ==========
__device__ void computeFeq(float* feq, int id) {
    float rhoid = d[0].rho[id];
    float uid = d[0].ux[id];
    float vid = d[0].uy[id];
    float wid = d[0].uz[id];
    
    float fuuvvww = 1.5f * (uid * uid + vid * vid + wid * wid) * eP[2];
    
    for (int j = 0; j < Q; j++) {
        float eu = ePhy[j * D] * uid + ePhy[j * D + 1] * vid + ePhy[j * D + 2] * wid;
        feq[j] = rhoid * w[j] * (1.0 + 3.0 * eu * eP[2] + 4.5 * eu * eu * eP[4] - fuuvvww);
    }
}

__device__ void computeMacro(int id) {
    float rho = 0, ux = 0, uy = 0, uz = 0;
    for (int j = 0; j < Q; j++) {
        rho += d[0].fval[j][id];
        ux += ePhy[j * D] * d[0].fval[j][id];
        uy += ePhy[j * D + 1] * d[0].fval[j][id];
        uz += ePhy[j * D + 2] * d[0].fval[j][id];
    }
    d[0].rho[id] = rho;
    d[0].ux[id] = ux / rho;
    d[0].uy[id] = uy / rho;
    d[0].uz[id] = uz / rho;
}

// ========== Kernel Functions ==========
__global__ void initDev() {
    int id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= NT) return;
    
    d[0].rho[id] = 1.0f;
    d[0].ux[id] = 0.0f;
    d[0].uy[id] = 0.0f;
    d[0].uz[id] = 0.0f;
    d[0].uxA[id] = 0.0f;
    d[0].uyA[id] = 0.0f;
    d[0].uzA[id] = 0.0f;
    d[0].TX[id] = 0.0f;
    d[0].TY[id] = 0.0f;
    d[0].TXY[id] = 0.0f;
    d[0].TKE[id] = 0.0f;
}

__global__ void initFval() {
    int id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= NT) return;
    if (d[0].nodeType[id] == 's') return;
    
    float feq[Q];
    computeFeq(feq, id);
    for (int j = 0; j < Q; j++) {
        d[0].fval[j][id] = feq[j];
    }
}

__global__ void collideMRT() {
    int id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= NT) return;
    if (d[0].nodeType[id] == 's') return;
    
    float f[Q], feq[Q], fcol[Q];
    for (int j = 0; j < Q; j++) f[j] = d[0].fval[j][id];
    
    computeFeq(feq, id);
    
    // Simplified BGK collision (replace with MRT if needed)
    float tau = tau_mac;
    for (int j = 0; j < Q; j++) {
        fcol[j] = f[j] - (f[j] - feq[j]) / tau;
        d[0].fcol[j][id] = fcol[j];
    }
}

__global__ void streamAmacro() {
    int id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= NT) return;
    if (d[0].nodeType[id] == 's' || d[0].nodeType[id] == 'o') return;
    
    int z = id / (NX * NY);
    int x = id % NX;
    int y = (id - NX * NY * z) / NX;
    
    char nt = d[0].nodeType[id];
    
    for (int j = 0; j < Q; j++) {
        int xpre = x - eUnit[j * D];
        int ypre = y - eUnit[j * D + 1];
        int zpre = z - eUnit[j * D + 2];
        
        if (nt == 'i') {
            int idxpre = getIndex(xpre, ypre, zpre);
            d[0].fval[j][id] = d[0].fcol[j][idxpre];
        } else if (nt == 'b') {
            int idxpre = getIndex(xpre, ypre, zpre);
            if (outRange(xpre, ypre, zpre) || d[0].nodeType[idxpre] == 's') {
                d[0].fval[j][id] = d[0].fcol[oppoDir[j]][id];
            } else {
                d[0].fval[j][id] = d[0].fcol[j][idxpre];
            }
        }
    }
    
    computeMacro(id);
}

__global__ void streamAmacroAver() {
    int id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= NT) return;
    if (d[0].nodeType[id] == 's' || d[0].nodeType[id] == 'o') return;
    
    int z = id / (NX * NY);
    int x = id % NX;
    int y = (id - NX * NY * z) / NX;
    
    char nt = d[0].nodeType[id];
    
    for (int j = 0; j < Q; j++) {
        int xpre = x - eUnit[j * D];
        int ypre = y - eUnit[j * D + 1];
        int zpre = z - eUnit[j * D + 2];
        
        if (nt == 'i') {
            int idxpre = getIndex(xpre, ypre, zpre);
            d[0].fval[j][id] = d[0].fcol[j][idxpre];
        } else if (nt == 'b') {
            int idxpre = getIndex(xpre, ypre, zpre);
            if (outRange(xpre, ypre, zpre) || d[0].nodeType[idxpre] == 's') {
                d[0].fval[j][id] = d[0].fcol[oppoDir[j]][id];
            } else {
                d[0].fval[j][id] = d[0].fcol[j][idxpre];
            }
        }
    }
    
    computeMacro(id);
    
    float ux = d[0].ux[id];
    float uy = d[0].uy[id];
    float uz = d[0].uz[id];
    
    d[0].uxA[id] += ux;
    d[0].uyA[id] += uy;
    d[0].uzA[id] += uz;
    d[0].TX[id] += ux * ux;
    d[0].TY[id] += uy * uy;
    d[0].TXY[id] += ux * uy;
    d[0].TKE[id] += ux * ux + uy * uy + uz * uz;
}

__global__ void resetAverage() {
    int id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= NT) return;
    if (d[0].nodeType[id] == 's') return;
    
    d[0].uxA[id] = 0.0f;
    d[0].uyA[id] = 0.0f;
    d[0].uzA[id] = 0.0f;
    d[0].TX[id] = 0.0f;
    d[0].TY[id] = 0.0f;
    d[0].TXY[id] = 0.0f;
    d[0].TKE[id] = 0.0f;
}

// ========== Boundary Conditions ==========
// X direction periodic
__global__ void boundaryPeriodicX() {
    int y = threadIdx.x;
    int z = blockIdx.x;
    
    int id_in = getIndex(0, y, z);
    int id_out = getIndex(NX - 1, y, z);
    
    for (int j = 0; j < Q; j++) {
        if (eUnit[j * D] > 0) {
            d[0].fval[j][id_in] = d[0].fcol[j][id_out];
        }
        if (eUnit[j * D] < 0) {
            d[0].fval[j][id_out] = d[0].fcol[j][id_in];
        }
    }
}

// Y direction periodic
__global__ void boundaryPeriodicY() {
    int x = threadIdx.x;
    int z = blockIdx.x;
    
    int id_front = getIndex(x, 0, z);
    int id_rear = getIndex(x, NY - 1, z);
    
    for (int j = 0; j < Q; j++) {
        if (eUnit[j * D + 1] > 0) {
            d[0].fval[j][id_front] = d[0].fcol[j][id_rear];
        }
        if (eUnit[j * D + 1] < 0) {
            d[0].fval[j][id_rear] = d[0].fcol[j][id_front];
        }
    }
}

// Z direction wall (membrane surfaces)
__global__ void boundaryWallZ() {
    int x = threadIdx.x;
    int y = blockIdx.x;
    
    int id_down = getIndex(x, y, 0);
    int id_up = getIndex(x, y, NZ - 1);
    
    for (int j = 0; j < Q; j++) {
        if (eUnit[j * D + 2] > 0) {
            d[0].fval[j][id_down] = d[0].fcol[oppoDir[j]][id_down];
        }
        if (eUnit[j * D + 2] < 0) {
            d[0].fval[j][id_up] = d[0].fcol[oppoDir[j]][id_up];
        }
    }
}

__global__ void error(int* d_flag) {
    int id = blockDim.x * blockIdx.x + threadIdx.x;
    if (id >= NT) return;
    
    if (d[0].rho[id] < 0 || isnan(d[0].rho[id])) {
        d_flag[0] = -1;
        d[0].rho[id] = 9999.0f;
    }
}

// ========== Initialization ==========
void init() {
    // Host memory allocation
    cudaMallocHost((void**)&h_ux, NT * sizeof(float));
    cudaMallocHost((void**)&h_uy, NT * sizeof(float));
    cudaMallocHost((void**)&h_uz, NT * sizeof(float));
    cudaMallocHost((void**)&h_uxA, NT * sizeof(float));
    cudaMallocHost((void**)&h_uyA, NT * sizeof(float));
    cudaMallocHost((void**)&h_uzA, NT * sizeof(float));
    cudaMallocHost((void**)&h_TX, NT * sizeof(float));
    cudaMallocHost((void**)&h_TY, NT * sizeof(float));
    cudaMallocHost((void**)&h_TXY, NT * sizeof(float));
    cudaMallocHost((void**)&h_TKE, NT * sizeof(float));
    cudaMallocHost((void**)&h_rho, NT * sizeof(float));
    cudaMallocHost((void**)&h_nodeType, NT * sizeof(char));
    
    cudaMallocHost((void**)&h_flag, sizeof(int));
    cudaMalloc((void**)&d_flag, sizeof(int));
    h_flag[0] = 666;
    cudaMemcpy(d_flag, h_flag, sizeof(int), cudaMemcpyHostToDevice);
    
    // Device memory allocation
    for (int j = 0; j < Q; j++) {
        cudaMalloc((void**)&dVar.fval[j], NT * sizeof(float));
        cudaMalloc((void**)&dVar.fcol[j], NT * sizeof(float));
    }
    cudaMalloc((void**)&dVar.rho, NT * sizeof(float));
    cudaMalloc((void**)&dVar.ux, NT * sizeof(float));
    cudaMalloc((void**)&dVar.uy, NT * sizeof(float));
    cudaMalloc((void**)&dVar.uz, NT * sizeof(float));
    cudaMalloc((void**)&dVar.uxA, NT * sizeof(float));
    cudaMalloc((void**)&dVar.uyA, NT * sizeof(float));
    cudaMalloc((void**)&dVar.uzA, NT * sizeof(float));
    cudaMalloc((void**)&dVar.TX, NT * sizeof(float));
    cudaMalloc((void**)&dVar.TY, NT * sizeof(float));
    cudaMalloc((void**)&dVar.TXY, NT * sizeof(float));
    cudaMalloc((void**)&dVar.TKE, NT * sizeof(float));
    cudaMalloc((void**)&dVar.nodeType, NT * sizeof(char));
    
    printCudaError("cudaMalloc");
    
    // Constant memory initialization
    float e = e_mac;
    float ee = e * e, eee = ee * e, eeee = ee * ee;
    float e_1 = 1.0f / e, ee_1 = 1.0f / ee, eee_1 = 1.0f / eee, eeee_1 = 1.0f / eeee;
    float h_e[8] = {e, e_1, ee_1, eee_1, eeee_1, ee, eee, eeee};
    cudaMemcpyToSymbol(eP, h_e, 8 * sizeof(float));
    
    double h_w[Q] = {8.0/27, 2.0/27, 2.0/27, 2.0/27, 2.0/27, 2.0/27, 2.0/27,
        1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54,
        1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216};
    
    int h_eUnit[D*Q] = {0,0,0, 1,0,0, 0,1,0, -1,0,0, 0,-1,0, 0,0,1, 0,0,-1,
        1,1,0, -1,1,0, -1,-1,0, 1,-1,0, 1,0,1, 0,1,1, -1,0,1, 0,-1,1, 1,0,-1, 0,1,-1, -1,0,-1, 0,-1,-1,
        1,1,1, -1,1,1, -1,-1,1, 1,-1,1, 1,1,-1, -1,1,-1, -1,-1,-1, 1,-1,-1};
    
    float h_ePhy[D*Q] = {0,0,0, e,0,0, 0,e,0, -e,0,0, 0,-e,0, 0,0,e, 0,0,-e,
        e,e,0, -e,e,0, -e,-e,0, e,-e,0, e,0,e, 0,e,e, -e,0,e, 0,-e,e, e,0,-e, 0,e,-e, -e,0,-e, 0,-e,-e,
        e,e,e, -e,e,e, -e,-e,e, e,-e,e, e,e,-e, -e,e,-e, -e,-e,-e, e,-e,-e};
    
    int h_oppoDir[Q] = {0,3,4,1,2,6,5,9,10,7,8,17,18,15,16,13,14,11,12,25,26,23,24,21,22,19,20};
    int h_GridSize[4] = {NT, NX, NY, NZ};
    
    cudaMemcpyToSymbol(w, h_w, Q * sizeof(double));
    cudaMemcpyToSymbol(eUnit, h_eUnit, Q * D * sizeof(int));
    cudaMemcpyToSymbol(ePhy, h_ePhy, Q * D * sizeof(float));
    cudaMemcpyToSymbol(oppoDir, h_oppoDir, Q * sizeof(int));
    cudaMemcpyToSymbol(N, h_GridSize, 4 * sizeof(int));
    
    printCudaError("constant memory");
    
    // Initialize all nodes as fluid
    for (int i = 0; i < NT; i++) {
        h_ux[i] = h_uy[i] = h_uz[i] = 0.0f;
        h_uxA[i] = h_uyA[i] = h_uzA[i] = 0.0f;
        h_rho[i] = 1.0f;
        h_nodeType[i] = 'i';
        
        int X = getX(i), Y = getY(i), Z = getZ(i);
        if (Z == 0 || X == 0 || Y == 0 || X == NX - 1 || Y == NY - 1 || Z == NZ - 1)
            h_nodeType[i] = 'o';
    }
    
    // ========== Generate Diamond Spacer Geometry ==========
    cout << "Generating spacer geometry..." << endl;
    float z_fiber_center = r_fiber;  // 0.5 mm
    int solid_count = 0;
    
    for (int i = 0; i < NT; i++) {
        int x = getX(i);
        int y = getY(i);
        int z = getZ(i);
        
        float x_phys = x * dx;
        float y_phys = y * dx;
        float z_phys = z * dx;
        
        bool isSolid = false;
        
        // Lower fibers (+45°): x - y = c
        for (float c = -NY*dx; c <= NX*dx + NY*dx; c += diamond_diag) {
            float dist_xy = fabsf(x_phys - y_phys - c) / sqrtf(2.0f);
            float dist_z = fabsf(z_phys - z_fiber_center);
            if (dist_xy < r_fiber && dist_z < r_fiber) {
                isSolid = true;
                break;
            }
        }
        if (isSolid) goto mark_solid;
        
        // Upper fibers (-45°): x + y = c
        for (float c = 0; c <= NX*dx + NY*dx; c += diamond_diag) {
            float dist_xy = fabsf(x_phys + y_phys - c) / sqrtf(2.0f);
            float dist_z = fabsf(z_phys - z_fiber_center);
            if (dist_xy < r_fiber && dist_z < r_fiber) {
                isSolid = true;
                break;
            }
        }
        if (isSolid) goto mark_solid;
        
        // Spherical nodes
        for (float c1 = -NY*dx; c1 <= NX*dx + NY*dx; c1 += diamond_diag) {
            for (float c2 = 0; c2 <= NX*dx + NY*dx; c2 += diamond_diag) {
                float x_cross = (c1 + c2) / 2.0f;
                float y_cross = (c2 - c1) / 2.0f;
                
                if (x_cross >= 0 && x_cross <= NX*dx && y_cross >= 0 && y_cross <= NY*dx) {
                    float dist = sqrtf((x_phys-x_cross)*(x_phys-x_cross) + 
                                     (y_phys-y_cross)*(y_phys-y_cross) + 
                                     (z_phys-z_fiber_center)*(z_phys-z_fiber_center));
                    if (dist < r_node) {
                        isSolid = true;
                        break;
                    }
                }
            }
            if (isSolid) break;
        }
        
        mark_solid:
        if (isSolid) {
            h_nodeType[i] = 's';
            solid_count++;
        }
    }
    
    float porosity = 1.0f - (float)solid_count / NT;
    cout << "Solid nodes: " << solid_count << " / " << NT << endl;
    cout << "Porosity: " << porosity * 100.0f << "%" << endl;
    
    // Mark boundary nodes
    int h_eUnit_temp[D*Q] = {0,0,0, 1,0,0, 0,1,0, -1,0,0, 0,-1,0, 0,0,1, 0,0,-1,
        1,1,0, -1,1,0, -1,-1,0, 1,-1,0, 1,0,1, 0,1,1, -1,0,1, 0,-1,1, 1,0,-1, 0,1,-1, -1,0,-1, 0,-1,-1,
        1,1,1, -1,1,1, -1,-1,1, 1,-1,1, 1,1,-1, -1,1,-1, -1,-1,-1, 1,-1,-1};
    
    for (int i = 0; i < NT; i++) {
        if (h_nodeType[i] != 's') {
            int x = getX(i), y = getY(i), z = getZ(i);
            for (int j = 0; j < Q; j++) {
                int xnb = x + h_eUnit_temp[j*D];
                int ynb = y + h_eUnit_temp[j*D+1];
                int znb = z + h_eUnit_temp[j*D+2];
                if (xnb < 0 || ynb < 0 || znb < 0 || xnb >= NX || ynb >= NY || znb >= NZ) continue;
                if (h_nodeType[h_getIndex(xnb, ynb, znb)] == 's') {
                    h_nodeType[i] = 'b';
                    break;
                }
            }
        }
    }
    
    // Transfer to device
    cudaMemcpy(dVar.nodeType, h_nodeType, NT * sizeof(char), cudaMemcpyHostToDevice);
    cudaMemcpyToSymbol(d, &dVar, sizeof(varb));
    printCudaError("nodeType transfer");
    
    // Initialize fields
    initDev <<<blocksPerGrid, threadsPerBlock>>>();
    cudaDeviceSynchronize();
    printCudaError("initDev");
    
    initFval <<<blocksPerGrid, threadsPerBlock>>>();
    cudaDeviceSynchronize();
    printCudaError("initFval");
    
    cout << "Initialization complete!" << endl;
}

// ========== Output Functions ==========
void output(int s) {
    ostringstream name;
    name << "spacer_flow_" << s << ".dat";
    ofstream out(name.str().c_str());
    
    out << "TITLE=\"RO Spacer Flow\"\n";
    out << "VARIABLES=\"X\",\"Y\",\"Z\",\"U\",\"V\",\"W\"\n";
    out << "ZONE T=\"FLOW\", I=" << NX << ", J=" << NY << ", K=" << NZ << ", F=POINT\n";
    
    for (int i = 0; i < NT; i++) {
        out << getX(i) << " " << getY(i) << " " << getZ(i) << " "
            << h_ux[i] << " " << h_uy[i] << " " << h_uz[i] << "\n";
    }
    out.close();
    cout << "Output: " << name.str() << endl;
}

void outputAver(int s) {
    ostringstream name;
    name << "spacer_average_" << s << ".dat";
    ofstream out(name.str().c_str());
    
    out << "TITLE=\"RO Spacer Time-Averaged\"\n";
    out << "VARIABLES=\"X\",\"Y\",\"Z\",\"U\",\"V\",\"W\",\"UA\",\"VA\",\"WA\",\"TX\",\"TY\",\"TXY\",\"TKE\"\n";
    out << "ZONE T=\"AVERAGE\", I=" << NX << ", J=" << NY << ", K=" << NZ << ", F=POINT\n";
    
    float factor = 1.0f / timespan;
    for (int i = 0; i < NT; i++) {
        out << getX(i) << " " << getY(i) << " " << getZ(i) << " "
            << h_ux[i] << " " << h_uy[i] << " " << h_uz[i] << " "
            << h_uxA[i] * factor << " " << h_uyA[i] * factor << " " << h_uzA[i] * factor << " "
            << h_TX[i] * factor << " " << h_TY[i] * factor << " " 
            << h_TXY[i] * factor << " " << h_TKE[i] * factor << "\n";
    }
    out.close();
    cout << "Output: " << name.str() << endl;
}

void outputerror(int k) {
    ostringstream name;
    name << "error_" << k << ".dat";
    ofstream out(name.str().c_str());
    
    out << "TITLE=\"Error\"\n";
    out << "VARIABLES=\"X\",\"Y\",\"Z\",\"U\",\"V\",\"W\",\"RHO\"\n";
    out << "ZONE T=\"ERROR\", I=" << NX << ", J=" << NY << ", K=" << NZ << ", F=POINT\n";
    
    for (int i = 0; i < NT; i++) {
        out << getX(i) << " " << getY(i) << " " << getZ(i) << " "
            << h_ux[i] << " " << h_uy[i] << " " << h_uz[i] << " " << h_rho[i] << "\n";
    }
    out.close();
}

// ========== Cleanup ==========
void freeMem() {
    for (int j = 0; j < Q; j++) {
        cudaFree(dVar.fval[j]);
        cudaFree(dVar.fcol[j]);
    }
    cudaFree(dVar.rho);
    cudaFree(dVar.ux); cudaFree(dVar.uy); cudaFree(dVar.uz);
    cudaFree(dVar.uxA); cudaFree(dVar.uyA); cudaFree(dVar.uzA);
    cudaFree(dVar.TX); cudaFree(dVar.TY); cudaFree(dVar.TXY); cudaFree(dVar.TKE);
    cudaFree(dVar.nodeType);
    cudaFree(d_flag);
    
    cudaFreeHost(h_ux); cudaFreeHost(h_uy); cudaFreeHost(h_uz);
    cudaFreeHost(h_uxA); cudaFreeHost(h_uyA); cudaFreeHost(h_uzA);
    cudaFreeHost(h_TX); cudaFreeHost(h_TY); cudaFreeHost(h_TXY); cudaFreeHost(h_TKE);
    cudaFreeHost(h_rho);
    cudaFreeHost(h_nodeType);
    cudaFreeHost(h_flag);
    
    printCudaError("freeMem");
}

// ========== Main ==========
const int timespan = 60000;

int main() {
    cout << "========================================" << endl;
    cout << "RO Spacer LBM Simulation" << endl;
    cout << "Grid: " << NX << " x " << NY << " x " << NZ << " = " << NT << " cells" << endl;
    cout << "========================================" << endl;
    
    init();
    
    for (int k = 1; k <= 120000; k++) {
        collideMRT <<<blocksPerGrid, threadsPerBlock>>>();
        cudaDeviceSynchronize();
        
        if (k <= 60000) {
            streamAmacro <<<blocksPerGrid, threadsPerBlock>>>();
        } else {
            streamAmacroAver <<<blocksPerGrid, threadsPerBlock>>>();
        }
        cudaDeviceSynchronize();
        
        // Apply boundary conditions
        boundaryPeriodicX <<<NZ, NY>>>();
        cudaDeviceSynchronize();
        
        boundaryPeriodicY <<<NZ, NX>>>();
        cudaDeviceSynchronize();
        
        boundaryWallZ <<<NY, NX>>>();
        cudaDeviceSynchronize();
        
        if (k % 500 == 0) {
            cout << "Step " << k << " / 120000" << endl;
            
            error <<<blocksPerGrid, threadsPerBlock>>>(d_flag);
            cudaMemcpy(h_flag, d_flag, sizeof(int), cudaMemcpyDeviceToHost);
            
            if (h_flag[0] != 666) {
                cout << "ERROR: NaN detected at step " << k << endl;
                outputerror(k);
                return 1;
            }
            
            if (k == 20000 || k == 40000 || k == 60000) {
                cudaMemcpy(h_ux, dVar.ux, NT * sizeof(float), cudaMemcpyDeviceToHost);
                cudaMemcpy(h_uy, dVar.uy, NT * sizeof(float), cudaMemcpyDeviceToHost);
                cudaMemcpy(h_uz, dVar.uz, NT * sizeof(float), cudaMemcpyDeviceToHost);
                output(k);
            }
            
            if (k == 120000) {
                cudaMemcpy(h_ux, dVar.ux, NT * sizeof(float), cudaMemcpyDeviceToHost);
                cudaMemcpy(h_uy, dVar.uy, NT * sizeof(float), cudaMemcpyDeviceToHost);
                cudaMemcpy(h_uz, dVar.uz, NT * sizeof(float), cudaMemcpyDeviceToHost);
                cudaMemcpy(h_uxA, dVar.uxA, NT * sizeof(float), cudaMemcpyDeviceToHost);
                cudaMemcpy(h_uyA, dVar.uyA, NT * sizeof(float), cudaMemcpyDeviceToHost);
                cudaMemcpy(h_uzA, dVar.uzA, NT * sizeof(float), cudaMemcpyDeviceToHost);
                cudaMemcpy(h_TX, dVar.TX, NT * sizeof(float), cudaMemcpyDeviceToHost);
                cudaMemcpy(h_TY, dVar.TY, NT * sizeof(float), cudaMemcpyDeviceToHost);
                cudaMemcpy(h_TXY, dVar.TXY, NT * sizeof(float), cudaMemcpyDeviceToHost);
                cudaMemcpy(h_TKE, dVar.TKE, NT * sizeof(float), cudaMemcpyDeviceToHost);
                outputAver(k);
                
                resetAverage <<<blocksPerGrid, threadsPerBlock>>>();
            }
        }
    }
    
    freeMem();
    cudaDeviceReset();
    
    cout << "========================================" << endl;
    cout << "Simulation complete!" << endl;
    cout << "========================================" << endl;
    
    return 0;
}
