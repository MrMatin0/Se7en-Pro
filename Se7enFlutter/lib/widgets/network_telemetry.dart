import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/i18n/app_strings.dart';
import '../core/models/connection_method.dart';
import '../core/models/connection_state.dart';
import '../core/models/tunnel_status.dart';
import '../core/services/providers.dart';
import '../core/utils/formatters.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'glass_controls.dart';

/// Live throughput panel.
///
/// Samples once per second and repaints only when a sample actually changes the
/// series. While disconnected the sampler is cancelled outright, so a
/// disconnected app schedules no repeating work at all.
class NetworkTelemetryHub extends ConsumerStatefulWidget {
  const NetworkTelemetryHub({super.key});

  @override
  ConsumerState<NetworkTelemetryHub> createState() =>
      _NetworkTelemetryHubState();
}

class _NetworkTelemetryHubState extends ConsumerState<NetworkTelemetryHub> {
  static const int _historyLength = 30;

  int _prevDl = 0;
  int _prevUl = 0;
  double _dlRate = 0;
  double _ulRate = 0;
  double _sessionPeakRate = 0;
  DateTime _lastRateTick = DateTime.now();
  DateTime _lastActiveDlTime = DateTime.now();
  DateTime _lastActiveUlTime = DateTime.now();
  Timer? _rateTicker;

  /// Bumped whenever the series changes; the painter compares this instead of
  /// walking both lists.
  int _revision = 0;

  final List<double> _dlHistory = List.filled(_historyLength, 0.0);
  final List<double> _ulHistory = List.filled(_historyLength, 0.0);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final initial =
        ref.read(tunnelStatusProvider).valueOrNull ?? const TunnelStatus();
    _prevDl = initial.bytesReceived;
    _prevUl = initial.bytesSent;
    _lastRateTick = now;
    _lastActiveDlTime = now;
    _lastActiveUlTime = now;

