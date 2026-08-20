import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, Circle, FancyArrowPatch, Wedge
import numpy as np
import os

# 设置中文字体
plt.rcParams['font.sans-serif'] = ['SimHei', 'DejaVu Sans', 'Arial Unicode MS', 'WenQuanYi Micro Hei']
plt.rcParams['axes.unicode_minus'] = False

# 创建输出目录
output_dir = "/root/.openclaw/workspace/青创赛图片"
os.makedirs(output_dir, exist_ok=True)

# ========== 图1: 光催化-两性离子协同抗污染机理示意图 ==========
fig1, ax1 = plt.subplots(1, 1, figsize=(12, 8))
ax1.set_xlim(0, 12)
ax1.set_ylim(0, 8)
ax1.axis('off')
ax1.set_title('光催化-两性离子协同抗污染机理示意图', fontsize=16, fontweight='bold', pad=20)

# 膜基底
membrane = FancyBboxPatch((1, 1), 10, 1.5, boxstyle="square,pad=0.02", 
                           facecolor='#2C3E50', edgecolor='black', linewidth=2)
ax1.add_patch(membrane)
ax1.text(6, 1.75, '聚酰胺膜基底', fontsize=11, ha='center', color='white', fontweight='bold')

# 两性离子亲水层
hydro_layer = FancyBboxPatch((1, 2.5), 10, 1.2, boxstyle="square,pad=0.02",
                              facecolor='#3498DB', edgecolor='#2980B9', linewidth=2, alpha=0.8)
ax1.add_patch(hydro_layer)
ax1.text(6, 3.1, '两性离子亲水层', fontsize=11, ha='center', color='white', fontweight='bold')

# 光催化纳米粒子 - 分散分布
np.random.seed(42)
particle_x = np.random.uniform(1.5, 10.5, 12)
particle_y = np.random.uniform(4, 5.5, 12)
for px, py in zip(particle_x, particle_y):
    circle = Circle((px, py), 0.25, facecolor='#E74C3C', edgecolor='#C0392B', linewidth=1.5)
    ax1.add_patch(circle)
ax1.text(6, 5.8, 'TiO₂光催化纳米粒子', fontsize=11, ha='center', color='#E74C3C', fontweight='bold')

# 污染物示意
pollutants = [(2.5, 6.5), (4, 6.8), (5.5, 6.3), (7.5, 6.7), (9, 6.4)]
for px, py in pollutants:
    # 不规则形状表示污染物
    theta = np.linspace(0, 2*np.pi, 8)
    r = 0.2 + 0.05 * np.random.randn(8)
    x_poly = px + r * np.cos(theta)
    y_poly = py + r * np.sin(theta)
    ax1.fill(x_poly, y_poly, facecolor='#95A5A6', edgecolor='#7F8C8D', alpha=0.7)

# 污染物被排斥的箭头
for px, py in pollutants:
    ax1.annotate('', xy=(px, py-0.8), xytext=(px, py-0.3),
                arrowprops=dict(arrowstyle='->', color='#E67E22', lw=2))

ax1.text(6, 7.2, '有机/无机污染物', fontsize=10, ha='center', color='#7F8C8D')
ax1.text(6, 0.3, '设计阶段 | 理论验证中', fontsize=9, ha='center', color='#7F8C8D', style='italic')

# 图例说明
legend_elements = [
    mpatches.Patch(facecolor='#E74C3C', label='光催化降解'),
    mpatches.Patch(facecolor='#3498DB', label='亲水排斥'),
    mpatches.Patch(facecolor='#95A5A6', label='污染物')
]
ax1.legend(handles=legend_elements, loc='upper right', fontsize=9)

plt.tight_layout()
plt.savefig(f"{output_dir}/01_抗污染机理示意图.png", dpi=300, bbox_inches='tight', facecolor='white')
plt.close()
print("✓ 图1完成: 抗污染机理示意图")

# ========== 图2: 仿生流道设计对比图 ==========
fig2, axes = plt.subplots(1, 2, figsize=(14, 6))

# 左侧：传统直道
ax_left = axes[0]
ax_left.set_xlim(0, 10)
ax_left.set_ylim(0, 6)
ax_left.axis('off')
ax_left.set_title('传统直通道设计', fontsize=13, fontweight='bold', color='#7F8C8D')

# 画传统流道
for i in range(4):
    y_pos = 1 + i * 1.2
    rect = FancyBboxPatch((0.5, y_pos), 9, 0.6, boxstyle="square,pad=0.01",
                           facecolor='#BDC3C7', edgecolor='#95A5A6', linewidth=1)
    ax_left.add_patch(rect)
    # 流速箭头
    ax_left.annotate('', xy=(8.5, y_pos+0.3), xytext=(1, y_pos+0.3),
                    arrowprops=dict(arrowstyle='->', color='#3498DB', lw=3))

