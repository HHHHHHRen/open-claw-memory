/*
 * RO Spacer LBM - CPU Version (No CUDA)
 * Diamond Pattern Spacer (3 crosses)
 * Compile: g++ -O3 spacer_lbm_cpu.cpp -o spacer_lbm_cpu
 * Or in VS Code: use C++ extension, click "Run"
 */

#include <iostream>
#include <fstream>
#include <sstream>
#include <cmath>
#include <vector>
#include <cstring>

#define D 3
#define Q 27
#define NX 340
#define NY 113
#define NZ 24
#define NT (NX * NY * NZ)

using namespace std;

// ========== Geometry Parameters ==========
const float dx = 0.05f;
const float pitch = 4.0f;
const float r_fiber = 0.5f;
const float r_node = 0.61f;
const float diamond_diag = pitch * sqrtf(2.0f);
const float z_fiber_center = 0.5f;

// ========== LBM Parameters ==========
const float tau = 0.5015f;
const float U_ref = 0.1f;

// ========== Global Arrays ==========
float f[NT][Q];      // Distribution functions
float fcol[NT][Q];   // Post-collision
float rho[NT];
float ux[NT], uy[NT], uz[NT];
char nodeType[NT];   // 'i'=fluid, 'b'=boundary, 's'=solid, 'o'=outlet

// ========== D3Q27 Weights and Directions ==========
const double w[Q] = {
    8.0/27, 2.0/27, 2.0/27, 2.0/27, 2.0/27, 2.0/27, 2.0/27,
    1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54, 1.0/54,
    1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216, 1.0/216
};

const int e[Q][D] = {
    {0,0,0}, {1,0,0}, {0,1,0}, {-1,0,0}, {0,-1,0}, {0,0,1}, {0,0,-1},
    {1,1,0}, {-1,1,0}, {-1,-1,0}, {1,-1,0}, {1,0,1}, {0,1,1}, {-1,0,1}, {0,-1,1},
    {1,0,-1}, {0,1,-1}, {-1,0,-1}, {0,-1,-1},
    {1,1,1}, {-1,1,1}, {-1,-1,1}, {1,-1,1}, {1,1,-1}, {-1,1,-1}, {-1,-1,-1}, {1,-1,-1}
};

const int oppoDir[Q] = {0,3,4,1,2,6,5,9,10,7,8,17,18,15,16,13,14,11,12,25,26,23,24,21,22,19,20};

// ========== Helper Functions ==========
inline int getIndex(int x, int y, int z) {
    return x + y * NX + z * NX * NY;
}

inline int getX(int id) { return id % NX; }
inline int getY(int id) { return (id / NX) % NY; }
inline int getZ(int id) { return id / (NX * NY); }

bool outRange(int x, int y, int z) {
    return (x < 0) || (x >= NX) || (y < 0) || (y >= NY) || (z < 0) || (z >= NZ);
}

// ========== LBM Functions ==========
void computeFeq(int id, float* feq) {
    float rhoid = rho[id];
    float uid = ux[id];
    float vid = uy[id];
    float wid = uz[id];
    
    float udotu = uid*uid + vid*vid + wid*wid;
    
    for (int j = 0; j < Q; j++) {
        float edotu = e[j][0]*uid + e[j][1]*vid + e[j][2]*wid;
        feq[j] = rhoid * w[j] * (1.0 + 3.0*edotu + 4.5*edotu*edotu - 1.5*udotu);
    }
}

void collide() {
    float feq[Q];
    
    for (int id = 0; id < NT; id++) {
        if (nodeType[id] == 's') continue;
        
        computeFeq(id, feq);
        
        for (int j = 0; j < Q; j++) {
            fcol[id][j] = f[id][j] - (f[id][j] - feq[j]) / tau;
        }
    }
}

