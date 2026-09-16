import 'dart:math' as math;

import 'package:flutter/material.dart' hide ConnectionState;

import '../core/models/connection_state.dart';

/// The primary connect control.
///
/// Only the transient `connecting` / `disconnecting` states animate. Every
/// steady state (`connected`, `disconnected`, `error`) paints exactly once and
/// then stays still, so an idle or long-running session costs zero frames.
class AuroraOrbButton extends StatefulWidget {
  const AuroraOrbButton({
    super.key,
    required this.state,
    required this.onTap,
    this.percent = 0,
    this.size = 210,
  });

  final ConnectionState state;
  final VoidCallback onTap;
  final int percent;
  final double size;

  @override
  State<AuroraOrbButton> createState() => _AuroraOrbButtonState();
}

class _AuroraOrbButtonState extends State<AuroraOrbButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;
  bool _hover = false;
  bool _pressed = false;

  bool get _isBusy =>
      widget.state == ConnectionState.connecting ||
      widget.state == ConnectionState.disconnecting;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _syncTicker();
  }

  /// A running ticker schedules a frame forever, so it is only allowed to exist
  /// while there is genuinely indeterminate progress to communicate.
  void _syncTicker() {
    if (_isBusy) {
      if (!_sweep.isAnimating) _sweep.repeat();
    } else if (_sweep.isAnimating) {
      _sweep.stop();
      _sweep.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant AuroraOrbButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncTicker();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  Color get _accent => switch (widget.state) {
        ConnectionState.connected => const Color(0xFF10B981),
        ConnectionState.connecting ||
        ConnectionState.disconnecting =>
          const Color(0xFFF59E0B),
        ConnectionState.error => const Color(0xFFEF4444),
        _ => const Color(0xFF8B5CF6),
      };

  Color get _accentDeep => switch (widget.state) {
        ConnectionState.connected => const Color(0xFF047857),
        ConnectionState.connecting ||
        ConnectionState.disconnecting =>
          const Color(0xFFB45309),
        ConnectionState.error => const Color(0xFFB91C1C),
        _ => const Color(0xFF6D28D9),
      };

  IconData get _icon => switch (widget.state) {
        ConnectionState.connected => Icons.shield_rounded,
        ConnectionState.connecting ||
        ConnectionState.disconnecting =>
          Icons.sync_rounded,
        ConnectionState.error => Icons.warning_rounded,
        _ => Icons.power_settings_new_rounded,
      };

  String get _label => switch (widget.state) {
        ConnectionState.connected => 'CONNECTED',
        ConnectionState.connecting => 'CONNECTING',
        ConnectionState.disconnecting => 'STOPPING',
        ConnectionState.error => 'RETRY',
        _ => 'CONNECT',
      };

  @override
  Widget build(BuildContext context) {
    final accent = _accent;

    // Built once per state change and handed to the painter as a child, so a
    // sweeping frame repaints the rings without rebuilding the core.
    final core = _OrbCore(
      size: widget.size * 0.60,
      accent: accent,
      accentDeep: _accentDeep,
      icon: _icon,
      label: _label,
      hover: _hover,
    );

    Widget rings = CustomPaint(
      painter: _OrbPainter(
        accent: accent,
        sweep: 0,
        busy: false,
        connected: widget.state == ConnectionState.connected,
        percent: 0,
        hover: _hover,
      ),
      child: Center(child: core),
    );

    if (_isBusy) {
      rings = AnimatedBuilder(
        animation: _sweep,
        child: Center(child: core),
        builder: (context, child) => CustomPaint(
          painter: _OrbPainter(
            accent: accent,
            sweep: _sweep.value,
            busy: true,
            connected: false,
            percent: widget.percent,
            hover: _hover,
          ),
          child: child,
        ),
      );
    }

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _pressed ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutQuart,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: rings,
            ),
          ),
        ),
      ),
    );
  }
}

/// Static centre of the orb. No animation, no `Opacity` layer, one shadow.
class _OrbCore extends StatelessWidget {
  const _OrbCore({
    required this.size,
    required this.accent,
    required this.accentDeep,
    required this.icon,
    required this.label,
    required this.hover,
  });

  final double size;
  final Color accent;
  final Color accentDeep;
  final IconData icon;
  final String label;
  final bool hover;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, accentDeep],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: hover ? 0.42 : 0.24),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: hover ? 0.40 : 0.26),
            blurRadius: hover ? 26 : 18,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: size * 0.34, color: Colors.white),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.accent,
    required this.sweep,
    required this.busy,
    required this.connected,
    required this.percent,
    required this.hover,
  });

  final Color accent;
  final double sweep;
  final bool busy;
  final bool connected;
  final int percent;
  final bool hover;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;

    // Halo, drawn straight onto the canvas. Previously an extra Container +
    // Opacity widget, which forced a saveLayer on every frame.
    final haloRect = Rect.fromCircle(center: center, radius: maxRadius);
    canvas.drawCircle(
      center,
      maxRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: hover ? 0.26 : 0.18),
            accent.withValues(alpha: 0.0),
          ],
          stops: const [0.42, 1.0],
        ).createShader(haloRect),
    );

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = accent.withValues(alpha: 0.14);

    canvas.drawCircle(center, maxRadius - 2, ringPaint);
    canvas.drawCircle(center, maxRadius - 14, ringPaint);

    final arcRadius = maxRadius - 8;
    final rect = Rect.fromCircle(center: center, radius: arcRadius);

    if (busy) {
      final angle = sweep * 2 * math.pi;
      canvas.drawArc(
        rect,
        angle,
        math.pi * 0.55,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3.0
          ..color = accent,
      );

      if (percent > 0) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: arcRadius - 7),
          -math.pi / 2,
          2 * math.pi * (percent / 100),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 2.5
            ..color = Colors.white.withValues(alpha: 0.85),
        );
      }
      return;
    }

    if (connected) {
      // A solid ring reads as "secured" without needing to move.
      canvas.drawCircle(
        center,
        arcRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = accent.withValues(alpha: 0.65),
      );
      return;
    }

    const segments = 6;
    const segmentSweep = (2 * math.pi) / segments;
    final notchPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..color = accent.withValues(alpha: 0.30);

    for (var i = 0; i < segments; i++) {
      canvas.drawArc(
        rect,
        i * segmentSweep,
        segmentSweep * 0.45,
        false,
        notchPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.sweep != sweep ||
      old.busy != busy ||
      old.connected != connected ||
      old.percent != percent ||
      old.hover != hover ||
      old.accent != accent;
}
