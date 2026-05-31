import 'package:flutter/material.dart';
import '../models/detection_metrics.dart';

class GuidanceOverlay extends StatelessWidget {
  final DetectionMetrics metrics;
  final CaptureStatus status;
  final int countdownSeconds;

  const GuidanceOverlay({
    super.key,
    required this.metrics,
    required this.status,
    required this.countdownSeconds,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: GuidancePainter(
        metrics: metrics,
        status: status,
        countdownSeconds: countdownSeconds,
      ),
      child: Container(),
    );
  }
}

class GuidancePainter extends CustomPainter {
  final DetectionMetrics metrics;
  final CaptureStatus status;
  final int countdownSeconds;

  GuidancePainter({
    required this.metrics,
    required this.status,
    required this.countdownSeconds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // 计算人体站位框（屏幕中央80%区域）
    final framePadding = size.width * 0.1;
    final frameRect = Rect.fromLTWH(
      framePadding,
      size.height * 0.15,
      size.width - framePadding * 2,
      size.height * 0.7,
    );

    // 根据状态选择颜色
    Color frameColor;
    if (metrics.canAutoCapture) {
      frameColor = Colors.green;
    } else if (metrics.isHumanComplete && 
               metrics.distanceRatio >= 0.5 && 
               metrics.distanceRatio <= 0.85) {
      frameColor = Colors.orange;
    } else {
      frameColor = Colors.red;
    }

    // ✅ 修复：使用 Path 创建带洞的遮罩（更可靠的方法）
    final maskPath = Path()
      // 添加外矩形（整个屏幕）
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      // 添加内矩形（站位框），形成空洞
      ..addRect(frameRect);
    
    // 使用 EvenOdd 填充规则，内矩形区域会被挖空
    final maskPaint = Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.srcOver;
    
    canvas.drawPath(maskPath, maskPaint);

    // 绘制站位框
    paint.color = frameColor;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 4;
    
    // 绘制圆角矩形框
    final roundedRect = RRect.fromRectAndRadius(
      frameRect,
      const Radius.circular(20),
    );
    canvas.drawRRect(roundedRect, paint);

    // 绘制四个角的标记
    _drawCornerMarkers(canvas, frameRect, frameColor);

    // 绘制中心十字线（辅助对齐）
    _drawCenterCross(canvas, frameRect, frameColor.withOpacity(0.5));

    // 绘制文字提示
    _drawTextHints(canvas, size, frameRect, frameColor);

    // 如果准备就绪，显示倒计时
    if (status == CaptureStatus.ready || status == CaptureStatus.capturing) {
      _drawCountdown(canvas, size, frameColor);
    }
  }

  /// 绘制四个角的标记
  void _drawCornerMarkers(Canvas canvas, Rect frame, Color color) {
    final markerLength = 30.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    // 左上角
    canvas.drawLine(
      Offset(frame.left, frame.top + markerLength),
      Offset(frame.left, frame.top),
      paint,
    );
    canvas.drawLine(
      Offset(frame.left, frame.top),
      Offset(frame.left + markerLength, frame.top),
      paint,
    );

    // 右上角
    canvas.drawLine(
      Offset(frame.right - markerLength, frame.top),
      Offset(frame.right, frame.top),
      paint,
    );
    canvas.drawLine(
      Offset(frame.right, frame.top),
      Offset(frame.right, frame.top + markerLength),
      paint,
    );

    // 左下角
    canvas.drawLine(
      Offset(frame.left, frame.bottom - markerLength),
      Offset(frame.left, frame.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(frame.left, frame.bottom),
      Offset(frame.left + markerLength, frame.bottom),
      paint,
    );

    // 右下角
    canvas.drawLine(
      Offset(frame.right - markerLength, frame.bottom),
      Offset(frame.right, frame.bottom),
      paint,
    );
    canvas.drawLine(
      Offset(frame.right, frame.bottom - markerLength),
      Offset(frame.right, frame.bottom),
      paint,
    );
  }

  /// 绘制中心十字线
  void _drawCenterCross(Canvas canvas, Rect frame, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final center = frame.center;
    final crossSize = 20.0;

    // 横线
    canvas.drawLine(
      Offset(center.dx - crossSize, center.dy),
      Offset(center.dx + crossSize, center.dy),
      paint,
    );

    // 竖线
    canvas.drawLine(
      Offset(center.dx, center.dy - crossSize),
      Offset(center.dx, center.dy + crossSize),
      paint,
    );
  }

  /// 绘制文字提示
  void _drawTextHints(Canvas canvas, Size size, Rect frame, Color color) {
    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    // 顶部提示
    String topText;
    if (!metrics.isHumanComplete) {
      topText = '请将全身放入框内';
    } else if (metrics.distanceRatio < 0.5) {
      topText = '请后退一些';
    } else if (metrics.distanceRatio > 0.85) {
      topText = '请靠近一些';
    } else if (!metrics.isPhoneVertical) {  // ✅ 修改：检查竖直状态
      topText = '请将手机竖直持握';
    } else if (!metrics.isStable) {
      topText = '请保持稳定';
    } else {
      topText = '保持姿势，即将拍照';
    }

    textPainter.text = TextSpan(
      text: topText,
      style: TextStyle(
        color: color,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            color: Colors.black,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        frame.top - 50,
      ),
    );

    // 底部提示
    final bottomText = TextSpan(
      text: '双脚分开与肩同宽，双手自然下垂',
      style: TextStyle(
        color: Colors.white.withOpacity(0.8),
        fontSize: 14,
        shadows: [
          Shadow(
            color: Colors.black,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
    textPainter.text = bottomText;
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        frame.bottom + 20,
      ),
    );
  }

  /// 绘制倒计时
  void _drawCountdown(Canvas canvas, Size size, Color color) {
    // 半透明背景
    final bgPaint = Paint()
      ..color = Colors.black.withOpacity(0.7);
    canvas.drawRect(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: 150,
        height: 150,
      ),
      bgPaint,
    );

    // 倒计时数字
    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    
    textPainter.text = TextSpan(
      text: '$countdownSeconds',
      style: TextStyle(
        color: color,
        fontSize: 80,
        fontWeight: FontWeight.bold,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant GuidancePainter oldDelegate) {
    return oldDelegate.metrics != metrics ||
           oldDelegate.status != status ||
           oldDelegate.countdownSeconds != countdownSeconds;
  }
}
