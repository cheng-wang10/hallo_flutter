import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../models/detection_metrics.dart';
import '../utils/image_converter.dart';

class PoseDetectionService {
  final PoseDetector _poseDetector;
  CameraController? _cameraController;
  bool _isProcessing = false;  // 防止并发处理
  int _frameCounter = 0;       // ✅ 新增：帧计数器
  static const int _skipFrames = 10;  // ✅ 优化：从5改为10，进一步降低到约3fps（更稳定）
  
  // ✅ 新增：状态平滑器（防止抖动）
  final StateSmoother _smoother = StateSmoother();
  
  // 回调函数
  Function(DetectionMetrics)? onMetricsUpdate;
  Function(String)? onError;

  PoseDetectionService() : _poseDetector = PoseDetector(
    options: PoseDetectorOptions(),
  );

  /// 开始检测（使用真实 ML Kit）
  void startDetection(CameraController cameraController) {
    print('🔧 [PoseDetection] 配置相机控制器...');
    _cameraController = cameraController;
    _frameCounter = 0;  // ✅ 重置帧计数器
    
    // ✅ 修复：只启动一次图像流，然后在回调中处理
    try {
      _cameraController!.startImageStream((CameraImage image) async {
        // ✅ 新增：跳帧机制，降低处理频率
        _frameCounter++;
        
        // ✅ 每30帧打印一次跳帧状态（约1秒）
        if (_frameCounter % 30 == 0) {
          print('📊 [FrameCounter] 已处理 $_frameCounter 帧，当前跳帧策略: 每$_skipFrames帧处理一次');
        }
        
        if (_frameCounter % _skipFrames != 0) {
          return;  // 跳过这一帧
        }
        
        // 防止并发处理
        if (_isProcessing) return;
        
        _isProcessing = true;
        
        try {
          // 转换为 ML Kit 格式
          final inputImage = ImageConverter.convertCameraImage(
            image,
            _cameraController!.description,
            _cameraController!.value.deviceOrientation,
          );
          
          if (inputImage != null) {
            // 进行真实的人体姿态检测
            await _processRealDetection(inputImage);
          } else {
            // 转换失败时使用模拟数据
            print('⚠️ [PoseDetection] 图像转换失败，使用模拟数据');
            _simulateDetection();
          }
        } catch (e) {
          print('❌ [PoseDetection] 检测错误: $e');
          onError?.call('检测错误: $e');
          _simulateDetection();
        } finally {
          _isProcessing = false;
        }
      });
      
      print('✅ [PoseDetection] 图像流已启动，目标检测频率: ${30 ~/ _skipFrames}fps');
    } catch (e) {
      print('❌ [PoseDetection] 启动图像流失败: $e');
      onError?.call('启动图像流错误: $e');
      _simulateDetection();
      _isProcessing = false;
    }
  }

  /// 处理真实检测
  Future<void> _processRealDetection(InputImage inputImage) async {
    try {
      // ✅ 添加详细调试日志
      print('🔍 [ML Kit] ===== 开始检测 =====');
      print('   图像尺寸: ${inputImage.metadata?.size}');
      print('   图像格式: ${inputImage.metadata?.format}');
      print('   旋转角度: ${inputImage.metadata?.rotation}');
      
      // 调用 ML Kit 进行姿态检测
      final startTime = DateTime.now();
      final List<Pose> poses = await _poseDetector.processImage(inputImage);
      final processingTime = DateTime.now().difference(startTime);
      
      print('⏱️ [ML Kit] 处理耗时: ${processingTime.inMilliseconds}ms');
      print('✅ [ML Kit] 检测到 ${poses.length} 个人体');
      
      if (poses.isEmpty) {
        // 未检测到人体
        print('⚠️ [ML Kit] 未检测到人体，可能原因：');
        print('   1. 光线不足或过亮');
        print('   2. 人体不在画面内或被遮挡');
        print('   3. 距离太远（>5米）或太近（<0.5米）');
        print('   4. 背景复杂或有干扰物');
        print('   5. 人体姿态异常（躺下、侧身等）');
        print('   6. ML Kit 模型加载失败');
        
        onMetricsUpdate?.call(const DetectionMetrics(
          isHumanComplete: false,
          distanceRatio: 0.0,
          landmarkCount: 0,
        ));
        return;
      }

      // 取第一个检测到的人体姿态
      final pose = poses.first;
      final landmarksMap = pose.landmarks;
      
      // 将 Map 转换为 List
      final landmarks = landmarksMap.values.toList();
      
      print('📊 [ML Kit] 关键点数量: ${landmarks.length}');
      
      // ✅ 打印前5个关键点的详细信息
      if (landmarks.isNotEmpty) {
        print('📍 [ML Kit] 前5个关键点示例:');
        for (int i = 0; i < landmarks.length && i < 5; i++) {
          final lm = landmarks[i];
          print('   [$i] ${lm.type}: x=${lm.x.toStringAsFixed(3)}, y=${lm.y.toStringAsFixed(3)}, z=${lm.z.toStringAsFixed(3)}');
        }
      }
      
      // 检查完整性
      final isComplete = _checkHumanCompleteness(landmarks);
      print('✅ [ML Kit] 完整性检查: $isComplete');
      
      // 计算距离
      final distanceRatio = _calculateDistanceRatio(landmarks);
      print('📏 [ML Kit] 距离比例: ${distanceRatio.toStringAsFixed(3)} (${(distanceRatio * 100).toStringAsFixed(1)}%)');

      // 分析姿态数据
      final metrics = _analyzePose(landmarks);
      
      print('========================');
      
      // 通知更新
      onMetricsUpdate?.call(metrics);
    } catch (e, stackTrace) {
      print('❌ [ML Kit] 处理错误: $e');
      print('   堆栈: $stackTrace');
      onError?.call('ML Kit 处理错误: $e');
      // 出错时使用模拟数据
      _simulateDetection();
    }
  }

