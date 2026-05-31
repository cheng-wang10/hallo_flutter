import 'package:flutter/material.dart';

/// 人体姿态检测状态
enum CaptureStatus {
  idle,           // 空闲
  detecting,      // 检测中
  ready,          // 准备就绪
  capturing,      // 拍照中
  completed,      // 完成
}

/// ✅ 新增：状态平滑器（防止抖动导致的频繁切换）
class StateSmoother {
  // ✅ 优化：大幅增大迟滞范围，确保长期稳定
  static const double _distanceHysteresis = 0.10;  // 距离比例迟滞范围 ±0.10（从0.05增大）
  static const double _angleHysteresis = 15.0;     // 角度迟滞范围 ±15°（从5°大幅增大）
  
  // 历史状态
  bool _lastIsHumanComplete = false;
  bool _lastIsPhoneVertical = false;
  double _lastDistanceRatio = 0.0;
  int _consecutiveValidFrames = 0;  // ✅ 新增：连续有效帧计数
  int _consecutiveInvalidFrames = 0;  // ✅ 新增：连续无效帧计数
  
  // ✅ 优化：状态保持机制（一旦进入某状态，保持N秒不变）
  DateTime? _stateLockTime;  // 状态锁定开始时间
  static const Duration _stateLockDuration = Duration(seconds: 1);  // ✅ 从3秒改为1秒（更灵敏）
  bool _lockedState = false;  // 锁定的状态值
  
  /// 平滑人体完整性判断（添加迟滞 + 连续帧验证 + 状态保持）
  bool smoothHumanCompleteness(bool currentValue, {DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    
    // ✅ 状态保持机制：如果处于锁定期间，直接返回锁定状态
    if (_stateLockTime != null) {
      final elapsed = currentTime.difference(_stateLockTime!);
      if (elapsed < _stateLockDuration) {
        // 还在锁定期间，返回锁定状态
        return _lockedState;
      } else {
        // 锁定结束，重置
        _stateLockTime = null;
      }
    }
    
    if (currentValue) {
      _consecutiveValidFrames++;
      _consecutiveInvalidFrames = 0;
      
      // 需要连续3帧都完整才判定为完整（防误判）
      if (_consecutiveValidFrames >= 3 && !_lastIsHumanComplete) {
        // ✅ 状态改变，启动锁定
        _lastIsHumanComplete = true;
        _stateLockTime = currentTime;
        _lockedState = true;
        return true;
      }
      
      if (_lastIsHumanComplete) {
        // 已经是完整状态，重置计数器但保持锁定
        _consecutiveValidFrames = 3;  // 保持在阈值以上
        return true;
      }
      
      return _lastIsHumanComplete;  // 保持原状态
    } else {
      _consecutiveInvalidFrames++;
      _consecutiveValidFrames = 0;
      
      // ✅ 优化：从8帧改为4帧，更快响应人像移除（约1.3秒）
      if (_consecutiveInvalidFrames >= 4 && _lastIsHumanComplete) {
        // ✅ 状态改变，启动锁定
        _lastIsHumanComplete = false;
        _stateLockTime = currentTime;
        _lockedState = false;
        return false;
      }
      
      if (!_lastIsHumanComplete) {
        // 已经是不完整状态，重置计数器但保持锁定
        _consecutiveInvalidFrames = 8;  // 保持在阈值以上
        return false;
      }
      
      return _lastIsHumanComplete;  // 保持原状态
    }
  }
  
  /// 平滑竖直判断（优化迟滞，提高灵敏度）
  bool smoothPhoneVertical(double pitch, double roll) {
    final currentVertical = (pitch - 90.0).abs() <= 10.0 || 
                           (pitch + 90.0).abs() <= 10.0;
    final rollOk = roll.abs() <= 10.0;
    final currentValue = currentVertical && rollOk;
    
    // ✅ 优化：减小迟滞到±12°，提高响应灵敏度
    if (_lastIsPhoneVertical && !currentValue) {
      final relaxedVertical = (pitch - 90.0).abs() <= 22.0 ||  // 10+12
                             (pitch + 90.0).abs() <= 22.0;
      final relaxedRoll = roll.abs() <= 22.0;  // 10+12
      if (relaxedVertical && relaxedRoll) {
        return true;  // 保持竖直状态
      }
    }
    
    _lastIsPhoneVertical = currentValue;
    return currentValue;
  }
  
  /// 平滑距离比例（使用移动平均）
  double smoothDistanceRatio(double currentValue) {
    // ✅ 修复：如果当前值为0（未检测到），直接返回0，不使用EMA
    if (currentValue <= 0.01) {
      _lastDistanceRatio = 0.0;  // 重置
      return 0.0;
    }
    
    // ✅ 优化：调整EMA系数，更快响应变化
    // α=0.4: 比之前的0.3更快响应，但仍然有平滑效果
    _lastDistanceRatio = 0.6 * _lastDistanceRatio + 0.4 * currentValue;
    return _lastDistanceRatio;
  }
  
  /// 判断距离是否合适（添加迟滞）
  bool isDistanceAppropriate(double smoothedRatio) {
    // 如果之前在合适范围内，放宽边界
    final lowerBound = 0.5 - _distanceHysteresis;
    final upperBound = 0.85 + _distanceHysteresis;
    return smoothedRatio >= lowerBound && smoothedRatio <= upperBound;
  }
  
  /// 重置所有状态
  void reset() {
    _lastIsHumanComplete = false;
    _lastIsPhoneVertical = false;
    _lastDistanceRatio = 0.0;
    _consecutiveValidFrames = 0;
    _consecutiveInvalidFrames = 0;
  }
}

/// 检测指标状态
class DetectionMetrics {
  final bool isHumanComplete;     // 人体是否完整
  final double distanceRatio;     // 距离比例 (0-1)
  final bool isPhoneVertical;     // ✅ 修改：手机是否竖直（而非水平）
  final bool isStable;            // 是否稳定
  final double pitch;             // 俯仰角
  final double roll;              // 翻滚角
  final int landmarkCount;        // 检测到的关键点数量

  const DetectionMetrics({
    this.isHumanComplete = false,
    this.distanceRatio = 0.0,
    this.isPhoneVertical = false,  // ✅ 修改：默认值
    this.isStable = false,
    this.pitch = 0.0,
    this.roll = 0.0,
    this.landmarkCount = 0,
  });

  /// 是否可以自动拍照
  bool get canAutoCapture {
    return isHumanComplete &&
        distanceRatio >= 0.5 && distanceRatio <= 0.85 &&
        isPhoneVertical &&  // ✅ 修改：要求手机竖直
        isStable &&
        landmarkCount >= 25; // 至少检测到25个关键点
  }

  /// 获取整体状态文本
  String getStatusText() {
    if (!isHumanComplete) return '请确保全身在画面内';
    if (distanceRatio < 0.5) return '请后退一些';
    if (distanceRatio > 0.85) return '请靠近一些';
    if (!isPhoneVertical) return '请将手机竖直持握';  // ✅ 修改：提示竖直
    if (!isStable) return '请保持稳定';
    return '准备就绪，即将拍照';
  }

  /// 获取状态颜色
  Color getStatusColor() {
    if (canAutoCapture) return Colors.green;
    if (isHumanComplete && distanceRatio >= 0.5 && distanceRatio <= 0.85) {
      return Colors.orange;
    }
    return Colors.red;
  }
}
