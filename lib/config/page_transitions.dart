import 'package:flutter/material.dart';

// ── Custom Page Route Transitions ──

class JobsyPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final JobsyTransition transition;
  
  JobsyPageRoute({
    required this.page,
    this.transition = JobsyTransition.fadeSlide,
    RouteSettings? settings,
  }) : super(
    settings: settings,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Outgoing page slightly scales & fades out to add depth
      final outgoingFade = Tween<double>(begin: 1.0, end: 0.9).animate(
        CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic),
      );
      final outgoingScale = Tween<double>(begin: 1.0, end: 0.97).animate(
        CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic),
      );
      
      Widget wrapWithOutgoing(Widget inner) {
        return FadeTransition(
          opacity: outgoingFade,
          child: ScaleTransition(scale: outgoingScale, child: inner),
        );
      }
      
      switch (transition) {
        case JobsyTransition.fade:
          return FadeTransition(opacity: animation, child: wrapWithOutgoing(child));
        case JobsyTransition.slideRight:
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: wrapWithOutgoing(child),
          );
        case JobsyTransition.slideUp:
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.0, 1.0), end: Offset.zero)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: wrapWithOutgoing(child),
          );
        case JobsyTransition.scale:
          return ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: FadeTransition(opacity: animation, child: wrapWithOutgoing(child)),
          );
        case JobsyTransition.fadeSlide:
          // Cinematic: fade + slight upward slide + tiny scale bump on incoming
          final incomingSlide = Tween<Offset>(
            begin: const Offset(0.0, 0.06),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          );
          final incomingScale = Tween<double>(begin: 0.985, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          );
          return SlideTransition(
            position: incomingSlide,
            child: ScaleTransition(
              scale: incomingScale,
              child: FadeTransition(
                opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
                child: wrapWithOutgoing(child),
              ),
            ),
          );
      }
    },
  );
}

enum JobsyTransition { fade, slideRight, slideUp, scale, fadeSlide }

// ── Animated List Item (staggered entrance) ──

class AnimatedListItem extends StatelessWidget {
  final int index;
  final Widget child;
  final Duration delay;
  
  const AnimatedListItem({
    super.key,
    required this.index,
    required this.child,
    this.delay = const Duration(milliseconds: 50),
  });
  
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + (index * delay.inMilliseconds)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

// ── Press Scale Animation Button ──

class AnimatedPressButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final double scaleDown;
  
  const AnimatedPressButton({
    super.key,
    required this.child,
    this.onPressed,
    this.scaleDown = 0.96,
  });
  
  @override
  State<AnimatedPressButton> createState() => _AnimatedPressButtonState();
}

class _AnimatedPressButtonState extends State<AnimatedPressButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleDown)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onPressed != null ? (_) => _controller.forward() : null,
      onTapCancel: widget.onPressed != null ? () => _controller.reverse() : null,
      onTap: widget.onPressed != null
          ? () {
              _controller.reverse();
              widget.onPressed!();
            }
          : null,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}

// ── Shimmer Loading Effect ──

class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  
  const ShimmerLoading({
    super.key,
    this.width = double.infinity,
    this.height = 80,
    this.borderRadius = 12,
  });
  
  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
              end: Alignment(1.0 + 2.0 * _controller.value, 0),
              colors: const [
                Color(0xFF1A1A24),
                Color(0xFF2A2A36),
                Color(0xFF1A1A24),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Fade In Widget ──

class FadeIn extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  
  const FadeIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 600),
    this.delay = Duration.zero,
  });
  
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: duration + delay,
      curve: Curves.easeOut,
      builder: (context, value, child) {
        final adjustedValue = delay.inMilliseconds > 0
            ? ((value - delay.inMilliseconds / (duration + delay).inMilliseconds) /
                (1 - delay.inMilliseconds / (duration + delay).inMilliseconds))
                .clamp(0.0, 1.0)
            : value;
        return Opacity(
          opacity: adjustedValue,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - adjustedValue)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
