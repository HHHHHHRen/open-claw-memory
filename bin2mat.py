#!/usr/bin/env python3
"""
Convert LBM binary output(s) to MATLAB .mat file(s)
Usage:
  python3 bin2mat.py spacer_flow_0050.bin          # 单个文件
  python3 bin2mat.py *.bin                          # 批量转换
  python3 bin2mat.py --all                          # 转换当前目录所有 .bin
"""

import numpy as np
import sys
import os
import glob

def bin_to_mat(bin_file):
    """Convert binary LBM output to MATLAB format"""
    if not os.path.exists(bin_file):
        print(f"❌ 文件不存在: '{bin_file}'")
        return False
    
    print(f"\n📄 读取: {bin_file}")
    
    with open(bin_file, 'rb') as f:
        # Read header: 4 integers (nx, ny, nz, nfields)
        header = np.fromfile(f, dtype=np.int32, count=4)
        nx, ny, nz, nfields = header
        print(f"   网格: {nx} x {ny} x {nz}, 字段数: {nfields}")
        
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
            print(f"✅ 已保存: {mat_file}")
            return True
        except ImportError:
            print("⚠️  scipy 未安装，保存为 .npz 格式")
            print("    安装命令: pip3 install scipy")
            npz_file = bin_file.replace('.bin', '.npz')
            np.savez(npz_file, rho=rho, ux=ux, uy=uy, uz=uz, nx=nx, ny=ny, nz=nz)
            print(f"✅ 已保存: {npz_file}")
            return True

def batch_convert(pattern):
    """批量转换匹配的文件"""
    files = glob.glob(pattern)
    
    if not files:
        print(f"❌ 未找到匹配的文件: {pattern}")
        return
    
    # 过滤出 .bin 文件
    bin_files = [f for f in files if f.endswith('.bin')]
    bin_files.sort()  # 排序: 0050, 0100, 0200...
    
    if not bin_files:
        print(f"❌ 未找到 .bin 文件")
        return
    
    print(f"\n🔧 找到 {len(bin_files)} 个文件，开始批量转换...")
    print("=" * 50)
    
    success = 0
    failed = 0
    
    for f in bin_files:
        if bin_to_mat(f):
            success += 1
        else:
            failed += 1
    
    print("\n" + "=" * 50)
    print(f"✅ 成功: {success} 个")
    if failed:
        print(f"❌ 失败: {failed} 个")
    print("\n在 MATLAB 中加载示例:")
    print("  data = load('spacer_flow_0100.mat');")
    print("  size(data.ux)  % 输出: [nz, ny, nx]")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("用法:")
        print("  python3 bin2mat.py <单个文件.bin>")
        print("  python3 bin2mat.py '*.bin'          # 批量转换")
        print("  python3 bin2mat.py --all            # 转换当前目录所有 .bin")
        sys.exit(1)
    
    arg = sys.argv[1]
    
    if arg == '--all':
        batch_convert('*.bin')
    elif '*' in arg:
        batch_convert(arg)
    else:
        # 单个文件
        if bin_to_mat(arg):
            print(f"\n在 MATLAB 中加载:")
            print(f"  data = load('{arg.replace('.bin', '.mat')}');")
            print(f"  size(data.ux)")