# 死区示意
dead_zones = [(2, 1.8), (5, 3), (7, 4.2)]
for dx, dy in dead_zones:
    circle = Circle((dx, dy), 0.4, facecolor='#E74C3C', alpha=0.5)
    ax_left.add_patch(circle)
    ax_left.text(dx, dy, '死区', fontsize=8, ha='center', va='center', color='white', fontweight='bold')

ax_left.text(5, 0.3, '问题：流速不均 | 易产生死区 | 污染物沉积', fontsize=10, ha='center', color='#E74C3C')

# 右侧：仿生优化流道
ax_right = axes[1]
ax_right.set_xlim(0, 10)
ax_right.set_ylim(0, 6)
ax_right.axis('off')
ax_right.set_title('仿生流道优化设计（设计验证阶段）', fontsize=13, fontweight='bold', color='#27AE60')

# 画仿生流道 - 波浪形
x = np.linspace(0.5, 9.5, 100)
for i in range(4):
    y_base = 1.3 + i * 1.1
    y_wave = y_base + 0.15 * np.sin(x * 1.5)
    ax_right.fill_between(x, y_wave-0.25, y_wave+0.25, alpha=0.6, color='#27AE60')
    ax_right.plot(x, y_wave+0.25, color='#1E8449', linewidth=2)
    ax_right.plot(x, y_wave-0.25, color='#1E8449', linewidth=2)
    # 流速箭头
    ax_right.annotate('', xy=(8.5, y_base), xytext=(1, y_base),
                     arrowprops=dict(arrowstyle='->', color='#2980B9', lw=3))

# 涡流增强示意
for i in range(3):
    cx = 2.5 + i * 2.5
    cy = 3
    # 画小漩涡
    theta = np.linspace(0, 2*np.pi, 30)
    for r, alpha in [(0.3, 0.3), (0.45, 0.2)]:
        spiral_x = cx + r * np.cos(theta + np.pi/4)
        spiral_y = cy + r * np.sin(theta + np.pi/4)
        ax_right.plot(spiral_x, spiral_y, color='#8E44AD', linewidth=1.5, alpha=alpha)

ax_right.text(5, 0.3, '优化：流速均匀 | 涡流自清洁 | 能耗降低20%+', fontsize=10, ha='center', color='#27AE60')

plt.tight_layout()
plt.savefig(f"{output_dir}/02_流道设计对比图.png", dpi=300, bbox_inches='tight', facecolor='white')
plt.close()
print("✓ 图2完成: 流道设计对比图")

# ========== 图3: 进口膜失效机理分析图 ==========
fig3, ax3 = plt.subplots(figsize=(12, 8))
ax3.set_xlim(0, 12)
ax3.set_ylim(0, 10)
ax3.axis('off')
ax3.set_title('进口膜在电网特种工况下的失效机理分析', fontsize=15, fontweight='bold', pad=20)

# 市政/海水膜设计场景
box1 = FancyBboxPatch((0.5, 7), 4.5, 2.5, boxstyle="round,pad=0.1",
                       facecolor='#AED6F1', edgecolor='#3498DB', linewidth=2)
ax3.add_patch(box1)
ax3.text(2.75, 8.8, '进口膜设计场景', fontsize=11, ha='center', fontweight='bold', color='#154360')
ax3.text(2.75, 8.2, '• 市政自来水\n• 海水淡化\n• 标准水质条件', fontsize=9, ha='center', va='top', color='#1A5276')

# 换流站实际工况
box2 = FancyBboxPatch((7, 7), 4.5, 2.5, boxstyle="round,pad=0.1",
                       facecolor='#F5B7B1', edgecolor='#E74C3C', linewidth=2)
ax3.add_patch(box2)
ax3.text(9.25, 8.8, '换流站实际工况', fontsize=11, ha='center', fontweight='bold', color='#7B241C')
ax3.text(9.25, 8.2, '• 高海拔（>3000m）\n• 水质差（高浊度）\n• 低温环境', fontsize=9, ha='center', va='top', color='#922B21')

# 不匹配箭头
ax3.annotate('', xy=(7, 8.25), xytext=(5, 8.25),
            arrowprops=dict(arrowstyle='<->', color='#E67E22', lw=3, ls='--'))
ax3.text(6, 8.6, '不匹配！', fontsize=11, ha='center', color='#E67E22', fontweight='bold')

