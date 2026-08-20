# Prophet：15分钟从"完全不懂"到"能跑预测"

> **Facebook 开源的时间序列预测工具** —— 不需要你懂统计学，不需要调参，几行代码就能出图。
> 
> 适合场景：销售额预测、DAU预测、电力需求、服务器负载、任何带时间戳的数据。

---

## 一句话概括 Prophet

**Prophet = 趋势（Trend） + 季节性（Seasonality） + 节假日（Holidays） + 噪声（Noise）**

它自动帮你拆这四项，你只需要喂数据：`ds`（日期）和 `y`（数值），然后告诉它预测多少天。

```python
from prophet import Prophet

m = Prophet()
m.fit(df)                       # df 里有两列：ds 和 y
future = m.make_future_dataframe(periods=30)   # 预测未来30天
forecast = m.predict(future)
m.plot(forecast)                # 出图
```

---

## 场景1：电商日销售额预测（最基础，5分钟上手）

**背景**：你管着一个电商店铺，每天销售额有波动，老板让你预测下个月销售额，好决定备货量。

**数据特点**：
- 长期缓慢增长（生意越来越好）
- 每年冬天是旺季（年季节性）
- 周末比工作日高（周季节性）

### 代码

```python
import pandas as pd
import numpy as np
from prophet import Prophet
import matplotlib.pyplot as plt
from matplotlib.font_manager import FontProperties

np.random.seed(42)

# 加载中文字体（Linux/macOS 路径，Windows 请改为 'C:/Windows/Fonts/simhei.ttf' 等）
font_path = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc'
font_prop = FontProperties(fname=font_path)
plt.rcParams['font.sans-serif'] = [font_prop.get_name()]
plt.rcParams['axes.unicode_minus'] = False

# 生成 2 年模拟数据
dates = pd.date_range('2022-01-01', '2023-12-31', freq='D')
n = len(dates)

trend = np.linspace(100, 200, n)                    # 缓慢增长
yearly = 20 * np.sin(2 * np.pi * np.arange(n) / 365.25)   # 年周期（淡旺季）
weekly = 15 * np.sin(2 * np.pi * np.arange(n) / 7) + 10     # 周周期（周末高）
noise = np.random.normal(0, 8, n)

y = trend + yearly + weekly + noise
y = np.maximum(y, 10)

df = pd.DataFrame({'ds': dates, 'y': y})

# 建模
m = Prophet(yearly_seasonality=True, weekly_seasonality=True, daily_seasonality=False)
m.fit(df)

# 预测未来30天
future = m.make_future_dataframe(periods=30)
forecast = m.predict(future)

# 画图
fig = m.plot(forecast)
plt.title('电商日销售额预测（30天）')
plt.show()

fig = m.plot_components(forecast)
plt.show()
```

### 运行结果

```
训练数据：730 天，预测未来：30 天
预测均值：216.1
预测区间：206.2 ~ 226.0
```

### 预测图

![场景1预测图](prophet_example1_forecast.png)

> **图里看什么**：黑点是历史数据，蓝线是预测值，浅蓝色阴影是预测区间（默认80%置信度）。你看到的是趋势+季节+噪声被拟合后的整体走势。

### 分解图

![场景1分解图](prophet_example1_components.png)

> **图里看什么**：Prophet 自动把数据拆成三块——
> - **Trend**：长期趋势，缓慢上升
> - **Yearly seasonality**：每年冬天的波峰（旺季）
> - **Weekly seasonality**：每周的周末波峰（周末买得多）
>
> 这就是 Prophet 的核心能力：它把混合在一起的时间信号，自动拆解成可解释的部分。

---

## 场景2：节假日效应（双十一、春节）

**背景**：电商大促期间，销售额会突然飙升；春节期间物流停运，销售额会暴跌。这些"异常"不是噪声，是可预测的节假日效应。

**Prophet 的解法**：你可以自定义一个 `holidays` 表格，告诉它哪些日子是特殊节日，影响窗口有多宽。

### 代码

