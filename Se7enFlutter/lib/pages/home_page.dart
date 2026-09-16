import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:country_flags/country_flags.dart';

import '../core/data/region_catalog.dart';
import '../core/i18n/app_strings.dart';
import '../core/models/connection_method.dart';
import '../core/models/connection_state.dart';
import '../core/models/tun_health.dart';
import '../core/models/tunnel_status.dart';
import '../core/services/providers.dart';
import '../core/utils/formatters.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_elevation_dialog.dart';
import '../widgets/aurora_orb_button.dart';
import '../widgets/glass_controls.dart';
import '../widgets/modern_region_picker.dart';
import '../widgets/network_telemetry.dart';
import '../widgets/v2ray_missing_config_dialog.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  void _handleToggle(
    BuildContext context,
    ConnectionMethod method,
    dynamic settings,
    ConnectionController controller,
    ConnectionState state,
  ) {
    if (state == ConnectionState.connected ||
        state == ConnectionState.connecting) {
      controller.toggle();
      return;
    }

    if (method.usesV2Ray) {
      final configs = settings.v2rayConfigs as List<dynamic>;
      final hasConfigs = configs.isNotEmpty;
      final hasActiveConfig =
          hasConfigs && configs.any((c) => c.isActive == true);
      if (!hasConfigs || !hasActiveConfig) {
        V2RayMissingConfigDialog.show(
          context,
          hasConfigs: hasConfigs,
          method: method,
        );
        return;
      }
    }

    controller.toggle();
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(connectionControllerProvider);

    final method = ConnectionMethodX.parse(settings.connectionMethod);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 6,
            child: _HeroConnectionStage(
              state: connectionState,
              onToggle: () => _handleToggle(
                  context, method, settings, controller, connectionState),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _EngineMethodCard(
                  method: method,
                  state: connectionState,
                  onMethodChanged: (m) => controller.setMethod(m),
                ),
                const SizedBox(height: 8),
                if (method.supportsRegionPicker) ...[
                  const SizedBox(height: 8),
                  _EgressRegionCard(
                    method: method,
                    onRegionPicked: (code) =>
                        controller.setEgressRegion(code, method: method),
                  ),
                ],
                const SizedBox(height: 8),
                const Expanded(
                  child: NetworkTelemetryHub(
                    key: ValueKey('network_telemetry_hub'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroUptimeBadge extends ConsumerStatefulWidget {
  const _HeroUptimeBadge();

  @override
  ConsumerState<_HeroUptimeBadge> createState() => _HeroUptimeBadgeState();
}

class _HeroUptimeBadgeState extends ConsumerState<_HeroUptimeBadge> {
  Timer? _timer;
  Duration _uptime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final start = ref.read(connectionStartTimeProvider);
    if (!mounted) return;
    final next =
        start != null ? DateTime.now().difference(start) : Duration.zero;
    // Only rebuild when the rendered second actually changes.
    if (next.inSeconds == _uptime.inSeconds) return;
    setState(() => _uptime = next);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: BrandColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BrandColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 13, color: BrandColors.success),
          const SizedBox(width: 5),
          Text(
            formatUptime(_uptime),
            style: AppTheme.mono(BrandColors.success,
                size: 12, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _HeroConnectionStage extends ConsumerWidget {
  const _HeroConnectionStage({
    required this.state,
    required this.onToggle,
  });

  final ConnectionState state;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<AppColors>()!;
    final str = ref.watch(stringsProvider);
    final isConnected = state == ConnectionState.connected;
    final isConnecting = state == ConnectionState.connecting ||
        state == ConnectionState.disconnecting;

    final progress = isConnecting
        ? ref.watch(tunnelStatusProvider.select((s) => (
              percent: s.valueOrNull?.connectProgressPercent ?? 0,
              text: s.valueOrNull?.connectProgressText ?? '',
            )))
        : const (percent: 0, text: '');

    final auraColor = switch (state) {
      ConnectionState.connected => BrandColors.success,
      ConnectionState.connecting ||
      ConnectionState.disconnecting =>
        BrandColors.warning,
      ConnectionState.error => BrandColors.danger,
      _ => BrandColors.violet,
    };

    final statusText = switch (state) {
      ConnectionState.connected => str.statusConnected,
      ConnectionState.connecting ||
      ConnectionState.disconnecting =>
        str.statusConnecting,
      ConnectionState.error => str.statusError,
      _ => str.statusDisconnected,
    };

    return RepaintBoundary(
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        borderRadius: 20,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: auraColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: auraColor,
                      ),
                    ),
                  ],
                ),
                if (isConnected)
                  const _HeroUptimeBadge()
                else
                  Text(
                    'SE7EN CORE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: c.textMuted,
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Center(
              child: AuroraOrbButton(
                state: state,
                percent: progress.percent,
                onTap: onToggle,
                size: 190,
              ),
            ),
            const SizedBox(height: 16),
            if (isConnecting)
              Text(
                (progress.text.isNotEmpty &&
                        !progress.text
                            .trim()
                            .toLowerCase()
                            .startsWith('connected') &&
                        progress.text.trim().toLowerCase() != 'connected')
                    ? progress.text
                    : str.subtextConnecting,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.warning,
                ),
              )
            else if (isConnected)
              Text(
                str.subtextConnected,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.success,
                ),
              )
            else if (state == ConnectionState.error)
              Text(
                str.subtextError,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: BrandColors.danger,
                ),
              )
            else
              Text(
                str.subtextDisconnected,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: c.textMuted,
                ),
              ),
            const Spacer(),
            const _HeroRoutingModes(),
          ],
        ),
      ),
    );
  }
}

