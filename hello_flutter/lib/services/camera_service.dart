import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;

  /// 初始化相机
  Future<void> initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('No cameras found');
      }

      // 选择后置摄像头（通常是第一个）
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      // ✅ 修复：配置正确的图像格式以支持 ML Kit
      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21      // Android 使用 NV21
            : ImageFormatGroup.bgra8888, // iOS 使用 BGRA8888
      );

      await _controller!.initialize();
      
      print('✅ [Camera] 相机初始化成功');
      print('   分辨率: ${_controller!.value.previewSize}');
      print('   图像格式: ${Platform.isAndroid ? "NV21" : "BGRA8888"}');
      
      _isInitialized = true;
    } catch (e) {
      print('❌ [Camera] 相机初始化失败: $e');
      rethrow;
    }
  }

  /// 获取相机控制器
  CameraController? get controller => _controller;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 拍照并保存到相册
  Future<String?> takePhoto() async {
    if (!_isInitialized || _controller == null) {
      return null;
    }

    try {
      final image = await _controller!.takePicture();
      
      // 保存到应用目录
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${directory.path}/capture_$timestamp.jpg';
      
      final file = File(image.path);
      await file.copy(filePath);
      
      return filePath;
    } catch (e) {
      print('Take photo error: $e');
      return null;
    }
  }

  /// 释放资源
  void dispose() {
    _controller?.dispose();
    _isInitialized = false;
  }
}
