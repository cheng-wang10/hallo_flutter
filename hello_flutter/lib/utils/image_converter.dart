import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

/// 相机图像转换工具
class ImageConverter {
  static final Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// 将 CameraImage 转换为 ML Kit 的 InputImage
  static InputImage? convertCameraImage(
    CameraImage cameraImage,
    CameraDescription camera,
    DeviceOrientation? deviceOrientation,
  ) {
    try {
      // 获取图像旋转角度
      final rotation = _getImageRotation(cameraImage, camera, deviceOrientation);
      if (rotation == null) return null;

      // 获取图像格式
      final format = InputImageFormatValue.fromRawValue(cameraImage.format.raw);
      if (format == null) return null;

      // 验证格式（Android: nv21, iOS: bgra8888）
      if (Platform.isAndroid && format != InputImageFormat.nv21) return null;
      if (Platform.isIOS && format != InputImageFormat.bgra8888) return null;

      // 确保只有一个平面
      if (cameraImage.planes.length != 1) return null;
      final plane = cameraImage.planes.first;

      // 创建 InputImage
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(
            cameraImage.width.toDouble(),
            cameraImage.height.toDouble(),
          ),
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    } catch (e) {
      print('Image conversion error: $e');
      return null;
    }
  }

  /// 获取图像旋转角度
  static InputImageRotation? _getImageRotation(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation? deviceOrientation,
  ) {
    final sensorOrientation = camera.sensorOrientation;
    
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      final rotationCompensation = _orientations[deviceOrientation];
      if (rotationCompensation == null) return null;

      int compensatedRotation;
      if (camera.lensDirection == CameraLensDirection.front) {
        // 前置摄像头
        compensatedRotation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        // 后置摄像头
        compensatedRotation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(compensatedRotation);
    }
    
    return rotation;
  }
}
