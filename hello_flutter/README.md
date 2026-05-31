# 人体采集系统 - Human Capture System

基于 Flutter + MediaPipe Pose + IMU 的智能人体采集应用，实现自动拍照功能。

## 📱 功能特性

### 核心功能
- ✅ **相机预览**：高分辨率后置摄像头实时预览
- ✅ **人体站位框**：GPU加速绘制的动态引导框
- ✅ **人体关键点检测**：MediaPipe Pose（32个关键点）
- ✅ **手机倾斜检测**：IMU传感器（加速度计+陀螺仪）
- ✅ **距离估算**：基于人体占屏幕比例法
- ✅ **自动拍照**：智能判断5大条件后自动触发

### 自动拍照触发条件
1. ✅ 人体完整进入画面
2. ✅ 距离占比合理（50%-85%）
3. ✅ 手机姿态正常（俯仰角/翻滚角 ≤ 5°）
4. ✅ 人体静止（加速度标准差 < 0.5 m/s²）
5. ✅ 数据稳定（至少检测到25个关键点）

### 用户体验
- 🎯 动画引导和半透明遮罩
- 📊 实时状态面板显示四大指标
- ⏱️ 3秒倒计时自动拍照
- 🔘 手动拍照按钮作为备用
- 🔄 拍照后可重新拍摄或确认使用

## 🏗️ 技术架构

### 技术栈
- **UI框架**: Flutter（跨平台：Android/iOS/Web）
- **摄像头**: `camera` 插件（实时帧流、高分辨率）
- **人体检测**: `google_mlkit_pose_detection`（MediaPipe Pose）
- **传感器**: `sensors_plus`（加速度计+陀螺仪）
- **文件存储**: `path_provider` + `image`
- **权限管理**: `permission_handler`

### 项目结构
```
lib/
├── main.dart                          # 应用入口
├── models/
│   └── detection_metrics.dart         # 数据模型（检测指标）
├── services/
│   ├── camera_service.dart            # 相机服务
│   ├── pose_detection_service.dart    # 姿态检测服务（MediaPipe）
│   └── imu_service.dart               # IMU传感器服务
├── screens/
│   └── capture_screen.dart            # 主采集界面
└── widgets/
    ├── camera_preview_widget.dart     # 相机预览组件
    ├── status_panel.dart              # 状态面板组件
    └── guidance_overlay.dart          # 引导遮罩组件
```

## 🚀 快速开始

### 环境要求
- Flutter SDK >= 3.11.5
- Dart >= 3.0.0
- Android: minSdkVersion 21, targetSdkVersion 35
- iOS: Minimum Deployment Target 15.5

### 安装依赖
```bash
flutter pub get
```

### 运行应用
```bash
# 连接设备后运行
flutter run

# 指定设备运行
flutter run -d <device_id>

# 查看可用设备
flutter devices
```

### 构建发布版本
```bash
# Android APK
flutter build apk --release

# iOS
flutter build ios --release

# Web
flutter build web --release
```

## 📖 使用说明

### 拍照流程
1. **启动应用**：自动打开相机并初始化传感器
2. **调整站位**：
   - 将全身放入引导框内
   - 双脚分开与肩同宽
   - 双手自然下垂
3. **等待检测**：
   - 观察顶部状态面板的四个指标
   - 确保所有指标变为绿色
4. **自动拍照**：
   - 当所有条件满足时，显示3秒倒计时
   - 倒计时结束后自动拍照
5. **确认结果**：
   - 查看拍摄的照片
   - 选择"确认使用"或"重新拍摄"

### 状态指标说明
| 指标 | 图标 | 说明 | 合格标准 |
|------|------|------|----------|
| 完整性 | 👤 | 人体是否在画面内 | 检测到所有关键部位 |
| 距离 | 📏 | 人体占屏幕比例 | 50% - 85% |
| 姿态 | 📱 | 手机是否水平 | 俯仰角/翻滚角 ≤ 5° |
| 稳定 | ⚖️ | 手机是否晃动 | 加速度标准差 < 0.5 |

### 颜色提示
- 🟢 **绿色**：条件满足，可以拍照
- 🟠 **橙色**：部分条件满足，接近就绪
- 🔴 **红色**：条件不满足，需要调整

## 🔧 开发指南

### 自定义参数
在 `models/detection_metrics.dart` 中修改阈值：
```dart
bool get canAutoCapture {
  return isHumanComplete &&
      distanceRatio >= 0.5 && distanceRatio <= 0.85 &&  // 调整距离范围
      isPhoneLevel &&
      isStable &&
      landmarkCount >= 25;  // 调整关键点数量要求
}
```

在 `services/imu_service.dart` 中修改稳定性阈值：
```dart
static const double _stabilityThreshold = 0.5;  // 调整稳定性阈值
```

### 接入真实 ML Kit
当前使用模拟数据进行演示，要接入真实的 MediaPipe Pose：

1. 在 `pose_detection_service.dart` 中实现 `_convertToInputImage()` 方法
2. 取消注释 `processCameraImage()` 中的真实检测逻辑
3. 根据相机格式正确转换图像数据

示例：
```dart
InputImage? _convertToInputImage(CameraImage image) {
  // 根据实际的相机格式进行转换
  final WriteBuffer allBytes = WriteBuffer();
  for (Plane plane in image.planes) {
    allBytes.putUint8List(plane.bytes);
  }
  final bytes = allBytes.done().buffer.asUint8List();

  final Size imageSize = Size(
    image.width.toDouble(),
    image.height.toDouble(),
  );

  final InputImageRotation imageRotation = 
      InputImageRotationValue.fromRawValue(image.rotation) ??
      InputImageRotation.rotation0deg;

  final InputImageFormat inputImageFormat = 
      InputImageFormatValue.fromRawValue(image.format.raw) ??
      InputImageFormat.nv21;

  final planeData = image.planes.map(
    (Plane plane) {
      return InputImagePlaneMetadata(
        bytesPerRow: plane.bytesPerRow,
        height: plane.height,
        width: plane.width,
      );
    },
  ).toList();

  final inputImageData = InputImageData(
    size: imageSize,
    rotation: imageRotation,
    format: inputImageFormat,
    planeData: planeData,
  );

  return InputImage.fromBytes(
    bytes: bytes,
    inputImageData: inputImageData,
  );
}
```

## 🐛 常见问题

### 1. 相机无法打开
- 检查是否授予相机权限
- 确保设备有后置摄像头
- 在 AndroidManifest.xml 中添加权限

### 2. 传感器数据不准确
- 确保设备支持加速度计和陀螺仪
- 在真机上测试（模拟器可能不支持传感器）

### 3. 人体检测不准确
- 确保光线充足
- 背景尽量简洁
- 穿着与背景对比明显的服装

### 4. iOS 构建失败
- 检查 Xcode 版本 >= 15.3.0
- 确保 iOS Deployment Target >= 15.5
- 排除 armv7 架构

## 📝 待办事项

- [ ] 接入真实的 MediaPipe Pose 检测
- [ ] 添加照片预览和编辑功能
- [ ] 支持批量拍摄模式
- [ ] 添加云端同步功能
- [ ] 优化检测算法性能
- [ ] 添加多语言支持

## 📄 许可证

MIT License

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📧 联系方式

如有问题或建议，请通过 GitHub Issues 联系。