class _EngineMethodCard extends ConsumerWidget {
  const _EngineMethodCard({
    required this.method,
    required this.state,
    required this.onMethodChanged,
  });

  final ConnectionMethod method;
  final ConnectionState state;
  final ValueChanged<ConnectionMethod> onMethodChanged;

  IconData _iconFor(ConnectionMethod m) {
    if (m == ConnectionMethod.psiphon ||
        m == ConnectionMethod.psiphonOverWarp ||
        m == ConnectionMethod.psiphonOverV2Ray) {
      return Icons.vpn_lock_rounded;
    }
    if (m.isShard) {
      return Icons.hub_rounded;
    }
    return m.isAether ? Icons.bolt_rounded : Icons.shield_moon_rounded;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<AppColors>()!;
    final str = ref.watch(stringsProvider);

    return GlassCard(
      padding: const EdgeInsets.all(12),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: BrandColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.alt_route_rounded,
                    size: 15, color: BrandColors.primary),
              ),
              const SizedBox(width: 8),
              Text(
                str.connectionProtocol,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: c.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MethodPopupButton(
            method: method,
            isBusy: state.isBusy,
            onMethodChanged: onMethodChanged,
            iconFor: _iconFor,
          ),
          const SizedBox(height: 7),
          _ProtocolSettingsButton(method: method),
        ],
      ),
    );
  }
}

class _ProtocolSettingsButton extends ConsumerStatefulWidget {
  const _ProtocolSettingsButton({required this.method});
  final ConnectionMethod method;

  @override
  ConsumerState<_ProtocolSettingsButton> createState() =>
      _ProtocolSettingsButtonState();
}

