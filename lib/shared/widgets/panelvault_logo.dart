import 'package:flutter/material.dart';

class PanelVaultLogo extends StatelessWidget {
  final double size;
  final bool showName;

  const PanelVaultLogo({super.key, this.size = 44, this.showName = true});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.primary, colors.secondary],
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: CustomPaint(painter: _VaultMarkPainter(color: Colors.white)),
        ),
        if (showName) ...[
          const SizedBox(width: 12),
          const Text(
            "PanelVault",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ],
    );
  }
}

class _VaultMarkPainter extends CustomPainter {
  final Color color;

  const _VaultMarkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fill = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    final vault = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.21,
        size.height * 0.2,
        size.width * 0.58,
        size.height * 0.62,
      ),
      Radius.circular(size.width * 0.1),
    );

    canvas.drawRRect(vault, fill);
    canvas.drawRRect(vault, stroke);

    final bolt = Path()
      ..moveTo(size.width * 0.55, size.height * 0.28)
      ..lineTo(size.width * 0.38, size.height * 0.55)
      ..lineTo(size.width * 0.53, size.height * 0.55)
      ..lineTo(size.width * 0.45, size.height * 0.73)
      ..lineTo(size.width * 0.66, size.height * 0.46)
      ..lineTo(size.width * 0.51, size.height * 0.46)
      ..close();

    canvas.drawPath(
      bolt,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _VaultMarkPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
