import 'package:flutter/material.dart';
import '../core/theme.dart';

/// A drop-in replacement for inline `Image.network` thumbnails that adds:
///  - a loading placeholder (spinner) while the image downloads,
///  - a graceful error fallback (broken-image box) instead of a blank gap,
///  - memory downsampling via `cacheWidth` so large user uploads don't decode
///    at full resolution for a small thumbnail.
///
/// Flutter already keeps decoded network images in an in-memory cache for the
/// session, so repeated views are instant. Use full `Image.network` (no
/// downsample) for full-screen/zoomable views where max resolution matters.
class AppNetworkImage extends StatelessWidget {
  final String url;
  final double? height;
  final double? width;
  final BoxFit fit;

  /// Max decoded width in pixels. Large uploads are downsampled to this to cap
  /// memory use; 1080 keeps thumbnails crisp on any phone.
  final int cacheWidth;

  const AppNetworkImage({
    super.key,
    required this.url,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.cacheWidth = 1080,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      height: height,
      width: width,
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          height: height ?? 160,
          width: width,
          color: AppColors.cream,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (context, error, stack) => Container(
        height: height ?? 60,
        width: width,
        color: AppColors.birch,
        alignment: Alignment.center,
        child: Icon(Icons.broken_image_outlined, size: 22, color: AppColors.ink4),
      ),
    );
  }
}