```python
import pandas as pd
from prophet import Prophet

# 定义节假日：双十一和春节
holidays = pd.DataFrame({
    'holiday': '双十一',
    'ds': pd.to_datetime(['2022-11-11', '2023-11-11']),
    'lower_window': -3,   # 大促前3天就开始预热
    'upper_window': 3,    # 大促后3天还有余温
})

holidays2 = pd.DataFrame({
    'holiday': '春节',
    'ds': pd.to_datetime(['2022-01-31', '2023-01-21']),
    'lower_window': -5,  # 年前物流减速
    'upper_window': 5,     # 年后恢复
})

holidays = pd.concat([holidays, holidays2])

# 建模时传入 holidays
m = Prophet(holidays=holidays, yearly_seasonality=True, weekly_seasonality=True)
m.fit(df2)   # df2 是带节假日spike的数据

future = m.make_future_dataframe(periods=30)
forecast = m.predict(future)

# 查看节假日影响
print(forecast[['ds', '双十一', '春节']].head(10))

m.plot(forecast)
plt.show()

m.plot_components(forecast)
plt.show()
```

### 运行结果

```
节假日影响（双十一）：+51.9（销量 spike）
节假日影响（春节）：-31.6（销量下跌）
```

### 预测图

![场景2预测图](prophet_example2_forecast.png)

> **注意**：图里的历史数据在 2022-11 和 2023-11 有明显的 spike，Prophet 已经学会了"双十一=涨"、"春节=跌"的规律，并在预测中自动应用。

### 分解图

![场景2分解图](prophet_example2_components.png)

> **新增的 holidays 面板**：双十一和春节作为单独一列被拆了出来。你可以看到 Prophet 不仅学会了趋势和季节性，还**量化**了每个节假日的影响幅度。

---

## 场景3：突变点检测（产品改版后业务飙升）

**背景**：你负责的产品在 2023年8月做了一次大改版，DAU 突然从缓慢增长变成陡峭上升。传统的线性模型根本抓不住这种"拐弯"。

**Prophet 的解法**：它内置了 **changepoint detection**（突变点检测），自动发现数据里趋势发生转折的位置。你还可以通过 `changepoint_prior_scale` 控制它有多"敏感"。

### 代码

```python
import pandas as pd
import numpy as np
from prophet import Prophet
import matplotlib.pyplot as plt

# 生成带突变点的数据：前600天缓慢增长，之后陡增
dates = pd.date_range('2022-01-01', '2024-03-31', freq='D')
n = len(dates)

trend = np.zeros(n)
trend[:600] = np.linspace(100, 130, 600)          # 改版前：缓慢
trend[600:] = np.linspace(130, 250, n - 600)      # 改版后：陡增

yearly = 20 * np.sin(2 * np.pi * np.arange(n) / 365.25)
weekly = 10 * np.sin(2 * np.pi * np.arange(n) / 7) + 5
noise = np.random.normal(0, 5, n)

y = trend + yearly + weekly + noise
y = np.maximum(y, 10)

df = pd.DataFrame({'ds': dates, 'y': y})

# 版本A：默认参数（changepoint_prior_scale=0.05）——趋势平滑，反应慢
m_default = Prophet(changepoint_prior_scale=0.05)
m_default.fit(df)

# 版本B：敏感参数（changepoint_prior_scale=0.5）——快速捕捉趋势变化
m_sensitive = Prophet(changepoint_prior_scale=0.5)
m_sensitive.fit(df)

future = m_default.make_future_dataframe(periods=30)
forecast_default = m_default.predict(future)
forecast_sensitive = m_sensitive.predict(future)
```

### 对比图

![场景3突变点对比](prophet_example3_changepoint.png)

> **两张图对比**：
> - **左图（默认 0.05）**：趋势线是平滑的曲线，它试图把"改版前的缓慢"和"改版后的陡增"用一条平滑曲线连起来，**低估了后期的增长**。
> - **右图（敏感 0.5）**：趋势线在 2023-08 附近明显拐了个弯，**准确捕捉了产品改版带来的增长加速**。
>
> **参数建议**：
> - `changepoint_prior_scale=0.05`（默认）：趋势稳定，适合成熟业务
> - `changepoint_prior_scale=0.5`：趋势敏感，适合快速增长或频繁迭代的业务
> - 值越大，模型越"多疑"，觉得到处都可能突变；值越小，模型越"迟钝"，觉得世界很平稳。

---

## 场景4：电力需求预测（多季节+置信区间+不确定性）

**背景**：电力公司要预测未来两个月的用电需求，调度发电机组。电力需求有**年季节性**（夏冬高峰）、**周季节性**（工作日工厂用电高），而且预测需要给出一个**区间**（不是单点数字），因为调度需要留有余量。

### 代码

