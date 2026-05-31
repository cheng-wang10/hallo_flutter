import 'dart:async';
import 'dart:math';
import 'package:sensors_plus/sensors_plus.dart';

class IMUService {
  StreamSubscription? _accelerometerSubscription;
  StreamSubscription? _gyroscopeSubscription;
  
  // 当前传感器数据
  double _pitch = 0.0;  // 俯仰角
  double _roll = 0.0;   // 翻滚角
  double _acceleration = 0.0;  // 加速度大小
  
  // ✅ 新增：平滑滤波（减少抖动）
  double _smoothedPitch = 0.0;
  double _smoothedRoll = 0.0;
  static const double _smoothingFactor = 0.35;  // ✅ 优化：从0.25改为0.35，更快响应

  // 稳定性检测
  final List<double> _recentAccelerations = [];
  static const int _stabilityWindowSize = 15;  // ✅ 优化：从20改为15（约0.75秒），更快响应
  static const double _stabilityThreshold = 1.8;  // ✅ 优化：从1.5改为1.8，更宽松以快速判定稳定

  // 回调函数
  Function(double pitch, double roll, bool isVertical, bool isStable)? onIMUUpdate;

  /// 开始监听传感器
  void startListening() {
    // 监听加速度计
    _accelerometerSubscription = accelerometerEvents.listen(
      (AccelerometerEvent event) {
        _processAccelerometer(event);
      },
      onError: (e) {
        print('Accelerometer error: $e');
      },
    );

    // 监听陀螺仪（可选，用于更精确的姿态检测）
    _gyroscopeSubscription = gyroscopeEvents.listen(
      (GyroscopeEvent event) {
        // 可以结合陀螺仪数据进行滤波
      },
      onError: (e) {
        print('Gyroscope error: $e');
      },
    );
  }

  /// 处理加速度计数据
  void _processAccelerometer(AccelerometerEvent event) {
    final x = event.x;
    final y = event.y;
    final z = event.z;

    // 计算俯仰角和翻滚角（单位：度）
    final rawPitch = _calculatePitch(x, y, z);
    final rawRoll = _calculateRoll(x, y, z);
    
    // ✅ 新增：应用指数移动平均滤波（EMA）
    _smoothedPitch = _smoothingFactor * rawPitch + (1 - _smoothingFactor) * _smoothedPitch;
    _smoothedRoll = _smoothingFactor * rawRoll + (1 - _smoothingFactor) * _smoothedRoll;
    
    // 使用平滑后的角度
    _pitch = _smoothedPitch;
    _roll = _smoothedRoll;
    
    // 计算加速度大小
    _acceleration = sqrt(x * x + y * y + z * z);
    
    // 更新稳定性检测窗口
    _updateStabilityWindow(_acceleration);
    
    // ✅ 修改：判断是否竖直（而非水平）
    final isVertical = _isPhoneVertical();
    
    // 判断是否稳定
    final isStable = _isPhoneStable();
    
    // 通知更新
    onIMUUpdate?.call(_pitch, _roll, isVertical, isStable);
  }

  /// 计算俯仰角（Pitch）
  double _calculatePitch(double x, double y, double z) {
    // Pitch: 绕X轴旋转的角度
    final pitch = atan2(y, sqrt(x * x + z * z)) * 180 / pi;
    return pitch;
  }

  /// 计算翻滚角（Roll）
  double _calculateRoll(double x, double y, double z) {
    // Roll: 绕Z轴旋转的角度
    final roll = atan2(-x, z) * 180 / pi;
    return roll;
  }

  /// 更新稳定性检测窗口
  void _updateStabilityWindow(double acceleration) {
    _recentAccelerations.add(acceleration);
    
    if (_recentAccelerations.length > _stabilityWindowSize) {
      _recentAccelerations.removeAt(0);
    }
  }

  /// 判断手机是否水平（已废弃，保留用于兼容）
  bool _isPhoneLevel() {
    // 俯仰角和翻滚角都在±5度以内
    return _pitch.abs() <= 5.0 && _roll.abs() <= 5.0;
  }

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

  /// 判断手机是否稳定
  bool _isPhoneStable() {
    if (_recentAccelerations.length < _stabilityWindowSize) {
      return false;
    }

    // 计算加速度的标准差
    final mean = _recentAccelerations.reduce((a, b) => a + b) / 
                 _recentAccelerations.length;
    
    final variance = _recentAccelerations.fold(0.0, (sum, value) {
      return sum + (value - mean) * (value - mean);
    }) / _recentAccelerations.length;
    
    final stdDev = sqrt(variance);
    
    // 标准差小于阈值视为稳定
    return stdDev < _stabilityThreshold;
  }

  /// 获取当前姿态数据
  Map<String, dynamic> getCurrentData() {
    return {
      'pitch': _pitch,
      'roll': _roll,
      'acceleration': _acceleration,
      'isLevel': _isPhoneLevel(),
      'isVertical': _isPhoneVertical(),  // ✅ 新增：竖直状态
      'isStable': _isPhoneStable(),
    };
  }

  /// 停止监听
  void stopListening() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _recentAccelerations.clear();
  }

  /// 释放资源
  void dispose() {
    stopListening();
  }
}
