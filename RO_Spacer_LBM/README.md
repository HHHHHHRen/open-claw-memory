# RO Spacer LBM Simulation

Complete LBM simulation setup for VS Code.

## Quick Start

1. **Open folder in VS Code**: `File -> Open Folder -> RO_Spacer_LBM`

2. **Compile and Run**:
   - Press `Ctrl+Shift+B` → Select "Full Pipeline"
   - Or run in terminal: `clang -O3 spacer_lbm.c -o spacer_lbm -lm && ./spacer_lbm`

3. **Convert to MATLAB**:
   ```bash
   python3 bin2mat.py spacer_flow_0050.bin
   ```

## File Structure

```
RO_Spacer_LBM/
├── spacer_lbm.c      # Main LBM code
├── bin2mat.py        # Python converter
├── .vscode/
│   └── tasks.json    # Build tasks
└── README.md
```

## Output Files

- `spacer_flow_0050.bin` - Binary data (for Python/MATLAB)
- `spacer_flow_0050.dat` - Tecplot format
- `spacer_flow_0050.mat` - MATLAB format (after conversion)
- `geometry.dat` - Grid geometry

## MATLAB Usage

```matlab
data = load('spacer_flow_0050.mat');
size(data.ux)      % [40, 113, 339]
slice(data.ux, [], [], 20);  % Visualize
```

## Python Visualization

```python
import numpy as np
from scipy.io import loadmat
data = loadmat('spacer_flow_0050.mat')
print(data['ux'].shape)  # (40, 113, 339)
```

## Requirements

- C compiler (clang/gcc)
- Python 3 + scipy (`pip3 install scipy numpy`)
