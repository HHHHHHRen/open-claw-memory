#!/usr/bin/env python3
"""
检查 z 方向对称性
Usage: python3 check_z_symmetry.py geometry.bin
"""

import numpy as np
import sys

fname = sys.argv[1] if len(sys.argv) > 1 else "geometry.bin"

with open(fname, 'rb') as f:
    nx, ny, nz = np.fromfile(f, dtype=np.int32, count=3)
    print(f"尺寸: {nx}x{ny}x{nz}")
    
    # 按 C 代码的方式读取: x 变化最快，然后 y，然后 z
    data = np.fromfile(f, dtype=np.uint8, count=nx*ny*nz)
    
    # reshape 为 (nx, ny, nz) - C order
    geom = data.reshape((nx, ny, nz), order='C')
    
    print(f"\n各层固体数量:")
    for z in range(nz):
        ns = np.sum(geom[:, :, z] == 1)
        print(f"  z={z}: 固体={ns}")
    
    # 检查对称性: z=k 应该等于 z=nz-1-k
    print(f"\n对称性检查 (z=k vs z={nz-1}-k):")
    match_all = True
    for k in range(nz//2):
        layer_k = geom[:, :, k]
        layer_mirror = geom[:, :, nz-1-k]
        match = np.array_equal(layer_k, layer_mirror)
        diff = np.sum(layer_k != layer_mirror)
        status = "✓" if match else f"✗ 差异{diff}格"
        print(f"  z={k} vs z={nz-1-k}: {status}")
        if not match:
            match_all = False
    
    if match_all:
        print("\n✓ z 方向完全对称")
    else:
        print("\n✗ z 方向不对称！")
        print("\n可能原因:")
        print("  1. MATLAB 生成时 z 网格没居中")
        print("  2. 导出 bin 时 Z 轴方向反了")
        print("\n修复建议:")
        print("  - 在 MATLAB 里把 z 范围改为 [-Lz/2, Lz/2] 再生成")
        print("  - 或手动翻转 Z 轴后重新导出")
