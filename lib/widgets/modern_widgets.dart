import 'package:flutter/material.dart';
import '../config/colors.dart';
import 'jobsy_pressable.dart';

// ── Glassmorphic Card ──

class JobsyCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;
  final double borderRadius;
  final Color? backgroundColor;
  final Border? border;
  
  const JobsyCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.borderRadius = 16,
    this.backgroundColor,
    this.border,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ?? JobsyColors.surfaceLight,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ?? Border.all(color: JobsyColors.border.withValues(alpha: 0.65), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── Gradient Button ──

class JobsyGradientButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final List<Color>? gradient;
  final IconData? icon;
  final bool isLoading;
  final double height;
  final double borderRadius;
  final double fontSize;
  
  const JobsyGradientButton({
    super.key,
    required this.text,
    this.onPressed,
    this.gradient,
    this.icon,
    this.isLoading = false,
    this.height = 56,
    this.borderRadius = 16,
    this.fontSize = 17,
  });
  
  @override
  Widget build(BuildContext context) {
    final colors = gradient ?? JobsyColors.employerGradient;
    final enabled = !isLoading && onPressed != null;
    final labelColor = JobsyColors.onRoleAccent(colors.first);

    return JobsyPressable(
      onPressed: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.22),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    color: labelColor,
                    strokeWidth: 2.5,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: labelColor, size: 22),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w700,
                        color: labelColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Modern Text Field ──

class JobsyTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Color accentColor;
  final int maxLines;
  final bool enabled;
  
  const JobsyTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.accentColor = JobsyColors.employerPrimary,
    this.maxLines = 1,
    this.enabled = true,
  });
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: JobsyColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          enabled: enabled,
          style: const TextStyle(
            fontSize: 16,
            color: JobsyColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          cursorColor: accentColor,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: JobsyColors.textSecondary, fontSize: 14),
            filled: true,
            fillColor: JobsyColors.inputBackground,
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: accentColor.withOpacity(0.8), size: 20)
                : null,
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: JobsyColors.inputBorder, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: JobsyColors.inputBorder, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accentColor, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: JobsyColors.error, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: JobsyColors.error, width: 1.5),
            ),
            errorStyle: const TextStyle(color: JobsyColors.error, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

// ── Status Badge ──

class JobsyStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  
  const JobsyStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });
  
  factory JobsyStatusBadge.open() => const JobsyStatusBadge(
    label: 'Open', color: JobsyColors.success, icon: Icons.circle,
  );
  
  factory JobsyStatusBadge.pending() => const JobsyStatusBadge(
    label: 'Pending', color: JobsyColors.warning, icon: Icons.schedule,
  );
  
  factory JobsyStatusBadge.accepted() => const JobsyStatusBadge(
    label: 'Accepted', color: JobsyColors.info, icon: Icons.check_circle,
  );
  
  factory JobsyStatusBadge.rejected() => const JobsyStatusBadge(
    label: 'Rejected', color: JobsyColors.error, icon: Icons.cancel,
  );
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

// ── Empty State Widget ──

class JobsyEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  
  const JobsyEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });
  
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: JobsyColors.surfaceLight,
                shape: BoxShape.circle,
                border: Border.all(color: JobsyColors.border, width: 0.5),
              ),
              child: Icon(icon, size: 36, color: JobsyColors.textTertiary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: JobsyColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 14, color: JobsyColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ── Modern Avatar ──

class JobsyAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double size;
  final bool showOnline;
  
  const JobsyAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.size = 48,
    this.showOnline = false,
  });
  
  @override
  Widget build(BuildContext context) {
    final initials = name.isNotEmpty
        ? name.split(' ').take(2).map((e) => e.isNotEmpty ? e[0] : '').join().toUpperCase()
        : '?';
    
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF374151), Color(0xFF1F2937)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: JobsyColors.border, width: 1),
          ),
          child: imageUrl != null && imageUrl!.isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(
                      child: Text(initials, style: TextStyle(
                        color: JobsyColors.textPrimary,
                        fontSize: size * 0.35,
                        fontWeight: FontWeight.w600,
                      )),
                    ),
                  ),
                )
              : Center(
                  child: Text(initials, style: TextStyle(
                    color: JobsyColors.textPrimary,
                    fontSize: size * 0.35,
                    fontWeight: FontWeight.w600,
                  )),
                ),
        ),
        if (showOnline)
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: size * 0.25,
              height: size * 0.25,
              decoration: BoxDecoration(
                color: JobsyColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: JobsyColors.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Section Header ──

class JobsySectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onAction;
  
  const JobsySectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.onAction,
  });
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: JobsyColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          if (actionText != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionText!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: JobsyColors.employerPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Coming Soon Placeholder ──
//
// A polished placeholder used for features that are not yet live
// (wallet, advanced employer tools, etc.). Matches the rich black
// welcome-screen aesthetic with a soft animated glow.

class JobsyComingSoon extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? note;
  final List<Color> accentGradient;
  
  const JobsyComingSoon({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.note,
    this.accentGradient = JobsyColors.metallicGradient,
  });
  
  @override
  State<JobsyComingSoon> createState() => _JobsyComingSoonState();
}

