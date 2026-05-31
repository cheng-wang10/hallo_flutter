# 🔄 水平检测改为竖直检测 - 完整修改报告

## 📋 修改概述

将人体采集系统的姿态检测从**要求手机水平持握**改为**要求手机竖直持握**（Portrait 模式），更符合实际拍照习惯。

---

## ✅ 已完成的修改

### 1️⃣ IMU 传感器服务 (`imu_service.dart`)

#### 新增竖直检测方法

```dart
/// ✅ 新增：判断手机是否竖直（Portrait模式）
bool _isPhoneVertical() {
  // 竖直持机时，俯仰角应接近90度（或-90度）
  // 允许 ±10度的误差范围
  final isPortraitUp = (_pitch - 90.0).abs() <= 10.0;
  final isPortraitDown = (_pitch + 90.0).abs() <= 10.0;
  
  // 翻滚角应该接近0度（手机没有左右倾斜）
  final isRollOk = _roll.abs() <= 10.0;
  
  return (isPortraitUp || isPortraitDown) && isRollOk;
}
```

**原理说明**：
- **水平持机**：俯仰角 ≈ 0°（手机平行于地面）
- **竖直持机**：俯仰角 ≈ 90° 或 -90°（手机垂直于地面）
- **容差范围**：±10°（允许轻微倾斜）

#### 更新回调函数签名

```dart
// ❌ 旧版
Function(double pitch, double roll, bool isLevel, bool isStable)? onIMUUpdate;

// ✅ 新版
Function(double pitch, double roll, bool isVertical, bool isStable)? onIMUUpdate;
```

#### 更新数据处理逻辑

```dart
void _processAccelerometer(AccelerometerEvent event) {
  // ... 计算角度 ...
  
  // ✅ 修改：判断是否竖直（而非水平）
  final isVertical = _isPhoneVertical();
  final isStable = _isPhoneStable();
  
  // 通知更新
  onIMUUpdate?.call(_pitch, _roll, isVertical, isStable);
}
```

---

### 2️⃣ 数据模型 (`detection_metrics.dart`)

#### 字段重命名

```dart
class DetectionMetrics {
  final bool isHumanComplete;
  final double distanceRatio;
  final bool isPhoneVertical;  // ✅ 从 isPhoneLevel 改为 isPhoneVertical
  final bool isStable;
  final double pitch;
  final double roll;
  final int landmarkCount;
}
```

#### 更新自动拍照条件

```dart
bool get canAutoCapture {
  return isHumanComplete &&
      distanceRatio >= 0.5 && distanceRatio <= 0.85 &&
      isPhoneVertical &&  // ✅ 修改：要求手机竖直
      isStable &&
      landmarkCount >= 25;
}
```

#### 更新状态提示文本

```dart
String getStatusText() {
  if (!isHumanComplete) return '请确保全身在画面内';
  if (distanceRatio < 0.5) return '请后退一些';
  if (distanceRatio > 0.85) return '请靠近一些';
  if (!isPhoneVertical) return '请将手机竖直持握';  // ✅ 修改提示
  if (!isStable) return '请保持稳定';
  return '准备就绪，即将拍照';
}
```

---

### 3️⃣ 主控制器 (`capture_screen.dart`)

#### 更新 IMU 回调

```dart
_imuService.onIMUUpdate = (pitch, roll, isVertical, isStable) {
  setState(() {
    _metrics = DetectionMetrics(
      isHumanComplete: _metrics.isHumanComplete,
      distanceRatio: _metrics.distanceRatio,
      isPhoneVertical: isVertical,  // ✅ 使用竖直状态
      isStable: isStable,
      pitch: pitch,
      roll: roll,
      landmarkCount: _metrics.landmarkCount,
    );
    _checkAutoCapture();
  });
};
```

---

### 4️⃣ 状态面板 (`status_panel.dart`)

#### 更新姿态指标显示