# 失效机理框
mechanisms = [
    ('膜孔堵塞', 1.5, 5.5, '#E74C3C', '高浊度导致物理堵塞'),
    ('化学污染', 4.5, 5.5, '#E67E22', '有机物吸附不可逆'),
    ('低温通量衰减', 7.5, 5.5, '#F39C12', '聚酰胺低温收缩'),
    ('清洗频繁', 10.5, 5.5, '#D35400', '周期仅2-3个月')
]

for title, x, y, color, desc in mechanisms:
    box = FancyBboxPatch((x-1, y-0.8), 2, 1.6, boxstyle="round,pad=0.05",
                          facecolor=color, edgecolor='black', linewidth=1.5, alpha=0.8)
    ax3.add_patch(box)
    ax3.text(x, y+0.3, title, fontsize=10, ha='center', color='white', fontweight='bold')
    ax3.text(x, y-0.3, desc, fontsize=8, ha='center', color='white')

# 后果
result_box = FancyBboxPatch((3, 1.5), 6, 2, boxstyle="round,pad=0.1",
                             facecolor='#922B21', edgecolor='#641E16', linewidth=2)
ax3.add_patch(result_box)
ax3.text(6, 2.8, '后果：非计划停机风险高 | 运维成本剧增 | 供应链卡脖子', 
         fontsize=11, ha='center', color='white', fontweight='bold')
ax3.text(6, 2.1, '亟需：针对电网特种工况的专用膜技术', 
         fontsize=10, ha='center', color='#FADBD8')

plt.tight_layout()
plt.savefig(f"{output_dir}/03_失效机理分析图.png", dpi=300, bbox_inches='tight', facecolor='white')
plt.close()
print("✓ 图3完成: 失效机理分析图")

# ========== 图4: 技术路线与产业化时间线 ==========
fig4, ax4 = plt.subplots(figsize=(14, 7))

# 阶段定义
stages = [
    ('基础研究阶段', 0, 2, '#3498DB', ['微观结构-性能关联机制', '分子设计理论指导']),
    ('技术开发阶段', 2, 4, '#2ECC71', ['高纯单体合成', '表面改性技术', '流道数值模拟']),
    ('中试验证阶段', 4, 6, '#F39C12', ['换流站现场验证', '寿命预测模型', '行业标准制定']),
    ('产业化阶段', 6, 8, '#9B59B6', ['万支级中试线', '规模化量产', '市场推广'])
]

y_pos = 0.5
for stage, start, end, color, tasks in stages:
    # 阶段条
    rect = FancyBboxPatch((start, y_pos), end-start, 0.8, boxstyle="round,pad=0.05",
                           facecolor=color, edgecolor='black', linewidth=1.5, alpha=0.85)
    ax4.add_patch(rect)
    ax4.text((start+end)/2, y_pos+0.4, stage, fontsize=11, ha='center', va='center', 
             color='white', fontweight='bold')
    
    # 任务列表
    for i, task in enumerate(tasks):
        ax4.text((start+end)/2, y_pos-0.4-i*0.35, f'• {task}', fontsize=9, ha='center', va='top', color='#2C3E50')

# 时间轴
ax4.set_xlim(-0.5, 8.5)
ax4.set_ylim(-1.5, 2)
ax4.axhline(y=y_pos-0.05, color='#34495E', linewidth=3, xmin=0.02, xmax=0.98)

# 时间点标记
for i in range(5):
    ax4.plot(i*2, y_pos-0.05, 'o', color='#34495E', markersize=10)
    year = 2024 + i
    ax4.text(i*2, y_pos-0.25, f'{year}', fontsize=9, ha='center', color='#7F8C8D')

ax4.set_title('"基础研究-技术开发-产业应用"全链条创新路线', fontsize=14, fontweight='bold', pad=20)
ax4.axis('off')

# 当前位置标注
ax4.annotate('当前位置\n(创意阶段)', xy=(1, y_pos+0.8), xytext=(1, y_pos+1.5),
            arrowprops=dict(arrowstyle='->', color='#E74C3C', lw=2),
            fontsize=10, ha='center', color='#E74C3C', fontweight='bold')

plt.tight_layout()
plt.savefig(f"{output_dir}/04_技术路线时间线.png", dpi=300, bbox_inches='tight', facecolor='white')
plt.close()
print("✓ 图4完成: 技术路线时间线")

# ========== 图5: 预期性能对比雷达图 ==========
fig5, ax5 = plt.subplots(figsize=(10, 10), subplot_kw=dict(projection='polar'))