class _ProtocolSettingsButtonState
    extends ConsumerState<_ProtocolSettingsButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;

    final (targetTab, label, subMode) = switch (widget.method) {
      ConnectionMethod.psiphon =>
        (SettingsTab.psiphon, 'Configure Psiphon Settings', null),
      ConnectionMethod.masque =>
        (SettingsTab.aether, 'Configure MASQUE Settings', 'masque'),
      ConnectionMethod.wireguard =>
        (SettingsTab.aether, 'Configure WireGuard Settings', 'wireguard'),
      ConnectionMethod.warpOnWarp =>
        (SettingsTab.aether, 'Configure Double WARP Settings', 'warp'),
      ConnectionMethod.masqueOnMasque => (
          SettingsTab.aether,
          'Configure Masque on Masque Settings',
          'masque_on_masque'
        ),
      ConnectionMethod.tor =>
        (SettingsTab.tor, 'Configure Tor Circuit Settings', null),
      ConnectionMethod.psiphonOverWarp => (
          SettingsTab.chained,
          'Configure Psiphon over WARP Settings',
          'psiphon_warp'
        ),
      ConnectionMethod.torOverWarp => (
          SettingsTab.chained,
          'Configure Tor over WARP Settings',
          'tor_warp'
        ),
      ConnectionMethod.psiphonOverV2Ray => (
          SettingsTab.chained,
          'Configure Psiphon over V2Ray Settings',
          'psiphon_v2ray'
        ),
      ConnectionMethod.torOverV2Ray => (
          SettingsTab.chained,
          'Configure Tor over V2Ray Settings',
          'tor_v2ray'
        ),
      ConnectionMethod.shard =>
        (SettingsTab.shard, 'Configure SHARD Settings', null),
    };

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          if (targetTab == SettingsTab.chained && subMode != null) {
            ref
                .read(settingsProvider.notifier)
                .update((s) => s.chainedSubMode = subMode);
          } else if (targetTab == SettingsTab.aether && subMode != null) {
            ref
                .read(settingsProvider.notifier)
                .update((s) => s.aetherProtocol = subMode);
          }
          ref.read(currentSettingsTabProvider.notifier).state = targetTab;
          ref.read(currentNavIndexProvider.notifier).state = 3;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
          decoration: BoxDecoration(
            color: _hovered
                ? BrandColors.primary.withValues(alpha: 0.12)
                : c.input.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered
                  ? BrandColors.primary.withValues(alpha: 0.5)
                  : c.border.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 13.5,
                color: _hovered ? BrandColors.primary : c.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _hovered ? BrandColors.primary : c.textSecondary,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 12.5,
                color: _hovered ? BrandColors.primary : c.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroRoutingModes extends ConsumerWidget {
  const _HeroRoutingModes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<AppColors>()!;
    final str = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final (isAdmin, tunStatusText, tunActive, tunLastError) = ref.watch(
      tunnelStatusProvider.select((s) {
        final val = s.valueOrNull;
        return (
          val?.isAdmin ?? false,
          val?.tunStatusText ?? 'Off',
          val?.tunActive ?? false,
          val?.tunLastError ?? '',
        );
      }),
    );
    final tun = TunHealth.of(
      TunnelStatus(
        isAdmin: isAdmin,
        tunStatusText: tunStatusText,
        tunActive: tunActive,
        tunLastError: tunLastError,
      ),
      settings.systemWideTunneling,
      'TUN — all system traffic',
    );
    Color tunColor;
    if (tun.failed) {
      tunColor = BrandColors.danger;
    } else if (tun.active) {
      tunColor = BrandColors.emerald;
    } else if (tun.wanted && tun.busy) {
      tunColor = BrandColors.warning;
    } else {
      tunColor = c.textMuted;
    }
    final isProxyActive = settings.setSystemProxy;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.input.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          _RoutingToggleRow(
            icon: Icons.shield_rounded,
            iconColor: tunColor,
            title: str.tunMode,
            subtitle: tun.detail,
            subtitleTooltip: tun.errorTooltip,
            value: tun.wanted,
            trailingBadge: !isAdmin
                ? _RoutingBadge(
                    label: str.adminReq,
                    icon: Icons.lock_outline_rounded,
                    color: BrandColors.warning)
                : tun.failed
                    ? _RoutingBadge(
                        label: str.failed,
                        icon: Icons.error_outline_rounded,
                        color: BrandColors.danger)
                    : tun.wanted && tun.busy
                        ? _RoutingBadge(
                            label: str.starting,
                            icon: Icons.sync_rounded,
                            color: BrandColors.warning)
                        : null,
            onChanged: (v) {
              if (!isAdmin && v) {
                showDialog(
                  context: context,
                  barrierDismissible: true,
                  builder: (ctx) => AdminElevationDialog(
                    onConfirm: () => ref
                        .read(settingsProvider.notifier)
                        .update((s) => s.systemWideTunneling = true),
                  ),
                );
              } else {
                ref
                    .read(settingsProvider.notifier)
                    .update((s) => s.systemWideTunneling = v);
              }
            },
          ),
          Divider(height: 10, color: c.border.withValues(alpha: 0.35)),
          _RoutingToggleRow(
            icon: Icons.lan_rounded,
            iconColor: isProxyActive ? BrandColors.accentCyan : c.textMuted,
            title: str.proxyMode,
            subtitle: str.proxyModeSubtitle,
            value: isProxyActive,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.setSystemProxy = v),
          ),
        ],
      ),
    );
  }
}

