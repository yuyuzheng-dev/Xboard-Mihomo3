import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:go_router/go_router.dart';

// Required imports
import 'package:fl_clash/xboard/features/shared/widgets/xboard_outbound_mode.dart';
import 'package:fl_clash/xboard/features/shared/widgets/node_selector_bar.dart';
import 'package:fl_clash/xboard/features/subscription/widgets/subscription_usage_card.dart';
import 'package:fl_clash/xboard/features/auth/providers/xboard_user_provider.dart';
import 'package:fl_clash/xboard/features/notice/notice.dart';
import 'package:fl_clash/xboard/features/invite/dialogs/logout_dialog.dart';

import 'notice_detail_sheet.dart';

class XBoardVpnPanel extends ConsumerStatefulWidget {
  const XBoardVpnPanel({super.key});

  @override
  ConsumerState<XBoardVpnPanel> createState() => _XBoardVpnPanelState();
}

class _XBoardVpnPanelState extends ConsumerState<XBoardVpnPanel> {
  bool isStart = false;

  @override
  void initState() {
    super.initState();
    isStart = globalState.appState.runTime != null;
  }

  void _handleToggle() {
    setState(() {
      isStart = !isStart;
    });
    debouncer.call(
      FunctionTag.updateStatus,
      () {
        globalState.appController.updateStatus(isStart);
      },
      duration: commonDuration,
    );
  }

  @override
  Widget build(BuildContext context) {
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

                // Connection Toggle Button
                _buildConnectButton(context, connectColor, disconnectColor),
                const SizedBox(height: 8),
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
      if (notices.isEmpty) {
        return const SizedBox(
          width: 48,
        );
      }
      return IconButton(
        icon: Badge(
          isLabelVisible: notices.isNotEmpty,
          child: const Icon(
            Icons.campaign_rounded,
          ),
        ),
        onPressed: () {
          _showNoticeBottomSheet(context, notices);
        },
      );
    });
  }

  void _showNoticeBottomSheet(BuildContext context, List<NoticeData> notices) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.8,
          builder: (context, scrollController) {
            return NoticeDetailSheet(
              notices: notices,
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  // Menu Button for other options like plans, invite, and logout
  Widget _buildMenuButton(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu_rounded),
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (context) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.4,
              minChildSize: 0.3,
              maxChildSize: 0.6,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title:
                              Text(AppLocalizations.of(context).xboardPlanInfo),
                          onTap: () {
                            context.push('/plans');
                            Navigator.of(context).pop();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.person_add_alt_1_outlined),
                          title: Text(AppLocalizations.of(context).invite),
                          onTap: () {
                            context.push('/invite');
                            Navigator.of(context).pop();
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.logout),
                          title: Text(AppLocalizations.of(context).logout),
                          onTap: () {
                            Navigator.of(context).pop();
                            showDialog(
                              context: context,
                              builder: (context) => const LogoutDialog(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // Connection Toggle Area (Using a simpler button)
  Widget _buildConnectButton(
    BuildContext context,
    Color connectColor,
    Color disconnectColor,
  ) {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: _handleToggle,
        icon: Icon(isStart ? Icons.stop_rounded : Icons.play_arrow_rounded),
        label: Text(
          isStart
              ? AppLocalizations.of(context).xboardStopProxy
              : AppLocalizations.of(context).xboardStartProxy,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: isStart ? disconnectColor : connectColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}