```dart
_buildIndicator(
  icon: Icons.screen_rotation,
  label: '姿态',
  value: metrics.isPhoneVertical ? '竖直' : '倾斜',  // ✅ 显示竖直状态
  isOk: metrics.isPhoneVertical,
),
```

**显示效果**：
- ✅ 绿色 + "竖直"：手机处于正确的竖直姿态
- ❌ 红色 + "倾斜"：需要调整为竖直持握

---

### 5️⃣ 引导遮罩 (`guidance_overlay.dart`)

#### 更新文字提示

```dart
String topText;
if (!metrics.isHumanComplete) {
  topText = '请将全身放入框内';
} else if (metrics.distanceRatio < 0.5) {
  topText = '请后退一些';
} else if (metrics.distanceRatio > 0.85) {
  topText = '请靠近一些';
} else if (!metrics.isPhoneVertical) {  // ✅ 检查竖直状态
  topText = '请将手机竖直持握';
} else if (!metrics.isStable) {
  topText = '请保持稳定';
} else {
  topText = '保持姿势，即将拍照';
}
```

---

### 6️⃣ 姿态检测服务 (`pose_detection_service.dart`)

#### 更新模拟数据

```dart
void _simulateDetection() {
  final metrics = DetectionMetrics(
    isHumanComplete: true,
    distanceRatio: 0.65,
    isPhoneVertical: true,  // ✅ 模拟竖直状态
    isStable: true,
    pitch: 90.0,            // ✅ 模拟俯仰角90度（竖直）
    roll: 0.0,              // ✅ 模拟翻滚角0度
    landmarkCount: 32,
  );
  
  onMetricsUpdate?.call(metrics);
}
```

---

## 🎯 修改后的行为

### 自动拍照条件（最终版）

| 条件 | 说明 | 阈值/要求 |
|------|------|-----------|
| ✅ 人体完整 | 7个关键部位都检测到 | - |
| ✅ 距离合适 | 鼻子到脚踝占屏幕50%-85% | 0.5-0.85 |
| ✅ **手机竖直** | **俯仰角约90°，翻滚角<10°** | **pitch≈90°, roll<10°** |
| ✅ 身体稳定 | 加速度标准差 < 0.5 | < 0.5 m/s² |
| ✅ 关键点充足 | 至少检测到25个关键点 | ≥ 25 |

### 用户操作流程

1. **竖直持机**：将手机垂直于地面（像平时拍照一样）
2. **对准人物**：确保人物全身在引导框内
3. **调整距离**：站在2-3米处，使人体占屏幕50%-85%
4. **保持稳定**：手持手机不要晃动
5. **等待拍照**：满足所有条件后，3秒倒计时自动拍照

---

## 📊 角度说明

### 俯仰角 (Pitch)

```
        90° (竖直向上)
         |
         |
0° ------+------ 180° (水平)
         |
         |
       -90° (竖直向下)
```

**竖直持机时**：
- 手机顶部朝上：pitch ≈ 90°
- 手机顶部朝下：pitch ≈ -90°
- 允许误差：±10°

### 翻滚角 (Roll)

```
       手机顶部
         ↑
         |
-90° ←---+---> 90°
         |
         ↓
       手机底部
```

**正确持握时**：
- roll ≈ 0°（手机没有左右倾斜）
- 允许误差：±10°

---

## 🧪 测试验证

### 测试步骤

1. **重新安装依赖**
   ```bash
   flutter pub get
   ```

2. **运行应用**
   ```bash
   flutter run
   ```

3. **验证竖直检测**
   
   **测试A：竖直持机**
   - 将手机竖直持握（正常拍照姿势）
   - 观察状态面板的"姿态"指标
   - 应显示：**绿色 + "竖直"**
   - 俯仰角应显示：**~90°** 或 **~-90°**
   
   **测试B：水平持机**
   - 将手机水平持握（平行于地面）
   - 观察状态面板的"姿态"指标
   - 应显示：**红色 + "倾斜"**
   - 俯仰角应显示：**~0°**
   
   **测试C：倾斜持机**
   - 将手机倾斜45°
   - 观察状态面板的"姿态"指标
   - 应显示：**红色 + "倾斜"**
   - 俯仰角应显示：**~45°**

