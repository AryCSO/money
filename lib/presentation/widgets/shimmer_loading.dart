import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/app_colors.dart';

class ShimmerLoading extends StatelessWidget {
  const ShimmerLoading({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: baseColor ??
          (isDark ? AppColors.surfaceAlt : AppColors.lightSurfaceAlt),
      highlightColor: highlightColor ??
          (isDark
              ? AppColors.surface.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.8)),
      child: child,
    );
  }
}

class ShimmerContactList extends StatelessWidget {
  const ShimmerContactList({super.key, this.itemCount = 8});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (_, _) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              _ShimmerCircle(size: 48),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShimmerBox(width: 140, height: 14),
                    SizedBox(height: 8),
                    _ShimmerBox(width: 200, height: 11),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShimmerMessageList extends StatelessWidget {
  const ShimmerMessageList({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          children: List.generate(itemCount, (i) {
            final isRight = i % 3 != 0;
            final width = (i % 2 == 0) ? 220.0 : 180.0;
            return Align(
              alignment:
                  isRight ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _ShimmerBox(
                  width: width,
                  height: 48 + (i % 3) * 12.0,
                  borderRadius: 18,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class ShimmerSectionCard extends StatelessWidget {
  const ShimmerSectionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShimmerBox(width: 200, height: 16),
            SizedBox(height: 12),
            _ShimmerBox(width: double.infinity, height: 12),
            SizedBox(height: 8),
            _ShimmerBox(width: 160, height: 12),
          ],
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class _ShimmerCircle extends StatelessWidget {
  const _ShimmerCircle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }
}
