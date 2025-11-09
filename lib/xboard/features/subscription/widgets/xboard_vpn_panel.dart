import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:go_router/go_router.dart';

import 'package:fl_clash/xboard/features/shared/widgets/notice_banner.dart';
import 'package:fl_clash/xboard/features/shared/widgets/xboard_outbound_mode.dart';
import 'package:fl_clash/xboard/features/shared/widgets/node_selector_bar.dart';
import 'package:fl_clash/xboard/features/subscription/widgets/subscription_usage_card.dart';
import 'package:fl_clash/xboard/features/auth/providers/xboard_user_provider.dart';
import 'package:fl_clash/xboard/features/notice/notice.dart';
import 'package:fl_clash/xboard/features/invite/dialogs/logout_dialog.dart';

class XBoardVpnPanel extends ConsumerStatefulWidget {
  const XBoardVpnPanel({super.key});

  @override
  ConsumerState<XBoardVpnPanel> createState() => _XBoardVpnPanelState();
}

class _XBoardVpnPanelState extends ConsumerState<XBoardVpnPanel>
    with TickerProviderStateMixin {
  late AnimationController _toggleController;
  late Animation<double> _toggleAnimation;
  late AnimationController _pulseController;
  late AnimationController _pressScaleController;
  bool isStart = false;

  @override
  void initState() {
    super.initState();
    isStart = globalState.appState.runTime != null;
    _toggleController = AnimationController(
      vsync: this,
      value: isStart ? 1 : 0,
      duration: const Duration(milliseconds: 250),
    );
    _toggleAnimation = CurvedAnimation(
      parent: _toggleController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (isStart) {
      _pulseController.repeat();
    }
    _pressScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.0,
      upperBound: 0.08,
      value: 0.0,
    );
  }

  @override
  void dispose() {
    _toggleController.dispose();
    _pulseController.dispose();
    _pressScaleController.dispose();
    super.dispose();
  }

  void _handleToggle() {
    isStart = !isStart;
    _updateControllers();
    debouncer.call(
      FunctionTag.updateStatus,
      () {
        globalState.appController.updateStatus(isStart);
      },
      duration: commonDuration,
    );
  }

  void _updateControllers() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (isStart) {
        _toggleController.forward();
        if (!_pulseController.isAnimating) {
          _pulseController.repeat();
        }
      } else {
        _toggleController.reverse();
        if (_pulseController.isAnimating) {
          _pulseController.stop();
          _pulseController.reset();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final connectColor = scheme.primary;
    final disconnectColor = scheme.error;

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Main Panel - Simplified and streamlined UI
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Header Section: Notifications and Menu
                Row(
                  children: [
                    _buildNoticeIcon(context),
                    const Spacer(),
                    _buildMenuButton(context),
                  ],
                ),
                const SizedBox(height: 16),

                // Subscription Info Card
                Consumer(
                  builder: (context, ref, child) {
                    final userInfo = ref.watch(userInfoProvider);
                    final subscriptionInfo = ref.watch(subscriptionInfoProvider);
                    final currentProfile = ref.watch(currentProfileProvider);
                    return SubscriptionUsageCard(
                      subscriptionInfo: subscriptionInfo,
                      userInfo: userInfo,
                      profileSubscriptionInfo: currentProfile?.subscriptionInfo,
                    );
                  },
                ),
                const SizedBox(height: 16),

                // VPN Mode Selector (Proxy Mode)
                const XBoardOutboundMode(),
                const SizedBox(height: 16),

                // Node Selection (Directly beneath VPN Mode)
                const NodeSelectorBar(),
                const SizedBox(height: 16),

                // Quick Stats (Updated positioning above the connection switch)
                _buildQuickStats(context),
                const SizedBox(height: 16),

                // Connection Toggle Button
                _buildConnectArea(context, connectColor, disconnectColor),
                const SizedBox(height: 8),
                _buildStatusText(context, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Simplified Notice Icon
  Widget _buildNoticeIcon(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final noticeState = ref.watch(noticeProvider);
      final notices = noticeState.visibleNotices;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (notices.isEmpty) {
              ref.read(noticeProvider.notifier).fetchNotices();
            } else {
              showDialog(
                context: context,
                builder: (context) => NoticeDetailDialog(
                  notices: notices,
                  initialIndex: 0,
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Icon(
            Icons.campaign_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    });
  }

  // Menu Button for other options like plans, invite, and logout
  Widget _buildMenuButton(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu_rounded),
      onSelected: (value) async {
        switch (value) {
          case 'plans':
            context.push('/plans');
            break;
          case 'invite':
            context.go('/invite');
            break;
          case 'logout':
            showDialog(
              context: context,
              builder: (context) => const LogoutDialog(),
            );
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'plans',
          child: Text(AppLocalizations.of(context).xboardPlanInfo),
        ),
        PopupMenuItem(
          value: 'invite',
          child: Text(AppLocalizations.of(context).invite),
        ),
        PopupMenuItem(
          value: 'logout',
          child: Text(AppLocalizations.of(context).logout),
        ),
      ],
    );
  }

  // Connection Toggle Area (Using a Circular Animated Button)
  Widget _buildConnectArea(
    BuildContext context,
    Color connectColor,
    Color disconnectColor,
  ) {
    return Center(
      child: GestureDetector(
        onTap: _handleToggle,
        onTapDown: (_) => _pressScaleController.forward(),
        onTapCancel: () => _pressScaleController.reverse(),
        onTapUp: (_) => _pressScaleController.reverse(),
        child: AnimatedBuilder(
          animation: Listenable.merge([_toggleController, _pulseController]),
          builder: (context, child) {
            final scale = 1 - _pressScaleController.value;
            final activeColor = isStart ? connectColor : disconnectColor;
            return SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isStart) ...[
                    // Pulse animation effect
                    ...List.generate(3, (i) {
                      final t = (_pulseController.value + i / 3) % 1.0;
                      final ringSize = 120 * (1 + t * 1.4);
                      final opacity = (1 - t) * 0.3;
                      return Container(
                        width: ringSize,
                        height: ringSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: activeColor.withOpacity(opacity),
                              blurRadius: 22 * t + 4,
                              spreadRadius: 1,
                            ),
                          ],
                          border: Border.all(
                            color: activeColor.withOpacity(opacity),
                            width: 1.0,
                          ),
                        ),
                      );
                    }),
                  ],
                  // Main toggle button
                  Transform.scale(
                    scale: scale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            activeColor.withOpacity(0.9),
                            activeColor.withOpacity(0.7),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: activeColor.withOpacity(0.35),
                            blurRadius: 16,
                            spreadRadius: 1.5,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: 60,
                        height: 60,
                        child: Center(
                          child: AnimatedIcon(
                            icon: AnimatedIcons.play_pause,
                            progress: _toggleAnimation,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // Status Text - VPN connection state and uptime
  Widget _buildStatusText(BuildContext context, bool isDark) {
    return Consumer(
      builder: (context, ref, _) {
        final runTime = ref.watch(runTimeProvider);
        final textTheme = Theme.of(context).textTheme;
        final statusText = isStart
            ? AppLocalizations.of(context).xboardStopProxy
            : AppLocalizations.of(context).xboardStartProxy;
        return Column(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.25),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                statusText,
                key: ValueKey(isStart),
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (isStart) ...[
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  AppLocalizations.of(context).xboardRunningTime(
                    utils.getTimeText(runTime),
                  ),
                  key: ValueKey(runTime),
                  style: textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.7),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // Quick Statistics (Uploaded / Downloaded data)
  Widget _buildQuickStats(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final traffics = ref.watch(trafficsProvider).list;
        final last = traffics.isEmpty ? null : traffics.last;
        final up = last != null ? last.up.toString() : '0B';
        final down = last != null ? last.down.toString() : '0B';

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Upload/Download statistics
            _buildChip(Icons.file_upload_outlined, '↑ $up'),
            _buildChip(Icons.file_download_outlined, '↓ $down'),
          ],
        );
      },
    );
  }

  // Helper method to build chips
  Widget _buildChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