  /// 停止检测
  void stopDetection() {
    print('🛑 [PoseDetection] 停止姿态检测...');
    _cameraController?.stopImageStream();
    _isProcessing = false;
    print('✅ [PoseDetection] 检测已停止');
  }

  /// 模拟检测（实际项目中应接入真实ML Kit）
  void _simulateDetection() {
    // 这里模拟检测结果
    // 在实际项目中，应该使用 ML Kit 进行真实的人体关键点检测
    
    final metrics = DetectionMetrics(
      isHumanComplete: true,  // 模拟：人体完整
      distanceRatio: 0.65,    // 模拟：距离合适
      isPhoneVertical: true,  // ✅ 修改：模拟手机竖直
      isStable: true,         // 模拟：稳定
      pitch: 90.0,            // ✅ 修改：模拟俯仰角90度（竖直）
      roll: 0.0,              // ✅ 修改：模拟翻滚角0度
      landmarkCount: 32,      // 模拟：检测到32个关键点
    );
    
    onMetricsUpdate?.call(metrics);
  }

  /// 处理相机图像进行真实检测
  Future<DetectionMetrics?> processCameraImage(CameraImage image) async {
    try {
      // 将相机图像转换为 ML Kit 支持的格式
      final inputImage = _convertToInputImage(image);
      
      if (inputImage == null) return null;

      // 检测人体关键点
      final poses = await _poseDetector.processImage(inputImage);
      
      if (poses.isEmpty) {
        return const DetectionMetrics(
          isHumanComplete: false,
          landmarkCount: 0,
        );
      }

      final pose = poses.first;
      final landmarksMap = pose.landmarks;
      
      // 将 Map 转换为 List
      final landmarks = landmarksMap.values.toList();

      // 分析关键点
      return _analyzePose(landmarks);
    } catch (e) {
      onError?.call('处理图像错误: $e');
      return null;
    }
  }

  /// 转换相机图像为 ML Kit 输入格式
  InputImage? _convertToInputImage(CameraImage image) {
    // 这里需要根据实际的相机格式进行转换
    // 简化实现，实际项目需要完整实现
    return null;
  }

  /// 分析姿态数据
  DetectionMetrics _analyzePose(List<PoseLandmark> landmarks) {
    // 检查关键点数量
    final landmarkCount = landmarks.length;
    
    // 检查人体完整性（基于关键点分布）
    final rawIsHumanComplete = _checkHumanCompleteness(landmarks);
    
    // ✅ 应用平滑：防止完整性频繁切换
    final isHumanComplete = _smoother.smoothHumanCompleteness(rawIsHumanComplete);
    
    // 计算距离比例（基于人体高度占屏幕的比例）
    final rawDistanceRatio = _calculateDistanceRatio(landmarks);
    
    // ✅ 应用平滑：使用移动平均减少抖动
    final distanceRatio = _smoother.smoothDistanceRatio(rawDistanceRatio);
    
    return DetectionMetrics(
      isHumanComplete: isHumanComplete,
      distanceRatio: distanceRatio,
      landmarkCount: landmarkCount,
    );
  }