class _JobsyComingSoonState extends State<JobsyComingSoon>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulse;
  
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final accent = widget.accentGradient.first;
    
    return Container(
      color: JobsyColors.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated glowing icon
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  return Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          accent.withOpacity(0.25 * _pulse.value),
                          accent.withOpacity(0.08 * _pulse.value),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: JobsyColors.surfaceLight,
                          border: Border.all(
                            color: accent.withOpacity(0.35),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withOpacity(0.18 * _pulse.value),
                              blurRadius: 30,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          widget.icon,
                          size: 38,
                          color: accent,
                        ),
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 28),
              
              // Coming Soon pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: accent.withOpacity(0.3),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  'COMING SOON',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Title with metallic shader
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [
                    Color(0xFFE2E8F0),
                    Color(0xFF94A3B8),
                    Color(0xFFE2E8F0),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ).createShader(bounds),
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.6,
                    height: 1.1,
                  ),
                ),
              ),
              
              const SizedBox(height: 14),
              
              // Subtitle
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: JobsyColors.textSecondary,
                  height: 1.5,
                  letterSpacing: 0.1,
                ),
              ),
              
              if (widget.note != null) ...[
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: JobsyColors.surfaceLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: JobsyColors.border.withOpacity(0.5),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: accent.withOpacity(0.8),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.note!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: JobsyColors.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Glow Card (for rich dark-theme inner pages) ──
//
// Card with a subtle gradient glow on one edge, used to add
// visual depth to lists of items on a rich black background.

class JobsyGlowCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;
  final Color glowColor;
  final double glowIntensity;
  
  const JobsyGlowCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.glowColor = JobsyColors.workerPrimary,
    this.glowIntensity = 0.08,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: JobsyColors.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: glowColor.withValues(alpha: 0.22),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(18),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── Reusable Cinematic Dialog Header ──
//
// Used by every full-screen dialog / bottom sheet so they all share
// the same "My Jobs" style: tri-color gradient fading into dark,
// soft white glow orb in the top-right corner, icon pill with border,
// metallic silver shader on the title, muted subtitle underneath.
//
// Pass `accentColor` — the top of the gradient (employerPrimary, workerPrimary,
// success green, warning orange, etc). The gradient automatically darkens
// toward `#1A1A2E` so it blends with the rich black body.

class JobsyDialogHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final BorderRadius? borderRadius;

  const JobsyDialogHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    this.borderRadius,
  });

  Color _darken(Color c, double factor) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness * factor).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ??
        const BorderRadius.vertical(top: Radius.circular(24));
    final isLightAccent = JobsyColors.isLightAccent(accentColor);
    final gradientColors = isLightAccent
        ? const [
            Color(0xFF3F3F46),
            Color(0xFF27272A),
            Color(0xFF1A1A2E),
          ]
        : [
            accentColor,
            _darken(accentColor, 0.7),
            const Color(0xFF1A1A2E),
          ];
    final iconColor = isLightAccent ? JobsyColors.employerPrimary : Colors.white;
    final titleColor = Colors.white;
    final subtitleColor = Colors.white.withOpacity(0.75);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -30,
              right: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withOpacity(0.18),
                      Colors.white.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.25),
                        width: 0.7,
                      ),
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: isLightAccent
                                ? [
                                    JobsyColors.employerPrimary,
                                    JobsyColors.employerDark,
                                    JobsyColors.employerPrimary,
                                  ]
                                : const [
                                    Color(0xFFFFFFFF),
                                    Color(0xFFCBD5E1),
                                    Color(0xFFFFFFFF),
                                  ],
                            stops: const [0.0, 0.5, 1.0],
                          ).createShader(bounds),
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: titleColor,
                              letterSpacing: -0.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: subtitleColor,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
