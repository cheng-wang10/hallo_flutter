import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/camera_service.dart';
import '../services/pose_detection_service.dart';
import '../services/imu_service.dart';
import '../models/detection_metrics.dart';
import '../widgets/camera_preview_widget.dart';
import '../widgets/status_panel.dart';
import '../widgets/guidance_overlay.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final CameraService _cameraService = CameraService();
  final PoseDetectionService _poseService = PoseDetectionService();
  final IMUService _imuService = IMUService();
  
  // ✅ 新增：状态平滑器（防止抖动）
  final StateSmoother _smoother = StateSmoother();
  
  bool _isInitialized = false;
  DetectionMetrics _metrics = const DetectionMetrics();
  CaptureStatus _status = CaptureStatus.idle;
  String? _capturedImagePath;
  
  Timer? _autoCaptureTimer;
  int _countdownSeconds = 3;
  
  // ✅ 优化：持续稳定时间检测，从2秒改为4秒
  DateTime? _stableStartTime;  // 开始稳定的时间点
  static const Duration _requiredStableDuration = Duration(seconds: 4);  // 需要持续稳定4秒
  
  // ✅ 新增：UI刷新频率限制
  DateTime? _lastUiUpdateTime;
  static const Duration _uiUpdateInterval = Duration(milliseconds: 500);  // 每500ms最多更新一次UI

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  /// 初始化所有服务
  Future<void> _initializeServices() async {
    try {
      // 初始化相机
      await _cameraService.initialize();
      
      // ✅ 新增：启动姿态检测器（ML Kit）
      if (_cameraService.controller != null) {
        print('🚀 [PoseDetection] 启动姿态检测器...');
        _poseService.startDetection(_cameraService.controller!);
        print('✅ [PoseDetection] 姿态检测器已启动');
      } else {
        print('❌ [PoseDetection] 相机控制器为空，无法启动检测');
      }
      
      // 设置姿态检测回调
      _poseService.onMetricsUpdate = (metrics) {
        // ✅ 应用状态平滑
        final smoothedMetrics = DetectionMetrics(
          isHumanComplete: _smoother.smoothHumanCompleteness(metrics.isHumanComplete),
          distanceRatio: _smoother.smoothDistanceRatio(metrics.distanceRatio),
          isPhoneVertical: _metrics.isPhoneVertical,  // IMU会更新这个值
          isStable: _metrics.isStable,  // IMU会更新这个值
          pitch: _metrics.pitch,
          roll: _metrics.roll,
          landmarkCount: metrics.landmarkCount,
        );
        
        // ✅ UI刷新频率限制
        final now = DateTime.now();
        if (_lastUiUpdateTime == null || 
            now.difference(_lastUiUpdateTime!) >= _uiUpdateInterval) {
          setState(() {
            _metrics = smoothedMetrics;
            _checkAutoCapture();
            _lastUiUpdateTime = now;
          });
        } else {
          // 不更新UI，但更新内部数据
          _metrics = smoothedMetrics;
          _checkAutoCapture();
        }
      };

      _poseService.onError = (error) {
        print('❌ [PoseDetection] 错误: $error');
      };
      
      // 设置 IMU 回调
      _imuService.onIMUUpdate = (pitch, roll, isVertical, isStable) {
        // ✅ 应用平滑：防止竖直判断频繁切换
        final smoothedIsVertical = _smoother.smoothPhoneVertical(pitch, roll);
        
        // ✅ UI刷新频率限制
        final now = DateTime.now();
        if (_lastUiUpdateTime == null || 
            now.difference(_lastUiUpdateTime!) >= _uiUpdateInterval) {
          setState(() {
            _metrics = DetectionMetrics(
              isHumanComplete: _metrics.isHumanComplete,
              distanceRatio: _metrics.distanceRatio,
              isPhoneVertical: smoothedIsVertical,  // ✅ 使用平滑后的竖直状态
              isStable: isStable,
              pitch: pitch,
              roll: roll,
              landmarkCount: _metrics.landmarkCount,
            );
            _checkAutoCapture();
            _lastUiUpdateTime = now;
          });
        } else {
          // 不更新UI，但更新内部数据
          _metrics = DetectionMetrics(
            isHumanComplete: _metrics.isHumanComplete,
            distanceRatio: _metrics.distanceRatio,
            isPhoneVertical: smoothedIsVertical,
            isStable: isStable,
            pitch: pitch,
            roll: roll,
            landmarkCount: _metrics.landmarkCount,
          );
          _checkAutoCapture();
        }
      };

      // 开始 IMU 监听
      _imuService.startListening();
      
      setState(() {
        _isInitialized = true;
        _status = CaptureStatus.detecting;
      });
      
      print('✅ [Init] 所有服务初始化完成');
    } catch (e) {
      print('❌ [Init] 初始化失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('初始化失败: $e')),
      );
    }
  }

  /// 检查是否可以自动拍照
  void _checkAutoCapture() {
    final canCapture = _metrics.canAutoCapture;
    
    if (canCapture && _status == CaptureStatus.detecting) {
      // ✅ 新增：检查持续稳定时间
      if (_stableStartTime == null) {
        // 第一次满足条件，记录开始时间
        _stableStartTime = DateTime.now();
        print('✅ [AutoCapture] 条件满足，开始计时...');
      } else {
        // 检查是否已持续足够时间
        final stableDuration = DateTime.now().difference(_stableStartTime!);
        if (stableDuration >= _requiredStableDuration) {
          // ✅ 持续稳定4秒，可以进入准备状态
          print('✅ [AutoCapture] 持续稳定 ${stableDuration.inSeconds}秒，触发倒计时');
          print('   - 人体完整: ${_metrics.isHumanComplete}');
          print('   - 距离比例: ${_metrics.distanceRatio.toStringAsFixed(2)}');
          print('   - 手机竖直: ${_metrics.isPhoneVertical}');
          print('   - 身体稳定: ${_metrics.isStable}');
          print('   - 关键点数: ${_metrics.landmarkCount}');
          
          setState(() {
            _status = CaptureStatus.ready;
          });
          
          // 启动自动拍照倒计时
          _startAutoCaptureCountdown();
          return;  // 提前返回
        } else {
          // 还在等待中，显示剩余时间
          final remaining = (_requiredStableDuration - stableDuration).inSeconds;
          if (remaining % 2 == 0) {  // 每2秒打印一次，减少日志噪音
            print('⏳ [AutoCapture] 还需稳定 ${remaining}秒...');
          }
        }
      }
    } else {
      // 条件不满足，重置计时器
      if (_stableStartTime != null) {
        print('❌ [AutoCapture] 条件不满足，重置计时器');
        _stableStartTime = null;
      }
      
      _cancelAutoCapture();
      if (_status == CaptureStatus.ready) {
        setState(() {
          _status = CaptureStatus.detecting;
        });
      }
    }
  }

  /// 启动自动拍照倒计时
  void _startAutoCaptureCountdown() {
    _cancelAutoCapture();
    _countdownSeconds = 3;
    
    _autoCaptureTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        setState(() {
          _countdownSeconds--;
        });
      } else {
        timer.cancel();
        _performAutoCapture();
      }
    });
  }

  /// 取消自动拍照
  void _cancelAutoCapture() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
  }

  /// 执行自动拍照
  Future<void> _performAutoCapture() async {
    if (_status == CaptureStatus.capturing) return;
    
    setState(() {
      _status = CaptureStatus.capturing;
    });
    
    final imagePath = await _cameraService.takePhoto();
    
    if (imagePath != null) {
      setState(() {
        _capturedImagePath = imagePath;
        _status = CaptureStatus.completed;
      });
      
      // 显示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 拍照成功！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      setState(() {
        _status = CaptureStatus.detecting;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ 拍照失败，请重试'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 手动拍照
  Future<void> _manualCapture() async {
    await _performAutoCapture();
  }

  /// 重新开始
  void _restart() {
    setState(() {
      _capturedImagePath = null;
      _status = CaptureStatus.detecting;
      _metrics = const DetectionMetrics();
    });
    _cancelAutoCapture();
  }

  @override
  void dispose() {
    _cancelAutoCapture();
    _poseService.dispose();
    _imuService.dispose();
    _cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在初始化...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // 相机预览
          Positioned.fill(
            child: CameraPreviewWidget(
              controller: _cameraService.controller!,
            ),
          ),
          
          // 引导遮罩和站位框
          GuidanceOverlay(
            metrics: _metrics,
            status: _status,
            countdownSeconds: _countdownSeconds,
          ),
          
          // 状态面板
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: StatusPanel(metrics: _metrics),
          ),
          
          // 底部控制按钮
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 24,
            left: 0,
            right: 0,
            child: _buildControlButtons(),
          ),
          
          // 拍照完成后的预览
          if (_capturedImagePath != null)
            _buildCapturePreview(),
        ],
      ),
    );
  }

  /// 构建控制按钮
  Widget _buildControlButtons() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 手动拍照按钮
          FloatingActionButton(
            onPressed: _status == CaptureStatus.detecting || 
                      _status == CaptureStatus.ready
                ? _manualCapture
                : null,
            backgroundColor: _metrics.canAutoCapture 
                ? Colors.green 
                : Colors.white,
            child: Icon(
              Icons.camera_alt,
              color: _metrics.canAutoCapture 
                  ? Colors.white 
                  : Colors.black,
              size: 32,
            ),
          ),
          
          const SizedBox(width: 24),
          
          // 重新拍摄按钮（拍照后显示）
          if (_status == CaptureStatus.completed)
            FloatingActionButton.extended(
              onPressed: _restart,
              icon: const Icon(Icons.refresh),
              label: const Text('重新拍摄'),
              backgroundColor: Colors.blue,
            ),
        ],
      ),
    );
  }

  /// 构建拍照预览
  Widget _buildCapturePreview() {
    return Container(
      color: Colors.black.withOpacity(0.9),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.file(
              File(_capturedImagePath!),
              height: 400,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _restart,
              icon: const Icon(Icons.check),
              label: const Text('确认使用'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _restart,
              icon: const Icon(Icons.refresh),
              label: const Text('重新拍摄'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
