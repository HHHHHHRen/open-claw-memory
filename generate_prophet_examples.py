import pandas as pd
import numpy as np
from prophet import Prophet
import matplotlib.pyplot as plt
from matplotlib.font_manager import FontProperties
import warnings
warnings.filterwarnings('ignore')

# 加载中文字体
font_path = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc'
font_prop = FontProperties(fname=font_path)
font_name = font_prop.get_name()
plt.rcParams['font.sans-serif'] = [font_name]
plt.rcParams['axes.unicode_minus'] = False

np.random.seed(42)

# ==================== 场景1：电商日销售额预测（最基础） ====================
print("=== 场景1：电商日销售额预测 ===")

# 生成 2 年数据，带趋势+周季节性+年季节性+噪声
dates = pd.date_range('2022-01-01', '2023-12-31', freq='D')
n = len(dates)

trend = np.linspace(100, 200, n)  # 缓慢增长
yearly = 20 * np.sin(2 * np.pi * np.arange(n) / 365.25)  # 年周期（淡旺季）
weekly = 15 * np.sin(2 * np.pi * np.arange(n) / 7) + 10  # 周周期（周末高）
noise = np.random.normal(0, 8, n)

y = trend + yearly + weekly + noise
y = np.maximum(y, 10)  # 保证正数

df = pd.DataFrame({'ds': dates, 'y': y})

m = Prophet(yearly_seasonality=True, weekly_seasonality=True, daily_seasonality=False)
m.fit(df)

future = m.make_future_dataframe(periods=30)
forecast = m.predict(future)

fig1 = m.plot(forecast)
plt.title('场景1：电商日销售额预测（30天）', fontsize=14, pad=20)
plt.xlabel('日期')
plt.ylabel('销售额')
plt.tight_layout()
plt.savefig('prophet_example1_forecast.png', dpi=150, bbox_inches='tight')
plt.close()

fig2 = m.plot_components(forecast)
plt.suptitle('场景1：趋势与季节性分解', fontsize=14, y=1.02)
plt.tight_layout()
plt.savefig('prophet_example1_components.png', dpi=150, bbox_inches='tight')
plt.close()

print(f"训练数据：{len(df)} 天，预测未来：30 天")
print(f"预测均值：{forecast['yhat'].tail(30).mean():.1f}")
print(f"预测区间：{forecast['yhat_lower'].tail(30).mean():.1f} ~ {forecast['yhat_upper'].tail(30).mean():.1f}")
print("图片已保存：prophet_example1_forecast.png, prophet_example1_components.png")
print()

# ==================== 场景2：节假日效应（双十一、春节） ====================
print("=== 场景2：节假日效应 ===")

# 生成数据，带节假日 spikes
holidays = pd.DataFrame({
    'holiday': '双十一',
    'ds': pd.to_datetime(['2022-11-11', '2023-11-11']),
    'lower_window': -3,
    'upper_window': 3,
})

holidays2 = pd.DataFrame({
    'holiday': '春节',
    'ds': pd.to_datetime(['2022-01-31', '2023-01-21']),
    'lower_window': -5,
    'upper_window': 5,
})

holidays = pd.concat([holidays, holidays2])

dates2 = pd.date_range('2022-01-01', '2023-12-31', freq='D')
n2 = len(dates2)
trend2 = np.linspace(500, 700, n2)
yearly2 = 50 * np.sin(2 * np.pi * np.arange(n2) / 365.25)
weekly2 = 30 * np.sin(2 * np.pi * np.arange(n2) / 7) + 20
noise2 = np.random.normal(0, 15, n2)

y2 = trend2 + yearly2 + weekly2 + noise2

# 添加双十一 spike
for d in ['2022-11-11', '2023-11-11']:
    idx = dates2.get_loc(pd.Timestamp(d))
    y2[idx] += 200
    y2[idx-1] += 80
    y2[idx+1] += 60

# 春节低谷（物流停）
for d in ['2022-01-31', '2023-01-21']:
    idx = dates2.get_loc(pd.Timestamp(d))
    for offset in range(-5, 6):
        if 0 <= idx+offset < len(y2):
            y2[idx+offset] -= 40

y2 = np.maximum(y2, 50)

df2 = pd.DataFrame({'ds': dates2, 'y': y2})

m2 = Prophet(holidays=holidays, yearly_seasonality=True, weekly_seasonality=True)
m2.fit(df2)

future2 = m2.make_future_dataframe(periods=30)
forecast2 = m2.predict(future2)

fig3 = m2.plot(forecast2)
plt.title('场景2：带节假日效应的预测（双十一+春节）', fontsize=14, pad=20)
plt.xlabel('日期')
plt.ylabel('订单量')
plt.tight_layout()
plt.savefig('prophet_example2_forecast.png', dpi=150, bbox_inches='tight')
plt.close()

fig4 = m2.plot_components(forecast2)
plt.suptitle('场景2：节假日与季节性分解', fontsize=14, y=1.02)
plt.tight_layout()
plt.savefig('prophet_example2_components.png', dpi=150, bbox_inches='tight')
plt.close()

print(f"节假日影响（双十一）：{forecast2[forecast2['双十一'].abs() > 0.1]['双十一'].mean():.1f}")
print(f"节假日影响（春节）：{forecast2[forecast2['春节'].abs() > 0.1]['春节'].mean():.1f}")
print("图片已保存：prophet_example2_forecast.png, prophet_example2_components.png")
print()

# ==================== 场景3：突变点（产品改版后业务飙升） ====================
print("=== 场景3：突变点检测（产品改版） ===")

dates3 = pd.date_range('2022-01-01', '2024-03-31', freq='D')
n3 = len(dates3)

