import 'package:flutter/material.dart';

class ShimmerText extends StatefulWidget {
  const ShimmerText({
    required this.text,
    required this.style,
    super.key,
  });

  final String text;
  final TextStyle style;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect bounds) {
            final double width = bounds.width <= 0 ? 1 : bounds.width;
            final double slide = width * 1.4 * _controller.value;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const <Color>[
                Color(0xFF8E8E8E),
                Color(0xFFF2F2F2),
                Color(0xFF8E8E8E),
              ],
              stops: const <double>[0.1, 0.5, 0.9],
              transform: _SlidingGradientTransform(translation: slide - width),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: Text(widget.text, style: widget.style),
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.translation});

  final double translation;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(translation, 0, 0);
  }
}