class _RoutingBadge extends StatelessWidget {
  const _RoutingBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9.5, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _RoutingToggleRow extends StatelessWidget {
  const _RoutingToggleRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.trailingBadge,
    this.subtitleTooltip,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget? trailingBadge;
  final String? subtitleTooltip;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;

    Widget subtitleText = Text(
      subtitle,
      style: TextStyle(fontSize: 9, color: c.textMuted),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (subtitleTooltip != null) {
      subtitleText = Tooltip(
        message: subtitleTooltip!,
        waitDuration: const Duration(milliseconds: 300),
        child: subtitleText,
      );
    }

    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      hoverColor: c.hoverBg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4.5),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: value ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 13.5, color: iconColor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: value ? c.textPrimary : c.textSecondary,
                        ),
                      ),
                      if (trailingBadge != null) ...[
                        const SizedBox(width: 5),
                        trailingBadge!,
                      ],
                    ],
                  ),
                  subtitleText,
                ],
              ),
            ),
            Transform.scale(
              scale: 0.68,
              child: Switch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodPopupButton extends StatefulWidget {
  const _MethodPopupButton({
    required this.method,
    required this.isBusy,
    required this.onMethodChanged,
    required this.iconFor,
  });

  final ConnectionMethod method;
  final bool isBusy;
  final ValueChanged<ConnectionMethod> onMethodChanged;
  final IconData Function(ConnectionMethod) iconFor;

  @override
  State<_MethodPopupButton> createState() => _MethodPopupButtonState();
}

class _MethodPopupButtonState extends State<_MethodPopupButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final isBusy = widget.isBusy;

    return MouseRegion(
      cursor: isBusy ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: Colors.transparent,
          child: ModernPopupMenuButton<ConnectionMethod>(
            tooltip: 'Choose engine protocol',
            enabled: !isBusy,
            constraints: const BoxConstraints(maxHeight: 390, minWidth: 260),
            onSelected: widget.onMethodChanged,
            itemBuilder: (context) {
              final groups = [
                (
                  'AETHER (CLOUDFLARE WARP)',
                  Icons.bolt_rounded,
                  BrandColors.primary,
                  const [
                    ConnectionMethod.masque,
                    ConnectionMethod.wireguard,
                    ConnectionMethod.warpOnWarp,
                    ConnectionMethod.masqueOnMasque,
                  ],
                ),
                (
                  'PSIPHON PROTOCOL',
                  Icons.vpn_lock_rounded,
                  BrandColors.accentCyan,
                  const [
                    ConnectionMethod.psiphon,
                    ConnectionMethod.psiphonOverWarp,
                    ConnectionMethod.psiphonOverV2Ray,
                  ],
                ),
                (
                  'TOR ONION NETWORK',
                  Icons.shield_moon_rounded,
                  const Color(0xFFC084FC),
                  const [
                    ConnectionMethod.tor,
                    ConnectionMethod.torOverWarp,
                    ConnectionMethod.torOverV2Ray,
                  ],
                ),
                (
                  'SHARD (CF FRAGMENTATION)',
                  Icons.hub_rounded,
                  const Color(0xFF38BDF8),
                  const [
                    ConnectionMethod.shard,
                  ],
                ),
              ];

              final items = <PopupMenuEntry<ConnectionMethod>>[];
              for (var i = 0; i < groups.length; i++) {
                final (title, icon, color, methods) = groups[i];
                if (i > 0) {
                  items.add(const PopupMenuDivider(height: 8));
                }
                items.add(
                  PopupMenuItem<ConnectionMethod>(
                    enabled: false,
                    height: 22,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    child: Row(
                      children: [
                        Icon(icon, size: 11.5, color: color),
                        const SizedBox(width: 6),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: color.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                for (final m in methods) {
                  items.add(
                    PopupMenuItem<ConnectionMethod>(
                      value: m,
                      padding: EdgeInsets.zero,
                      height: 32,
                      child: ModernPopupHoverTile(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        borderRadius: 6,
                        child: Row(
                          children: [
                            Icon(
                              widget.iconFor(m),
                              size: 15,
                              color: m == widget.method
                                  ? BrandColors.accentCyan
                                  : c.textSecondary,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                m.displayName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: m == widget.method
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: m == widget.method
                                      ? BrandColors.accentCyan
                                      : c.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (m == widget.method)
                              const Icon(Icons.check_rounded,
                                  size: 15, color: BrandColors.accentCyan),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              }
              return items;
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: _hovered && !isBusy
                    ? c.cardElevated.withValues(alpha: 0.9)
                    : c.input.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _hovered && !isBusy
                      ? BrandColors.accentCyan.withValues(alpha: 0.55)
                      : c.border.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: BrandColors.accentCyan.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(widget.iconFor(widget.method),
                        size: 16, color: BrandColors.accentCyan),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.method.displayName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          widget.method.isChained
                              ? 'Multi-Hop DPI Resilience Core'
                              : (widget.method.isAether
                                  ? 'Cloudflare Network Mesh'
                                  : (widget.method.isTor
                                      ? 'Tor Onion Routing Mesh'
                                      : 'Psiphon Obfuscation Core')),
                          style: TextStyle(
                            fontSize: 10,
                            color: c.textMuted,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.card.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: c.border.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Switch',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: c.textSecondary),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.unfold_more_rounded,
                            size: 13, color: c.textMuted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EgressRegionCard extends ConsumerWidget {
  const _EgressRegionCard({
    required this.method,
    required this.onRegionPicked,
  });

  final ConnectionMethod method;
  final ValueChanged<String> onRegionPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<AppColors>()!;
    final str = ref.watch(stringsProvider);
    final selectedCode = ref
        .watch(settingsProvider.select(
            (s) => method.isTor ? s.torExitCountry : s.egressRegion))
        .toUpperCase();
    final supportsRegion = method.supportsRegionPicker;

    final regionInfo = ref.watch(tunnelStatusProvider.select((st) => (
          available: st.valueOrNull?.availableEgressRegions ?? const <String>[],
          connected: st.valueOrNull?.connectedServerRegion ?? '',
          isConnected: st.valueOrNull?.state == ConnectionState.connected,
        )));

    final available = method.isTor
        ? RegionCatalog.torSeedRegions
        : (regionInfo.available.isNotEmpty
            ? regionInfo.available
            : RegionCatalog.psiphonSeedRegions);

    final isConnected = regionInfo.isConnected;
    final hasActiveEgress = isConnected && regionInfo.connected.isNotEmpty;

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4.5),
                decoration: BoxDecoration(
                  color: BrandColors.accentCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.public_rounded,
                    size: 14, color: BrandColors.accentCyan),
              ),
              const SizedBox(width: 8),
              Text(
                str.exitLocation,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: c.textMuted,
                ),
              ),
              const Spacer(),
              if (hasActiveEgress)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: BrandColors.emerald.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: BrandColors.emerald.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: CountryFlag.fromCountryCode(
                          regionInfo.connected,
                          height: 10,
                          width: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        RegionCatalog.nameFor(regionInfo.connected),
                        style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: BrandColors.emerald),
                      ),
                    ],
                  ),
                )
              else if (isConnected && method.isTor)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC084FC).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color:
                            const Color(0xFFC084FC).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hub_rounded,
                          size: 11, color: Color(0xFFC084FC)),
                      SizedBox(width: 4),
                      Text(
                        'Dynamic / Multi-Hop',
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFC084FC)),
                      ),
                    ],
                  ),
                )
              else if (!supportsRegion)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.input.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'Fixed by Protocol',
                    style: TextStyle(fontSize: 9.5, color: c.textMuted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _RegionSelectButton(
            method: method,
            selectedCode: selectedCode,
            available: available,
            onRegionPicked: onRegionPicked,
          ),
        ],
      ),
    );
  }
}

