#!/usr/bin/env python3
"""
检查 geometry.bin 文件的结构
Usage: python3 check_geometry.py geometry.bin
"""

import numpy as np
import sys

if len(sys.argv) < 2:
    print("Usage: python3 check_geometry.py geometry.bin")
    sys.exit(1)

fname = sys.argv[1]

with open(fname, 'rb') as f:
    header = np.fromfile(f, dtype=np.int32, count=3)
    nx, ny, nz = header
    print(f"网格尺寸: {nx} x {ny} x {nz}")
    
    data = np.fromfile(f, dtype=np.uint8, count=nx*ny*nz)
    data = data.reshape((nx, ny, nz), order='F')
    
    print(f"\n总体统计:")
    print(f"  流体(0): {np.sum(data==0)} ({100*np.sum(data==0)/data.size:.1f}%)")
    print(f"  固体(1): {np.sum(data==1)} ({100*np.sum(data==1)/data.size:.1f}%)")
    print(f"  边界(2): {np.sum(data==2)} ({100*np.sum(data==2)/data.size:.1f}%)")
    print(f"  出口(3): {np.sum(data==3)} ({100*np.sum(data==3)/data.size:.1f}%)")
    
    print(f"\n入口平面 (x=0):")
    inlet = data[0, :, :]
    print(f"  流体: {np.sum(inlet==0)}, 固体: {np.sum(inlet==1)}, 边界: {np.sum(inlet==2)}")
    if np.sum(inlet==0) == 0:
        print("  ⚠️ 警告: 入口平面没有流体节点！")
    
    print(f"\n出口平面 (x={nx-1}):")
    outlet = data[-1, :, :]
    print(f"  流体: {np.sum(outlet==0)}, 固体: {np.sum(outlet==1)}, 边界: {np.sum(outlet==2)}")
    if np.sum(outlet==0) == 0:
        print("  ⚠️ 警告: 出口平面没有流体节点！")
    
    print(f"\n底面 (z=0):")
    bottom = data[:, :, 0]
    print(f"  流体: {np.sum(bottom==0)}, 固体: {np.sum(bottom==1)}")
    
    print(f"\n顶面 (z={nz-1}):")
    top = data[:, :, -1]
    print(f"  流体: {np.sum(top==0)}, 固体: {np.sum(top==1)}")
    if np.sum(top==0) > 0:
        print("  ⚠️ 顶层有流体节点 - 可能与壁面边界冲突")
    
    # 检查是否有孤立的流体节点
    print(f"\n检查潜在问题...")
    for z in [0, nz//2, nz-1]:
        slice_data = data[:, :, z]
        fluid_count = np.sum(slice_data == 0)
        solid_count = np.sum(slice_data == 1)
        print(f"  z={z}: 流体={fluid_count}, 固体={solid_count}")