trend3 = np.zeros(n3)
# 前 600 天：缓慢增长
trend3[:600] = np.linspace(100, 130, 600)
# 第 600 天（产品改版）后：增速翻倍
trend3[600:] = np.linspace(130, 250, n3 - 600)

yearly3 = 20 * np.sin(2 * np.pi * np.arange(n3) / 365.25)
weekly3 = 10 * np.sin(2 * np.pi * np.arange(n3) / 7) + 5
noise3 = np.random.normal(0, 5, n3)

y3 = trend3 + yearly3 + weekly3 + noise3
y3 = np.maximum(y3, 10)

df3 = pd.DataFrame({'ds': dates3, 'y': y3})

# 默认 Prophet（changepoint 不敏感）
m3_default = Prophet(yearly_seasonality=True, weekly_seasonality=True, changepoint_prior_scale=0.05)
m3_default.fit(df3)
future3 = m3_default.make_future_dataframe(periods=30)
forecast3_default = m3_default.predict(future3)

# 敏感版 Prophet（changepoint 更敏感）
m3_sensitive = Prophet(yearly_seasonality=True, weekly_seasonality=True, changepoint_prior_scale=0.5)
m3_sensitive.fit(df3)
forecast3_sensitive = m3_sensitive.predict(future3)

fig5, axes = plt.subplots(2, 1, figsize=(10, 8))

# 默认版
axes[0].plot(df3['ds'], df3['y'], 'k.', alpha=0.3, label='历史数据')
axes[0].plot(forecast3_default['ds'], forecast3_default['yhat'], 'b-', label='预测')
axes[0].fill_between(forecast3_default['ds'], forecast3_default['yhat_lower'], forecast3_default['yhat_upper'], alpha=0.2)
axes[0].axvline(pd.Timestamp('2023-08-23'), color='r', linestyle='--', alpha=0.7, label='产品改版（2023-08-23）')
axes[0].set_title('changepoint_prior_scale=0.05（默认，趋势平滑）', fontsize=12)
axes[0].legend()
axes[0].set_ylabel('DAU')

# 敏感版
axes[1].plot(df3['ds'], df3['y'], 'k.', alpha=0.3, label='历史数据')
axes[1].plot(forecast3_sensitive['ds'], forecast3_sensitive['yhat'], 'b-', label='预测')
axes[1].fill_between(forecast3_sensitive['ds'], forecast3_sensitive['yhat_lower'], forecast3_sensitive['yhat_upper'], alpha=0.2)
axes[1].axvline(pd.Timestamp('2023-08-23'), color='r', linestyle='--', alpha=0.7, label='产品改版（2023-08-23）')
axes[1].set_title('changepoint_prior_scale=0.5（敏感，快速捕捉趋势变化）', fontsize=12)
axes[1].legend()
axes[1].set_ylabel('DAU')
axes[1].set_xlabel('日期')

plt.suptitle('场景3：突变点检测对比', fontsize=14, y=1.02)
plt.tight_layout()
plt.savefig('prophet_example3_changepoint.png', dpi=150, bbox_inches='tight')
plt.close()

print("图片已保存：prophet_example3_changepoint.png")
print()

# ==================== 场景4：多季节 + 置信区间 + 交叉验证 ====================
print("=== 场景4：电力需求预测（多季节+置信区间） ===")

# 模拟电力需求：年周期（夏冬高峰）+ 周周期（工作日高）+ 日周期（不用，因为是日数据）
dates4 = pd.date_range('2022-01-01', '2024-04-30', freq='h')
# 太多了，用日数据吧，但展示 weekly 和 yearly
dates4 = pd.date_range('2022-01-01', '2024-04-30', freq='D')
n4 = len(dates4)

trend4 = np.linspace(1000, 1200, n4)
# 年周期：夏冬双高峰（用两个sin叠加）
yearly4 = 150 * np.sin(2 * np.pi * np.arange(n4) / 365.25) + 80 * np.sin(4 * np.pi * np.arange(n4) / 365.25)
# 周周期：工作日高，周末低
weekly4 = 50 * np.sin(2 * np.pi * np.arange(n4) / 7)
noise4 = np.random.normal(0, 20, n4)

y4 = trend4 + yearly4 + weekly4 + noise4
y4 = np.maximum(y4, 500)

df4 = pd.DataFrame({'ds': dates4, 'y': y4})

m4 = Prophet(
    yearly_seasonality=True,
    weekly_seasonality=True,
    daily_seasonality=False,
    interval_width=0.95,  # 95% 置信区间
    changepoint_prior_scale=0.1
)
m4.fit(df4)

future4 = m4.make_future_dataframe(periods=60)
forecast4 = m4.predict(future4)

fig6 = m4.plot(forecast4)
plt.title('场景4：电力需求预测（60天，95%置信区间）', fontsize=14, pad=20)
plt.xlabel('日期')
plt.ylabel('电力需求（MW）')
plt.tight_layout()
plt.savefig('prophet_example4_forecast.png', dpi=150, bbox_inches='tight')
plt.close()

fig7 = m4.plot_components(forecast4)
plt.suptitle('场景4：年季节 + 周季节分解', fontsize=14, y=1.02)
plt.tight_layout()
plt.savefig('prophet_example4_components.png', dpi=150, bbox_inches='tight')
plt.close()

print(f"预测未来60天，均值：{forecast4['yhat'].tail(60).mean():.1f} MW")
print(f"95% 区间宽度：{forecast4['yhat_upper'].tail(60).mean() - forecast4['yhat_lower'].tail(60).mean():.1f}")
print("图片已保存：prophet_example4_forecast.png, prophet_example4_components.png")
print()

print("="*50)
print("所有图片生成完毕！")