class _RegionSelectButton extends StatefulWidget {
  const _RegionSelectButton({
    required this.method,
    required this.selectedCode,
    required this.available,
    required this.onRegionPicked,
  });

  final ConnectionMethod method;
  final String selectedCode;
  final Iterable<String> available;
  final ValueChanged<String> onRegionPicked;

  @override
  State<_RegionSelectButton> createState() => _RegionSelectButtonState();
}

class _RegionSelectButtonState extends State<_RegionSelectButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final selectedCode = widget.selectedCode;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () async {
          final picked = await showModernRegionPicker(
            context: context,
            options: RegionCatalog.optionsFrom(widget.available),
            selectedCode: selectedCode,
          );
          if (picked != null) {
            widget.onRegionPicked(picked.code);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6.5),
          decoration: BoxDecoration(
            color: _hovered
                ? c.cardElevated.withValues(alpha: 0.9)
                : c.input.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: _hovered
                  ? BrandColors.accentCyan.withValues(alpha: 0.55)
                  : c.border.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 25,
                height: 18,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3.5),
                  border:
                      Border.all(color: c.border.withValues(alpha: 0.5)),
                ),
                child: selectedCode.isEmpty
                    ? const Icon(Icons.flash_on_rounded,
                        size: 13, color: BrandColors.accentCyan)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(2.5),
                        child: CountryFlag.fromCountryCode(
                          selectedCode,
                          height: 18,
                          width: 25,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      selectedCode.isEmpty
                          ? 'Optimal (Fastest Available)'
                          : RegionCatalog.nameFor(selectedCode),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      selectedCode.isEmpty
                          ? (widget.method.isTor
                              ? 'Tor Mesh (Dynamic multi-hop exits)'
                              : 'Auto-routed via nearest POP')
                          : 'Exit Node Region: $selectedCode',
                      style: TextStyle(fontSize: 9.5, color: c.textMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: c.card.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: c.border.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      selectedCode.isEmpty ? 'AUTO' : selectedCode,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.unfold_more_rounded,
                        size: 12, color: c.textMuted),
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