4. **验证自动拍照**
   - 竖直持机
   - 确保人物在框内
   - 调整到合适距离
   - 保持稳定
   - 应触发3秒倒计时并自动拍照

5. **查看日志**
   ```bash
   # 查看详细日志
   flutter run -v | grep "IMU\|姿态"
   ```
   
   预期输出：
   ```
   [IMU] Pitch: 88.5°, Roll: 2.3°, Vertical: true, Stable: true
   ```

---

## ⚠️ 注意事项

### 1. 为什么选择竖直持机？

**优势**：
- ✅ 符合日常拍照习惯
- ✅ 更容易拍摄全身照
- ✅ 相机视野更适合人像
- ✅ 更稳定的持握方式

**对比水平持机**：
- ❌ 水平持机需要双手平举，容易疲劳
- ❌ 视野过宽，人物占比小
- ❌ 不符合自然拍照姿势

### 2. 容差范围设置

当前设置：
- 俯仰角：90° ± 10°（即 80°-100° 或 -80° 到 -100°）
- 翻滚角：0° ± 10°（即 -10° 到 10°）

**如需调整**，修改 `imu_service.dart` 中的 `_isPhoneVertical()` 方法：

```dart
bool _isPhoneVertical() {
  final tolerance = 15.0;  // 可调整容差（当前10°）
  final isPortraitUp = (_pitch - 90.0).abs() <= tolerance;
  final isPortraitDown = (_pitch + 90.0).abs() <= tolerance;
  final isRollOk = _roll.abs() <= tolerance;
  
  return (isPortraitUp || isPortraitDown) && isRollOk;
}
```

### 3. ML Kit 人体检测

**如果检测不到人体**，请检查：

1. **相机格式配置**：
   - Android: NV21
   - iOS: BGRA8888
   - 已在 `camera_service.dart` 中配置

2. **环境因素**：
   - 光线充足
   - 背景简洁
   - 距离合适（2-3米）
   - 穿着与背景对比明显

3. **查看日志**：
   ```
   🔍 [ML Kit] 开始处理图像...
      尺寸: Size(1080.0, 1920.0)
      格式: InputImageFormat.nv21
   ✅ [ML Kit] 检测到 1 个人体
   📊 [ML Kit] 关键点数量: 32
   ```

---

## 📝 修改文件清单

| 文件 | 修改内容 | 行数变化 |
|------|---------|----------|
| `lib/services/imu_service.dart` | 添加 `_isPhoneVertical()` 方法，更新回调 | +20 |
| `lib/models/detection_metrics.dart` | 字段重命名，更新逻辑 | ~10 |
| `lib/screens/capture_screen.dart` | 更新 IMU 回调参数 | ~5 |
| `lib/widgets/status_panel.dart` | 更新姿态显示文本 | ~3 |
| `lib/widgets/guidance_overlay.dart` | 更新提示文字 | ~3 |
| `lib/services/pose_detection_service.dart` | 更新模拟数据 | ~5 |

**总计**：6个文件，约46行代码修改

---

## 🎉 总结

### 核心改动

✅ **水平检测 → 竖直检测**  
✅ **isPhoneLevel → isPhoneVertical**  
✅ **pitch ≈ 0° → pitch ≈ 90°**  
✅ **提示文字全部更新**  

### 用户体验提升

- ✅ 更符合自然拍照习惯
- ✅ 操作更舒适
- ✅ 提示更清晰
- ✅ 检测更准确

### 下一步

1. 运行 `flutter pub get`
2. 连接真机
3. 运行 `flutter run`
4. **竖直持机**测试应用
5. 享受智能拍照体验！

---

**修改完成时间**: 2026-05-25  
**测试状态**: 代码无编译错误，待真机验证  
**文档版本**: v1.0
