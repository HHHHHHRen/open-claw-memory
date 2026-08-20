#!/usr/bin/env python3
"""
修复版：geometry.bin 转 MATLAB，尝试多种维度顺序
Usage: python3 geom_check.py geometry.bin
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
    print(f"文件头: NX={nx}, NY={ny}, NZ={nz}")
    
    # 读取原始数据
    raw = np.fromfile(f, dtype=np.uint8)
    print(f"数据长度: {len(raw)} (期望: {nx*ny*nz})")
    
    if len(raw) != nx*ny*nz:
        print(f"⚠️ 长度不匹配！尝试其他解释...")
        # 可能是只有固体/流体标记（1字节每节点）
        pass
    
    # 方法1: Fortran order (MATLAB默认)
    geom_f = raw[:nx*ny*nz].reshape((nx, ny, nz), order='F')
    
    # 方法2: C order  
    geom_c = raw[:nx*ny*nz].reshape((nx, ny, nz), order='C')
    
    # 方法3: 维度顺序调换 (z, y, x)
    geom_swap = geom_f.transpose(2, 1, 0)  # (z, y, x)
    
    # 保存所有版本供对比
    savemat('geometry_check.mat', {
        'geom_f_xyz': geom_f,           # [x, y, z] Fortran
        'geom_c_xyz': geom_c,           # [x, y, z] C
        'geom_f_zyx': geom_swap,        # [z, y, x] 
        'solid_f': (geom_f == 1).astype(np.uint8),
        'solid_swap': (geom_swap == 1).astype(np.uint8),
        'nx': nx, 'ny': ny, 'nz': nz
    })
    
    print(f"\n已保存: geometry_check.mat")
    print(f"\n在 MATLAB 中对比三种顺序:")
    print(f"  % 方法1: Fortran order [x,y,z] -> 显示 z切片")
    print(f"  imagesc(squeeze(geom_f_xyz(:,:,12)));")
    print(f"  % 方法2: 转置后 [z,y,x] -> 显示 z切片")  
    print(f"  imagesc(squeeze(geom_f_zyx(12,:,:)));")
    print(f"  % 方法3: 直接看 solid_swap")
    print(f"  imagesc(squeeze(solid_swap(12,:,:)));")
    
    # 打印统计，帮助判断
    print(f"\n统计:")
    print(f"  值=0 (流体): {np.sum(geom_f==0)}")
    print(f"  值=1 (固体): {np.sum(geom_f==1)}")
    print(f"  其他值: {np.sum((geom_f!=0)&(geom_f!=1))}")
    
    # 检查 z=0 和 z=nz-1
    print(f"\nz=0 层: 流体={np.sum(geom_f[:,:,0]==0)}, 固体={np.sum(geom_f[:,:,0]==1)}")
    print(f"z={nz-1} 层: 流体={np.sum(geom_f[:,:,-1]==0)}, 固体={np.sum(geom_f[:,:,-1]==1)}")