# 性能指标
categories = ['脱盐率', '使用寿命', '抗污染性', '低温通量', '能耗效率', '运维成本']
N = len(categories)

# 计算角度
angles = [n / float(N) * 2 * np.pi for n in range(N)]
angles += angles[:1]  # 闭合

# 进口膜（现状）
import_membrane = [85, 60, 50, 55, 70, 40]  # 相对得分
import_membrane += import_membrane[:1]

# 自主膜（预期目标）
self_membrane = [95, 90, 88, 85, 85, 85]  # 基于设计目标
self_membrane += self_membrane[:1]

# 绘制
ax5.plot(angles, import_membrane, 'o-', linewidth=2, label='进口膜（现状）', color='#E74C3C')
ax5.fill(angles, import_membrane, alpha=0.25, color='#E74C3C')
ax5.plot(angles, self_membrane, 'o-', linewidth=2, label='自主膜（预期目标）', color='#27AE60')
ax5.fill(angles, self_membrane, alpha=0.25, color='#27AE60')

# 设置标签
ax5.set_xticks(angles[:-1])
ax5.set_xticklabels(categories, fontsize=12)
ax5.set_ylim(0, 100)
ax5.set_yticks([20, 40, 60, 80, 100])
ax5.set_yticklabels(['20', '40', '60', '80', '100'], color='gray', size=9)

ax5.set_title('预期性能指标对比（基于理论设计与数值模拟）', fontsize=14, fontweight='bold', pad=30)
ax5.legend(loc='upper right', bbox_to_anchor=(1.3, 1.1), fontsize=11)

# 关键指标标注
ax5.annotate('≥99.7%', xy=(angles[0], 95), xytext=(angles[0]+0.3, 105),
            fontsize=9, color='#27AE60', fontweight='bold')
ax5.annotate('≥5年', xy=(angles[1], 90), xytext=(angles[1]+0.3, 98),
            fontsize=9, color='#27AE60', fontweight='bold')

plt.tight_layout()
plt.savefig(f"{output_dir}/05_性能对比雷达图.png", dpi=300, bbox_inches='tight', facecolor='white')
plt.close()
print("✓ 图5完成: 性能对比雷达图")

# ========== 图6: 关键性能指标总览表 ==========
fig6, ax6 = plt.subplots(figsize=(12, 7))
ax6.axis('tight')
ax6.axis('off')

# 表格数据
table_data = [
    ['性能指标', '进口膜（现状）', '自主膜（预期目标）', '提升幅度'],
    ['脱盐率', '98.5%', '≥99.7%', '↑ 1.2%'],
    ['使用寿命', '2-3年', '≥5年', '↑ 67-150%'],
    ['化学清洗周期', '2-3个月', '≥6个月', '↑ 100-200%'],
    ['能耗水平', '基准值', '降低20%+', '↓ 20%'],
    ['低温通量保持率', '60%(@5℃)', '≥80%(@5℃)', '↑ 33%'],
    ['抗污染指数', '中等', '优秀', '显著提升'],
    ['适配性', '市政/海水', '电网特种工况', '定制化'],
]

# 创建表格
table = ax6.table(cellText=table_data, cellLoc='center', loc='center',
                  colWidths=[0.25, 0.25, 0.25, 0.25])

table.auto_set_font_size(False)
table.set_fontsize(10)
table.scale(1, 2.5)

# 设置表头样式
for i in range(4):
    cell = table[(0, i)]
    cell.set_facecolor('#34495E')
    cell.set_text_props(weight='bold', color='white', fontsize=11)

# 设置数据行样式
colors = ['#ECF0F1', '#FFFFFF']
for i in range(1, len(table_data)):
    for j in range(4):
        cell = table[(i, j)]
        cell.set_facecolor(colors[i % 2])
        if j == 3:  # 提升幅度列
            cell.set_text_props(weight='bold', color='#27AE60')
        if i == len(table_data) - 1:  # 最后一行
            cell.set_text_props(weight='bold')

ax6.set_title('关键性能指标对比表（基于理论设计预期）', fontsize=14, fontweight='bold', pad=20)

# 底部说明
fig6.text(0.5, 0.05, '注：预期目标基于数值模拟与理论计算，具体数据以实际研发结果为准', 
          ha='center', fontsize=9, color='#7F8C8D', style='italic')

plt.savefig(f"{output_dir}/06_性能指标对比表.png", dpi=300, bbox_inches='tight', facecolor='white')
plt.close()
print("✓ 图6完成: 性能指标对比表")

print(f"\n✅ 全部6张图片已生成！保存路径: {output_dir}/")