    if (initial.state == ConnectionState.connected) _startSampler();
  }

  void _startSampler() {
    _rateTicker ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickDataRate(),
    );
  }

  void _stopSampler() {
    _rateTicker?.cancel();
    _rateTicker = null;
  }

  void _resetSeries() {
    _dlRate = 0;
    _ulRate = 0;
    _sessionPeakRate = 0;
    _dlHistory.fillRange(0, _dlHistory.length, 0.0);
    _ulHistory.fillRange(0, _ulHistory.length, 0.0);
    _revision++;
  }

  void _tickDataRate() {
    if (!mounted) return;
    final status =
        ref.read(tunnelStatusProvider).valueOrNull ?? const TunnelStatus();

    if (status.state != ConnectionState.connected) {
      _stopSampler();
      if (_dlRate != 0 || _ulRate != 0) setState(_resetSeries);
      return;
    }

    final now = DateTime.now();
    final curDl = status.bytesReceived;
    final curUl = status.bytesSent;
    final dt = now.difference(_lastRateTick).inMilliseconds / 1000.0;

    final bDown = status.downSpeed;
    final bUp = status.upSpeed;

    if (bDown > 0) {
      _dlRate = bDown;
      _lastActiveDlTime = now;
    } else if (dt >= 0.2) {
      final dlDelta = (curDl >= _prevDl) ? (curDl - _prevDl) : 0;
      if (dlDelta > 0) {
        final instDl = dlDelta / dt;
        _dlRate = (_dlRate <= 0) ? instDl : (_dlRate * 0.35 + instDl * 0.65);
        _lastActiveDlTime = now;
      } else if (now.difference(_lastActiveDlTime).inMilliseconds > 700) {
        _dlRate *= 0.50;
        if (_dlRate < 64) _dlRate = 0;
      }
    }

    if (bUp > 0) {
      _ulRate = bUp;
      _lastActiveUlTime = now;
    } else if (dt >= 0.2) {
      final ulDelta = (curUl >= _prevUl) ? (curUl - _prevUl) : 0;
      if (ulDelta > 0) {
        final instUl = ulDelta / dt;
        _ulRate = (_ulRate <= 0) ? instUl : (_ulRate * 0.35 + instUl * 0.65);
        _lastActiveUlTime = now;
      } else if (now.difference(_lastActiveUlTime).inMilliseconds > 700) {
        _ulRate *= 0.50;
        if (_ulRate < 64) _ulRate = 0;
      }
    }

    if (dt >= 0.2) {
      _prevDl = curDl;
      _prevUl = curUl;
      _lastRateTick = now;
    }

    if (_dlRate > _sessionPeakRate) _sessionPeakRate = _dlRate;
    if (_ulRate > _sessionPeakRate) _sessionPeakRate = _ulRate;

    final tailDl = _dlHistory.last;
    final tailUl = _ulHistory.last;
    final idle = _dlRate == 0 && _ulRate == 0 && tailDl == 0 && tailUl == 0;

    // A flat idle series would repaint an identical picture. Skip it.
    if (idle) return;

    setState(() {
      _dlHistory.removeAt(0);
      _dlHistory.add(_dlRate);
      _ulHistory.removeAt(0);
      _ulHistory.add(_ulRate);
      _revision++;
    });
  }

  @override
  void dispose() {
    _stopSampler();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<TunnelStatus>>(tunnelStatusProvider,
        (previous, next) {
      final oldStatus = previous?.valueOrNull;
      final newStatus = next.valueOrNull ?? const TunnelStatus();
      if (oldStatus?.state == newStatus.state) return;

      if (newStatus.state == ConnectionState.connected) {
        final now = DateTime.now();
        _prevDl = newStatus.bytesReceived;
        _prevUl = newStatus.bytesSent;
        _lastRateTick = now;
        _lastActiveDlTime = now;
        _lastActiveUlTime = now;
        _dlRate = newStatus.downSpeed;
        _ulRate = newStatus.upSpeed;
        _sessionPeakRate = _dlRate > _ulRate ? _dlRate : _ulRate;
        _dlHistory.fillRange(0, _dlHistory.length, 0.0);
        _ulHistory.fillRange(0, _ulHistory.length, 0.0);
        _revision++;
        _startSampler();
      } else {
        _stopSampler();
        setState(_resetSeries);
      }
    });

    final c = Theme.of(context).extension<AppColors>()!;
    final str = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final method = ConnectionMethodX.parse(settings.connectionMethod);
    final panelStatus = ref.watch(tunnelStatusProvider.select((s) {
      final v = s.valueOrNull;
      return (
        state: v?.state ?? ConnectionState.disconnected,
        httpProxyPort: v?.httpProxyPort ?? 0,
        socksProxyPort: v?.socksProxyPort ?? 0,
        currentRouteIp: v?.currentRouteIp ?? '',
        currentRouteSni: v?.currentRouteSni ?? '',
        bytesReceived: v?.bytesReceived ?? 0,
        bytesSent: v?.bytesSent ?? 0,
      );
    }));

    final isConnected = panelStatus.state == ConnectionState.connected;
    final http = panelStatus.httpProxyPort > 0
        ? '127.0.0.1:${panelStatus.httpProxyPort}'
        : '127.0.0.1:—';
    final socks = panelStatus.socksProxyPort > 0
        ? '127.0.0.1:${panelStatus.socksProxyPort}'
        : '127.0.0.1:—';

    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 20,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableH = constraints.maxHeight;
          final isShort = availableH < 340;
          final isCompact = constraints.maxWidth < 440 || isShort;
          final gap = availableH >= 520 ? 10.0 : 7.0;

          final content = <Widget>[
            _PanelHeader(isConnected: isConnected, str: str),
            SizedBox(height: gap),
            Row(
              children: [
                Expanded(
                  child: _SpeedGaugeCard(
                    title: str.download,
                    icon: Icons.arrow_downward_rounded,
                    accentColor: BrandColors.accentCyan,
                    speedRate: _dlRate,
                    totalBytes: panelStatus.bytesReceived,
                    isConnected: isConnected,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SpeedGaugeCard(
                    title: str.upload,
                    icon: Icons.arrow_upward_rounded,
                    accentColor: BrandColors.primary,
                    speedRate: _ulRate,
                    totalBytes: panelStatus.bytesSent,
                    isConnected: isConnected,
                  ),
                ),
              ],
            ),
            SizedBox(height: gap),
            if (!isShort)
              Expanded(child: _buildChart(c, isConnected))
            else
              SizedBox(height: 120, child: _buildChart(c, isConnected)),
            SizedBox(height: gap),
            Row(
              children: [
                Expanded(
                  child: _DiagnosticTile(
                    icon: Icons.cable_rounded,
                    iconColor: BrandColors.accentCyan,
                    label: isCompact ? 'SOCKS5' : 'SOCKS5 PROXY',
                    value: socks,
                    badgeText: isCompact
                        ? null
                        : (panelStatus.socksProxyPort > 0 ? 'PORT READY' : 'OFF'),
                    badgeColor: panelStatus.socksProxyPort > 0
                        ? BrandColors.emerald
                        : c.textMuted,
                    canCopy: panelStatus.socksProxyPort > 0,
                    isCompact: isCompact,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _DiagnosticTile(
                    icon: Icons.http_rounded,
                    iconColor: BrandColors.accentCyan,
                    label: isCompact ? 'HTTP' : 'HTTP PROXY',
                    value: http,
                    badgeText: isCompact
                        ? null
                        : (panelStatus.httpProxyPort > 0 ? 'PORT READY' : 'OFF'),
                    badgeColor: panelStatus.httpProxyPort > 0
                        ? BrandColors.emerald
                        : c.textMuted,
                    canCopy: panelStatus.httpProxyPort > 0,
                    isCompact: isCompact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: _DiagnosticTile(
                    icon: Icons.public_rounded,
                    iconColor: BrandColors.emerald,
                    label: isCompact ? 'GATEWAY' : 'ROUTE GATEWAY',
                    value: panelStatus.currentRouteIp.isNotEmpty
                        ? panelStatus.currentRouteIp
                        : (isConnected ? 'POP Mesh' : 'Mesh Standby'),
                    badgeText:
                        isCompact ? null : (isConnected ? 'CONNECTED' : 'STANDBY'),
                    badgeColor:
                        isConnected ? BrandColors.emerald : c.textMuted,
                    canCopy: panelStatus.currentRouteIp.isNotEmpty,
                    isCompact: isCompact,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _DiagnosticTile(
                    icon: Icons.security_rounded,
                    iconColor: BrandColors.primary,
                    label: isCompact ? 'CIPHER' : 'CIPHER & PROTOCOL',
                    value: panelStatus.currentRouteSni.isNotEmpty
                        ? panelStatus.currentRouteSni
                        : (isConnected ? method.displayName : 'Cipher Ready'),
                    badgeText:
                        isCompact ? null : (isConnected ? 'ENCRYPTED' : 'IDLE'),
                    badgeColor:
                        isConnected ? BrandColors.primary : c.textMuted,
                    canCopy: false,
                    isCompact: isCompact,
                  ),
                ),
              ],
            ),
            SizedBox(height: gap),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: c.input.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.donut_large_rounded,
                      size: 12, color: BrandColors.emerald),
                  const SizedBox(width: 7),
                  Text(
                    str.totalTraffic,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: c.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatBytes(
                        panelStatus.bytesReceived + panelStatus.bytesSent),
                    style: AppTheme.mono(BrandColors.emerald,
                        size: 11, weight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ];

          if (isShort) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: content,
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: content,
          );
        },
      ),
    );
  }

  Widget _buildChart(AppColors c, bool isConnected) {
    return Container(
      decoration: BoxDecoration(
        color: c.input.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: c.border.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected
                        ? BrandColors.emerald
                        : c.textMuted.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? 'THROUGHPUT · 30s' : 'THROUGHPUT · IDLE',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: isConnected ? c.textPrimary : c.textMuted,
                  ),
                ),
                const Spacer(),
                if (isConnected && _sessionPeakRate > 0)
                  Text(
                    'PEAK ${formatSpeed(_sessionPeakRate.toInt())}',
                    style: AppTheme.mono(BrandColors.accentCyan,
                        size: 8, weight: FontWeight.w700),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: _ThroughputPainter(
                  dlHistory: _dlHistory,
                  ulHistory: _ulHistory,
                  peakRate: _sessionPeakRate,
                  revision: _revision,
                  isConnected: isConnected,
                  downColor: BrandColors.accentCyan,
                  upColor: BrandColors.primary,
                  gridColor: c.border.withValues(alpha: 0.18),
                  mutedColor: c.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.isConnected, required this.str});

  final bool isConnected;
  final AppStrings str;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final tint = isConnected ? BrandColors.emerald : BrandColors.accentCyan;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tint.withValues(alpha: 0.25)),
          ),
          child: Icon(
            isConnected ? Icons.sensors_rounded : Icons.stream_rounded,
            size: 14,
            color: tint,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              str.networkTelemetry.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: c.textPrimary,
              ),
            ),
            Text(
              isConnected
                  ? 'Real-time speed + gateway'
                  : 'Idle — waiting for connection',
              style: TextStyle(fontSize: 8.5, color: c.textMuted),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: tint.withValues(alpha: 0.35)),
          ),
          child: Text(
            isConnected ? 'LIVE' : 'STANDBY',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: isConnected ? BrandColors.emerald : c.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeedGaugeCard extends StatelessWidget {
  const _SpeedGaugeCard({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.speedRate,
    required this.totalBytes,
    required this.isConnected,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final double speedRate;
  final int totalBytes;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final safeIntSpeed =
        (speedRate.isFinite && !speedRate.isNegative) ? speedRate.toInt() : 0;
    final hasSpeed = isConnected && safeIntSpeed > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3.5),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 12, color: accentColor),
              ),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: c.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            hasSpeed ? formatSpeed(safeIntSpeed) : '0.0 KB/s',
            style: AppTheme.mono(
              hasSpeed ? accentColor : c.textPrimary,
              size: 14.5,
              weight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(Icons.data_usage_rounded, size: 10, color: c.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Total: ${formatBytes(totalBytes)}',
                  style: AppTheme.mono(c.textSecondary,
                      size: 9.5, weight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagnosticTile extends ConsumerStatefulWidget {
  const _DiagnosticTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.badgeText,
    this.badgeColor,
    this.canCopy = false,
    this.isCompact = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? badgeText;
  final Color? badgeColor;
  final bool canCopy;
  final bool isCompact;

  @override
  ConsumerState<_DiagnosticTile> createState() => _DiagnosticTileState();
}

class _DiagnosticTileState extends ConsumerState<_DiagnosticTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final isAvailable = !widget.value.contains('—');
    final isCompact = widget.isCompact;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 7 : 9,
          vertical: isCompact ? 5 : 6.5,
        ),
        decoration: BoxDecoration(
          color: _isHovered
              ? c.cardElevated.withValues(alpha: 0.65)
              : c.input.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: _isHovered
                ? widget.iconColor.withValues(alpha: 0.45)
                : c.border.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isCompact ? 3.5 : 4),
              decoration: BoxDecoration(
                color: widget.iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(widget.icon,
                  size: isCompact ? 11 : 12, color: widget.iconColor),
            ),
            SizedBox(width: isCompact ? 5 : 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: isCompact ? 7.8 : 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: isCompact ? 0.3 : 0.4,
                            color: c.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCompact && widget.badgeColor != null) ...[
                        const SizedBox(width: 4),
                        Container(
                          width: 5.5,
                          height: 5.5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.badgeColor,
                          ),
                        ),
                      ] else if (widget.badgeText != null) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3.5, vertical: 1),
                          decoration: BoxDecoration(
                            color: (widget.badgeColor ?? widget.iconColor)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.badgeText!,
                            style: TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.w800,
                              color: widget.badgeColor ?? widget.iconColor,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: isCompact ? 1.5 : 2),
                  Text(
                    widget.value,
                    style: AppTheme.mono(
                      isAvailable ? c.textPrimary : c.textMuted,
                      size: isCompact ? 9.2 : 10,
                      weight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (widget.canCopy && isAvailable)
              Tooltip(
                message: 'Copy to clipboard',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: widget.value));
                      final msg = ref
                          .read(stringsProvider)
                          .copiedToClipboard(
                              '${widget.label}: ${widget.value}');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(msg),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.copy_rounded,
                        size: isCompact ? 10.5 : 11,
                        color: _isHovered ? widget.iconColor : c.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Plots the last 30 measured samples. Every value on screen comes from the
/// tunnel; there are no synthetic harmonics driving the shape.
class _ThroughputPainter extends CustomPainter {
  _ThroughputPainter({
    required this.dlHistory,
    required this.ulHistory,
    required this.peakRate,
    required this.revision,
    required this.isConnected,
    required this.downColor,
    required this.upColor,
    required this.gridColor,
    required this.mutedColor,
  });

  final List<double> dlHistory;
  final List<double> ulHistory;
  final double peakRate;
  final int revision;
  final bool isConnected;
  final Color downColor;
  final Color upColor;
  final Color gridColor;
  final Color mutedColor;

  static final Map<String, TextPainter> _labelCache = {};

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, h * 0.33), Offset(w, h * 0.33), gridPaint);
    canvas.drawLine(Offset(0, h * 0.66), Offset(w, h * 0.66), gridPaint);

    var maxRate = peakRate;
    for (final v in dlHistory) {
      if (v > maxRate) maxRate = v;
    }
    for (final v in ulHistory) {
      if (v > maxRate) maxRate = v;
    }

    if (!isConnected || maxRate <= 0) {
      _drawBaseline(canvas, size);
      return;
    }

    if (maxRate < 1024.0) maxRate = 1024.0;

    _drawAxisLabel(canvas, formatSpeed((maxRate * 0.66).toInt()), h * 0.33, w);
    _drawAxisLabel(canvas, formatSpeed((maxRate * 0.33).toInt()), h * 0.66, w);

    _paintCurve(canvas, size, ulHistory, maxRate, upColor, 1.5);
    _paintCurve(canvas, size, dlHistory, maxRate, downColor, 1.8);
  }

  void _drawBaseline(Canvas canvas, Size size) {
    final y = size.height - 4;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = mutedColor.withValues(alpha: 0.35)
        ..strokeWidth = 1.2,
    );
  }

  void _drawAxisLabel(Canvas canvas, String text, double y, double w) {
    var tp = _labelCache[text];
    if (tp == null) {
      if (_labelCache.length > 60) _labelCache.clear();
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: 8.0,
            fontWeight: FontWeight.w600,
            color: mutedColor.withValues(alpha: 0.60),
            fontFamily: 'JetBrains Mono',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _labelCache[text] = tp;
    }
    tp.paint(canvas, Offset(w - tp.width - 6, y - tp.height - 2));
  }

  void _paintCurve(
    Canvas canvas,
    Size size,
    List<double> data,
    double maxVal,
    Color color,
    double strokeWidth,
  ) {
    final w = size.width;
    final h = size.height;
    final n = data.length;
    if (n < 2) return;

    final usableH = h * 0.80;
    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final x = (i / (n - 1)) * w;
      final ratio = (data[i] / maxVal).clamp(0.0, 1.0);
      points.add(Offset(x, h - (ratio * usableH) - 4));
    }

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final cpx = (p0.dx + p1.dx) / 2;
      path.cubicTo(cpx, p0.dy, cpx, p1.dy, p1.dx, p1.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.20),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke,
    );

    canvas.drawCircle(points.last, 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ThroughputPainter old) =>
      old.revision != revision ||
      old.isConnected != isConnected ||
      old.downColor != downColor;
}