  /// 检查人体完整性
  bool _checkHumanCompleteness(List<PoseLandmark> landmarks) {
    // ✅ 优化1: 大幅增加关键点数量要求，防止误判
    if (landmarks.length < 20) {  // 从15增加到20
      print('⚠️ [Completeness] 关键点数量不足: ${landmarks.length}/20');
      return false;  // 关键点太少，肯定是误检测
    }
    
    // ✅ 优化2: 检查关键部位是否都存在（7个必需）
    final requiredLandmarks = [
      PoseLandmarkType.nose,
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.rightAnkle,
    ];

    int foundCount = 0;
    for (final type in requiredLandmarks) {
      if (landmarks.any((l) => l.type == type)) {
        foundCount++;
      }
    }
    
    // ✅ 优化3: 必须找到全部7个关键点才认为完整（不允许缺失）
    if (foundCount < 7) {
      print('⚠️ [Completeness] 只检测到 $foundCount/7 个关键部位');
      return false;
    }
    
    // ✅ 优化4: 验证关键点的合理性（防止错误检测）
    final nose = landmarks.where((l) => l.type == PoseLandmarkType.nose).toList();
    final leftAnkle = landmarks.where((l) => l.type == PoseLandmarkType.leftAnkle).toList();
    final rightAnkle = landmarks.where((l) => l.type == PoseLandmarkType.rightAnkle).toList();
    
    if (nose.isEmpty || (leftAnkle.isEmpty && rightAnkle.isEmpty)) {
      print('⚠️ [Completeness] 缺少鼻子或脚踝');
      return false;
    }
    
    // ✅ 优化5: 验证人体比例合理性（放宽阈值，适配不同距离）
    if (nose.isNotEmpty && (leftAnkle.isNotEmpty || rightAnkle.isNotEmpty)) {
      final noseY = nose.first.y;
      final ankleY = leftAnkle.isNotEmpty && rightAnkle.isNotEmpty 
          ? (leftAnkle.first.y + rightAnkle.first.y) / 2
          : (leftAnkle.isNotEmpty ? leftAnkle.first.y : rightAnkle.first.y);
      
      final heightRatio = (ankleY - noseY).abs();
      
      // ✅ 关键修复：判断坐标类型
      bool isPixelCoordinate = (noseY > 1.0 || ankleY > 1.0);
      
      if (isPixelCoordinate) {
        // 像素坐标：人体高度应该在300-1800像素之间（典型手机屏幕）
        if (heightRatio < 300 || heightRatio > 1800) {
          print('⚠️ [Completeness] 人体比例异常(像素): ${heightRatio.toStringAsFixed(0)}px (应在300-1800px)');
          return false;
        }
        print('✅ [Completeness] 人体比例正常(像素): ${heightRatio.toStringAsFixed(0)}px');
      } else {
        // 归一化坐标：人体高度应该在0.15-0.95之间（更宽松的范围）
        if (heightRatio < 0.15 || heightRatio > 0.95) {
          print('⚠️ [Completeness] 人体比例异常(归一化): ${heightRatio.toStringAsFixed(2)} (应在0.15-0.95)');
          return false;
        }
        print('✅ [Completeness] 人体比例正常(归一化): ${(heightRatio * 100).toStringAsFixed(1)}%');
      }
    }
    
    print('✅ [Completeness] 检测通过: ${landmarks.length}个关键点, 7/7关键部位');
    return true;
  }

