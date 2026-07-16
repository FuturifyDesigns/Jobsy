import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config/colors.dart';
import '../utils/external_job_presentation.dart';

/// Crisp network image for Web Jobs — logos stay small, never stretched.
class ExternalJobImage extends StatelessWidget {
  final String imageUrl;
  final double? height;
  final double? width;
  final BoxFit fit;
  final bool isLogo;
  final Widget? placeholder;
  final Widget? errorWidget;

  static const _httpHeaders = {
    'User-Agent': 'Mozilla/5.0 (compatible; Jobsy/1.0; +https://jobsy.app)',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  };

  const ExternalJobImage({
    super.key,
    required this.imageUrl,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.isLogo = false,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final treatAsLogo = isLogo ||
        ExternalJobPresentation.isLikelyLogoOrThumbnail(imageUrl);

    final url = ExternalJobPresentation.enhanceImageUrl(
      imageUrl,
      forLogo: treatAsLogo,
    );

    // Logos: decode at native size — never upscale via memCacheWidth.
    int? memCacheWidth;
    if (!treatAsLogo) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final screenW = MediaQuery.sizeOf(context).width;
      final displayW = width != null && width!.isFinite ? width! : screenW;
      memCacheWidth = (displayW * dpr).round().clamp(400, 1200);
    }

    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: _httpHeaders,
      height: height,
      width: width,
      fit: treatAsLogo ? BoxFit.contain : fit,
      filterQuality: FilterQuality.high,
      memCacheWidth: memCacheWidth,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, __) =>
          placeholder ?? Container(color: Colors.black12),
      errorWidget: (_, __, ___) =>
          errorWidget ??
          const Icon(Icons.image_not_supported_outlined, color: Colors.white54),
    );
  }
}

/// Compact logo tile for list cards — fixed size, no stretch.
class ExternalJobLogoTile extends StatelessWidget {
  final Map<String, dynamic> job;
  final double size;

  const ExternalJobLogoTile({
    super.key,
    required this.job,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final logoUrl = ExternalJobPresentation.logoImageUrl(job);
    final company = ExternalJobPresentation.cleanText(job['company_name']?.toString() ?? '');
    final initial = ExternalJobPresentation.companyInitial(
      company.isNotEmpty ? company : null,
    );
    final inner = size * 0.72;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.2),
        border: Border.all(color: JobsyColors.borderLight.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.14),
      child: logoUrl != null
          ? ExternalJobImage(
              imageUrl: logoUrl,
              width: inner,
              height: inner,
              isLogo: true,
              placeholder: _initial(initial, inner),
              errorWidget: _initial(initial, inner),
            )
          : _initial(initial, inner),
    );
  }

  Widget _initial(String letter, double inner) {
    return Container(
      width: inner,
      height: inner,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: JobsyColors.workerPrimary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(inner * 0.2),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: inner * 0.48,
          fontWeight: FontWeight.w800,
          color: JobsyColors.workerDark,
        ),
      ),
    );
  }
}