void stream() {
    for (int id = 0; id < NT; id++) {
        if (nodeType[id] == 's' || nodeType[id] == 'o') continue;
        
        int x = getX(id);
        int y = getY(id);
        int z = getZ(id);
        
        for (int j = 0; j < Q; j++) {
            int xpre = x - e[j][0];
            int ypre = y - e[j][1];
            int zpre = z - e[j][2];
            
            if (nodeType[id] == 'i') {
                if (!outRange(xpre, ypre, zpre)) {
                    int idxpre = getIndex(xpre, ypre, zpre);
                    f[id][j] = fcol[idxpre][j];
                }
            } else if (nodeType[id] == 'b') {
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
    for (int id = 0; id < NT; id++) {
        if (nodeType[id] == 's') continue;
        
        float r = 0, u = 0, v = 0, w = 0;
        for (int j = 0; j < Q; j++) {
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

// ========== Boundary Conditions ==========
void applyBoundary() {
    // X direction periodic
    for (int y = 0; y < NY; y++) {
        for (int z = 0; z < NZ; z++) {
            int id_in = getIndex(0, y, z);
            int id_out = getIndex(NX-1, y, z);
            
            for (int j = 0; j < Q; j++) {
                if (e[j][0] > 0) f[id_in][j] = fcol[id_out][j];
                if (e[j][0] < 0) f[id_out][j] = fcol[id_in][j];
            }
        }
    }
    
    // Y direction periodic
    for (int x = 0; x < NX; x++) {
        for (int z = 0; z < NZ; z++) {
            int id_front = getIndex(x, 0, z);
            int id_rear = getIndex(x, NY-1, z);
            
            for (int j = 0; j < Q; j++) {
                if (e[j][1] > 0) f[id_front][j] = fcol[id_rear][j];
                if (e[j][1] < 0) f[id_rear][j] = fcol[id_front][j];
            }
        }
    }
    
    // Z direction wall (bounce-back)
    for (int x = 0; x < NX; x++) {
        for (int y = 0; y < NY; y++) {
            int id_down = getIndex(x, y, 0);
            int id_up = getIndex(x, y, NZ-1);
            
            for (int j = 0; j < Q; j++) {
                if (e[j][2] > 0) f[id_down][j] = fcol[id_down][oppoDir[j]];
                if (e[j][2] < 0) f[id_up][j] = fcol[id_up][oppoDir[j]];
            }
        }
    }
}

// ========== Initialization ==========
void init() {
    cout << "========================================" << endl;
    cout << "RO Spacer LBM - CPU Version" << endl;
    cout << "Grid: " << NX << " x " << NY << " x " << NZ << " = " << NT << " cells" << endl;
    cout << "========================================" << endl;
    
    // Initialize all nodes
    for (int id = 0; id < NT; id++) {
        rho[id] = 1.0f;
        ux[id] = uy[id] = uz[id] = 0.0f;
        nodeType[id] = 'i';
        
        int x = getX(id), y = getY(id), z = getZ(id);
        if (z == 0 || x == 0 || y == 0 || x == NX-1 || y == NY-1 || z == NZ-1) {
            nodeType[id] = 'o';
        }
    }
    
    // Generate spacer geometry
    cout << "Generating spacer geometry..." << endl;
    int solid_count = 0;
    
    for (int id = 0; id < NT; id++) {
        int x = getX(id);
        int y = getY(id);
        int z = getZ(id);
        
        float x_phys = x * dx;
        float y_phys = y * dx;
        float z_phys = z * dx;
        
        bool isSolid = false;
        
        // Lower fibers (+45°)
        for (float c = -NY*dx; c <= NX*dx + NY*dx; c += diamond_diag) {
            float dist_xy = fabsf(x_phys - y_phys - c) / sqrtf(2.0f);
            float dist_z = fabsf(z_phys - z_fiber_center);
            if (dist_xy < r_fiber && dist_z < r_fiber) {
                isSolid = true;
                break;
            }
        }
        if (isSolid) goto mark_solid;
        
        // Upper fibers (-45°)
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
            nodeType[id] = 's';
            solid_count++;
        }
    }
    
    // Mark boundary nodes
    for (int id = 0; id < NT; id++) {
        if (nodeType[id] != 's') {
            int x = getX(id), y = getY(id), z = getZ(id);
            for (int j = 0; j < Q; j++) {
                int xnb = x + e[j][0];
                int ynb = y + e[j][1];
                int znb = z + e[j][2];
                if (outRange(xnb, ynb, znb)) continue;
                if (nodeType[getIndex(xnb, ynb, znb)] == 's') {
                    nodeType[id] = 'b';
                    break;
                }
            }
        }
    }
    
    float porosity = 1.0f - (float)solid_count / NT;
    cout << "Solid nodes: " << solid_count << " / " << NT << endl;
    cout << "Porosity: " << porosity * 100.0f << "%" << endl;
    cout << "========================================" << endl;
    
    // Initialize equilibrium
    float feq[Q];
    for (int id = 0; id < NT; id++) {
        if (nodeType[id] == 's') {
            for (int j = 0; j < Q; j++) f[id][j] = 0;
            continue;
        }
        computeFeq(id, feq);
        for (int j = 0; j < Q; j++) f[id][j] = feq[j];
    }
}

// ========== Output ==========
void output(int step) {
    ostringstream name;
    name << "spacer_flow_" << step << ".dat";
    ofstream out(name.str().c_str());
    
    out << "TITLE=\"RO Spacer Flow - Step " << step << "\"" << endl;
    out << "VARIABLES=\"X\",\"Y\",\"Z\",\"U\",\"V\",\"W\"" << endl;
    out << "ZONE T=\"FLOW\", I=" << NX << ", J=" << NY << ", K=" << NZ << ", F=POINT" << endl;
    
    for (int id = 0; id < NT; id++) {
        out << getX(id) << " " << getY(id) << " " << getZ(id) << " "
            << ux[id] << " " << uy[id] << " " << uz[id] << endl;
    }
    out.close();
    cout << "Output: " << name.str() << endl;
}

void outputGeometry() {
    ofstream out("geometry.dat");
    out << "TITLE=\"Spacer Geometry\"" << endl;
    out << "VARIABLES=\"X\",\"Y\",\"Z\",\"Type\"" << endl;
    out << "ZONE T=\"GEOM\", I=" << NX << ", J=" << NY << ", K=" << NZ << ", F=POINT" << endl;
    
    for (int id = 0; id < NT; id++) {
        int type = 0;
        if (nodeType[id] == 's') type = 1;
        else if (nodeType[id] == 'b') type = 2;
        out << getX(id) << " " << getY(id) << " " << getZ(id) << " " << type << endl;
    }
    out.close();
    cout << "Geometry output: geometry.dat" << endl;
}

// ========== Main ==========
int main() {
    init();
    outputGeometry();
    
    cout << "Starting simulation..." << endl;
    
    int maxStep = 1000;  // Run 1000 steps for testing
    int outputInterval = 200;
    
    for (int step = 1; step <= maxStep; step++) {
        collide();
        stream();
        applyBoundary();
        computeMacro();
        
        if (step % 100 == 0) {
            cout << "Step " << step << " / " << maxStep << endl;
        }
        
        if (step % outputInterval == 0) {
            output(step);
        }
    }
    
    cout << "========================================" << endl;
    cout << "Simulation complete!" << endl;
    cout << "Max step: " << maxStep << endl;
    cout << "Output files: spacer_flow_*.dat, geometry.dat" << endl;
    cout << "Use Tecplot/Paraview to visualize" << endl;
    cout << "========================================" << endl;
    
    return 0;
}
