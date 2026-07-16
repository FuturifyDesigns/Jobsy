import 'package:flutter/material.dart';
import '../config/colors.dart';
import '../models/social_provider.dart';
import 'jobsy_pressable.dart';

/// Stacked Google sign-in button(s).
class SocialSignInButtons extends StatelessWidget {
  final void Function(SocialProvider provider) onProviderTap;
  final SocialProvider? loadingProvider;

  const SocialSignInButtons({
    super.key,
    required this.onProviderTap,
    this.loadingProvider,
  });

  @override
  Widget build(BuildContext context) {
    final providers = availableSocialProviders;
    if (providers.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (var i = 0; i < providers.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _SocialButton(
            provider: providers[i],
            isLoading: loadingProvider == providers[i],
            onPressed: loadingProvider != null
                ? null
                : () => onProviderTap(providers[i]),
          ),
        ],
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final SocialProvider provider;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _SocialButton({
    required this.provider,
    required this.onPressed,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final isGoogle = provider == SocialProvider.google;
    const radius = BorderRadius.all(Radius.circular(14));

    return JobsyPressable(
      onPressed: onPressed,
      borderRadius: radius,
      pressedOpacity: 0.9,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: provider.backgroundColor,
          borderRadius: radius,
          border: isGoogle
              ? Border.all(color: JobsyColors.borderLight.withOpacity(0.6))
              : null,
        ),
        child: isLoading
            ? Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: provider.foregroundColor,
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isGoogle)
                    Image.asset(
                      'assets/icons/google_g.png',
                      width: 22,
                      height: 22,
                      fit: BoxFit.contain,
                    )
                  else
                    Icon(provider.icon, size: 22, color: provider.foregroundColor),
                  const SizedBox(width: 12),
                  Text(
                    provider.buttonLabel,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: provider.foregroundColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
