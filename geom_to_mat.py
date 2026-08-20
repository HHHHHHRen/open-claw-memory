#!/usr/bin/env python3
"""
把 geometry.bin 转成 MATLAB .mat 格式，方便检查结构
Usage: python3 geom_to_mat.py geometry.bin
"""

import numpy as np
import sys

try:
    from scipy.io import savemat
except ImportError:
    print("需要 scipy: pip3 install scipy")
    sys.exit(1)

fname = sys.argv[1] if len(sys.argv) > 1 else "geometry.bin"

with open(fname, 'rb') as f:
    nx, ny, nz = np.fromfile(f, dtype=np.int32, count=3)
    print(f"读取: {nx}x{ny}x{nz}")
    
    # 读取几何数据 (0=流体, 1=固体, 2=边界, 3=出口)
    geom = np.fromfile(f, dtype=np.uint8, count=nx*ny*nz)
    geom = geom.reshape((nx, ny, nz), order='F')
    
    # 转置为 MATLAB 顺序 [z, y, x]
    geom_zxy = np.transpose(geom, (2, 1, 0))
    
    # 保存
    outname = fname.replace('.bin', '_struct.mat')
    savemat(outname, {
        'geometry': geom_zxy,  # 0=流体, 1=固体, etc.
        'solid_mask': (geom_zxy == 1).astype(np.uint8),  # 只看固体
        'nx': nx, 'ny': ny, 'nz': nz
    })
    print(f"已保存: {outname}")
    print(f"\n在 MATLAB 中查看:")
    print(f"  data = load('{outname}');")
    print(f"  imagesc(squeeze(data.solid_mask(12,:,:)));  % z=12 切片")
    print(f"  axis xy; title('z=12 固体分布');")
