#!/usr/bin/env python3
"""
Convert LBM binary output to MATLAB .mat file
Usage: python3 bin2mat.py spacer_flow_0050.bin
"""

import numpy as np
import sys
import os

def bin_to_mat(bin_file):
    """Convert binary LBM output to MATLAB format"""
    if not os.path.exists(bin_file):
        print(f"Error: File '{bin_file}' not found")
        sys.exit(1)
    
    print(f"Reading: {bin_file}")
    
    with open(bin_file, 'rb') as f:
        # Read header: 4 integers (nx, ny, nz, nfields)
        header = np.fromfile(f, dtype=np.int32, count=4)
        nx, ny, nz, nfields = header
        print(f"  Grid: {nx} x {ny} x {nz}")
        print(f"  Fields: {nfields}")
        
        # Read all data
        total = nx * ny * nz * nfields
        data = np.fromfile(f, dtype=np.float32, count=total)
    
    # Reshape: Fortran order (column-major like MATLAB)
    data = data.reshape((nx, ny, nz, nfields), order='F')
    
    # Extract fields
    rho = data[:,:,:,0]
    ux = data[:,:,:,1]
    uy = data[:,:,:,2]
    uz = data[:,:,:,3]
    
    # Transpose to MATLAB order [z, y, x]
    rho = np.transpose(rho, (2, 1, 0))
    ux = np.transpose(ux, (2, 1, 0))
    uy = np.transpose(uy, (2, 1, 0))
    uz = np.transpose(uz, (2, 1, 0))
    
    # Save to .mat
    try:
        from scipy.io import savemat
        mat_file = bin_file.replace('.bin', '.mat')
        savemat(mat_file, {
            'rho': rho,
            'ux': ux,
            'uy': uy,
            'uz': uz,
            'nx': nx,
            'ny': ny,
            'nz': nz
        })
        print(f"\nSaved: {mat_file}")
        print(f"  In MATLAB: size(ux) = [{nz}, {ny}, {nx}]")
    except ImportError:
        print("\nWarning: scipy not installed. Saving as .npz instead.")
        print("Install scipy: pip3 install scipy")
        npz_file = bin_file.replace('.bin', '.npz')
        np.savez(npz_file, rho=rho, ux=ux, uy=uy, uz=uz, nx=nx, ny=ny, nz=nz)
        print(f"Saved: {npz_file}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 bin2mat.py <bin_file>")
        print("Example: python3 bin2mat.py spacer_flow_0050.bin")
        sys.exit(1)
    
    bin_to_mat(sys.argv[1])