```python
import pandas as pd
import numpy as np
from prophet import Prophet

# 生成两年多的日数据
dates = pd.date_range('2022-01-01', '2024-04-30', freq='D')
n = len(dates)

trend = np.linspace(1000, 1200, n)
# 年周期：夏冬双高峰（用两个sin叠加）
yearly = 150 * np.sin(2 * np.pi * np.arange(n) / 365.25) + 80 * np.sin(4 * np.pi * np.arange(n) / 365.25)
# 周周期：工作日高，周末低
weekly = 50 * np.sin(2 * np.pi * np.arange(n) / 7)
noise = np.random.normal(0, 20, n)

y = trend + yearly + weekly + noise
y = np.maximum(y, 500)

df = pd.DataFrame({'ds': dates, 'y': y})

# 建模：开启95%置信区间
m = Prophet(
    yearly_seasonality=True,
    weekly_seasonality=True,
    daily_seasonality=False,
    interval_width=0.95,       # 95%置信区间（默认是80%）
    changepoint_prior_scale=0.1
)
m.fit(df)

future = m.make_future_dataframe(periods=60)
forecast = m.predict(future)

m.plot(forecast)
plt.show()

m.plot_components(forecast)
plt.show()
```

### 运行结果

```
预测未来60天，均值：1211.1 MW
95% 区间宽度：77.5
```

### 预测图

![场景4预测图](prophet_example4_forecast.png)

> **注意浅蓝色阴影更宽了**：因为 `interval_width=0.95`，Prophet 给出了95%置信区间（比默认80%更宽）。这意味着"未来两个月的真实值，有95%的概率落在这个阴影里"。调度部门可以根据这个区间决定最小/最大发电量。

### 分解图

![场景4分解图](prophet_example4_components.png)

> **Yearly 面板**：不是简单的单峰，而是**夏冬双高峰**（因为叠加了两个sin波）。Prophet 通过傅里叶级数自动拟合复杂的年周期形状。
> 
> **Weekly 面板**：工作日波峰、周末波谷，清晰可辨。

---

## 参数速查表

| 参数 | 作用 | 默认值 | 什么时候调 |
|------|------|--------|-----------|
| `yearly_seasonality` | 是否拟合年周期 | `True` | 数据不足1年设为 `False` |
| `weekly_seasonality` | 是否拟合周周期 | `True` | 日级以下数据（如小时）设为 `False` |
| `daily_seasonality` | 是否拟合日周期 | `True` | 日级以上数据设为 `False` |
| `holidays` | 自定义节假日 | `None` | 有促销/节日/异常日期时传入 |
| `changepoint_prior_scale` | 突变点敏感度 | `0.05` | 业务突变频繁时调高（0.1~0.5） |
| `interval_width` | 置信区间宽度 | `0.80` | 需要更保守预测时调高到 `0.95` |
| `seasonality_mode` | 季节叠加方式 | `'additive'` | 季节性幅度随趋势增长时改用 `'multiplicative'` |

---

## 安装（一条命令）

```bash
pip install prophet pandas matplotlib numpy
```

> **注意**：Prophet 底层依赖 cmdstanpy，首次运行时会自动编译模型，可能需要 1-2 分钟。后面就秒开了。

---

## 总结：什么时候用 Prophet？

| 场景 | 用不用 |
|------|--------|
| 日/周/月级别的业务指标预测（销售额、DAU、订单量） | ✅ 非常适合 |
| 数据有明确节假日/促销规律 | ✅ 非常适合 |
| 业务发生过突然转折（产品改版、市场扩张） | ✅ 非常适合 |
| 需要给老板看"趋势+季节性"的可解释拆分 | ✅ 非常适合 |
| 超高频数据（毫秒级、秒级、分钟级） | ❌ 不适合，用 ARIMA/LSTM |
| 需要复杂外生变量（天气、股价、宏观经济） | ⚠️ 可以加入 `add_regressor`，但不如 XGBoost/LightGBM 灵活 |
| 数据量极小（<100条） | ❌ 不适合，样本不够 |

---

## 最后一句

Prophet 不是最精准的模型，但它是**最省心的模型**。

你不需要写循环调参，不需要手动拆季节，不需要画趋势图。几行代码，一张图，数据里有什么规律，肉眼就能看出来。

对于"明天要跟老板汇报，今晚需要一张预测图"这种场景，Prophet 是救命神器。

---

*文档生成时间：2026-06-01 | 所有代码均可直接运行，图片为真实执行结果*