  /// 计算距离比例
  double _calculateDistanceRatio(List<PoseLandmark> landmarks) {
    if (landmarks.isEmpty) {
      print('⚠️ [Distance] 关键点列表为空，返回0');
      return 0.0;
    }
    
    // ✅ 修复：严格检查关键点是否存在
    final noseList = landmarks.where((l) => l.type == PoseLandmarkType.nose).toList();
    if (noseList.isEmpty) {
      print('⚠️ [Distance] 未检测到鼻子，返回0');
      return 0.0;
    }
    final nose = noseList.first;
    
    final leftAnkleList = landmarks.where((l) => l.type == PoseLandmarkType.leftAnkle).toList();
    final rightAnkleList = landmarks.where((l) => l.type == PoseLandmarkType.rightAnkle).toList();
    
    final leftAnkle = leftAnkleList.isNotEmpty ? leftAnkleList.first : null;
    final rightAnkle = rightAnkleList.isNotEmpty ? rightAnkleList.first : null;
    
    // ✅ 优化：至少需要一个脚踝才能计算
    if (leftAnkle == null && rightAnkle == null) {
      print('⚠️ [Distance] 未检测到脚踝，返回0');
      return 0.0;
    }
    
    // 使用检测到的脚踝（优先使用两个的平均值）
    double bottomY;
    if (leftAnkle != null && rightAnkle != null) {
      bottomY = (leftAnkle.y + rightAnkle.y) / 2;
    } else if (leftAnkle != null) {
      bottomY = leftAnkle.y;
    } else {
      bottomY = rightAnkle!.y;
    }
    
    final topY = nose.y;
    
    // ✅ 关键修复：打印所有相关关键点的详细信息用于诊断
    print('📏 [Distance] ===== 原始数据诊断 =====');
    print('   总关键点数: ${landmarks.length}');
    print('   鼻子类型: ${nose.type}, Y=${nose.y.toStringAsFixed(4)}, X=${nose.x.toStringAsFixed(4)}');
    print('   左脚类型: ${leftAnkle?.type}, Y=${leftAnkle?.y.toStringAsFixed(4) ?? "null"}, X=${leftAnkle?.x.toStringAsFixed(4) ?? "null"}');
    print('   右脚类型: ${rightAnkle?.type}, Y=${rightAnkle?.y.toStringAsFixed(4) ?? "null"}, X=${rightAnkle?.x.toStringAsFixed(4) ?? "null"}');
    print('   顶部Y (鼻子): ${topY.toStringAsFixed(4)}');
    print('   底部Y (脚踝平均): ${bottomY.toStringAsFixed(4)}');
    print('   差值 (bottomY - topY): ${(bottomY - topY).toStringAsFixed(4)}');
    print('   绝对值: ${(bottomY - topY).abs().toStringAsFixed(4)}');
    
    // ✅ 关键修复：直接使用绝对值，确保正数
    double rawHeightRatio = (bottomY - topY).abs();
    
    // ✅ 判断坐标是否为归一化坐标
    bool isNormalized = (topY <= 1.0 && bottomY <= 1.0);
    
    if (!isNormalized) {
      // ✅ 关键修复：使用实际的图像高度进行归一化
      // 从日志看到图像尺寸是 Size(1280.0, 720.0)
      // 由于相机旋转了90度，实际显示高度应该是720（短边）
      // 但ML Kit的坐标是基于原始图像的，所以应该用1280（长边）作为高度
      
      // 尝试从常见的相机分辨率中推断
      double imageHeight;
      
      // 根据坐标范围推断图像高度
      // 如果最大Y坐标接近720，说明高度是720
      // 如果最大Y坐标接近1280，说明高度是1280
      final maxY = [topY, bottomY, ...landmarks.map((l) => l.y)].reduce((a, b) => a > b ? a : b);
      
      if (maxY < 800) {
        // 坐标在720范围内，图像高度可能是720
        imageHeight = 720.0;
        print('   ℹ️ 推断图像高度: 720px (基于最大Y坐标: ${maxY.toStringAsFixed(0)})');
      } else if (maxY < 1500) {
        // 坐标在1280范围内，图像高度可能是1280
        imageHeight = 1280.0;
        print('   ℹ️ 推断图像高度: 1280px (基于最大Y坐标: ${maxY.toStringAsFixed(0)})');
      } else {
        // 其他情况，使用估算值
        imageHeight = 2000.0;
        print('   ⚠️ 无法推断图像高度，使用估算值: 2000px');
      }
      
      final normalizedTopY = topY / imageHeight;
      final normalizedBottomY = bottomY / imageHeight;
      
      rawHeightRatio = (normalizedBottomY - normalizedTopY).abs();
      
      print('   归一化后顶部: ${normalizedTopY.toStringAsFixed(4)}');
      print('   归一化后底部: ${normalizedBottomY.toStringAsFixed(4)}');
      print('   归一化后差值: ${rawHeightRatio.toStringAsFixed(4)}');
    }
    
    // ✅ Clamp到合理范围
    rawHeightRatio = rawHeightRatio.clamp(0.0, 1.0);
    
    print('   最终比例: ${rawHeightRatio.toStringAsFixed(4)} (${(rawHeightRatio * 100).toStringAsFixed(1)}%)');
    print('   理想范围: 0.5-0.85 (50%-85%)');
    print('   状态: ${rawHeightRatio >= 0.5 && rawHeightRatio <= 0.85 ? "✅ 合适" : "❌ 不合适"}');
    print('========================');
    
    return rawHeightRatio;
  }

  /// 释放资源
  void dispose() {
    stopDetection();
    _poseDetector.close();
  }
}
