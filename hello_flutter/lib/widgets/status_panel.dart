import 'package:flutter/material.dart';
import '../models/detection_metrics.dart';

class StatusPanel extends StatelessWidget {
  final DetectionMetrics metrics;

  const StatusPanel({
    super.key,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '检测状态',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: metrics.getStatusColor(),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  metrics.canAutoCapture ? '✓ 就绪' : '检测中',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 4),
          
          // ✅ 新增：稳定进度提示
          if (metrics.isStable)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '🟢 稳定',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '🟡 晃动',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
              ),
            ),

          const SizedBox(height: 4),
          
          // 四项指标
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildIndicator(
                icon: Icons.person_outline,
                label: '完整性',
                value: metrics.isHumanComplete ? '完整' : '不完整',
                isOk: metrics.isHumanComplete,
              ),
              _buildIndicator(
                icon: Icons.straighten,
                label: '距离',
                value: '${(metrics.distanceRatio * 100).toInt()}%',
                isOk: metrics.distanceRatio >= 0.5 && 
                      metrics.distanceRatio <= 0.85,
              ),
              _buildIndicator(
                icon: Icons.screen_rotation,
                label: '姿态',
                // ✅ 修改：显示竖直状态
                value: metrics.isPhoneVertical ? '竖直' : '倾斜',
                isOk: metrics.isPhoneVertical,
              ),
              _buildIndicator(
                icon: Icons.stay_current_portrait,
                label: '稳定',
                value: metrics.isStable ? '稳定' : '晃动',
                isOk: metrics.isStable,
              ),
            ],
          ),
          
          // 详细数据
          if (metrics.pitch != 0 || metrics.roll != 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text(
                    '俯仰: ${metrics.pitch.toStringAsFixed(1)}°',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '翻滚: ${metrics.roll.toStringAsFixed(1)}°',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '关键点: ${metrics.landmarkCount}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 构建单个指标
  Widget _buildIndicator({
    required IconData icon,
    required String label,
    required String value,
    required bool isOk,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isOk 
            ? Colors.green.withOpacity(0.3) 
            : Colors.red.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isOk ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isOk ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: isOk ? Colors.green : Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
