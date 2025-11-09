import 'dart:async';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/xboard/features/auth/providers/xboard_user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/l10n/l10n.dart';

import 'package:fl_clash/xboard/features/shared/shared.dart';
import 'package:fl_clash/xboard/features/latency/services/auto_latency_service.dart';
import 'package:fl_clash/xboard/features/subscription/services/subscription_status_checker.dart';
import 'package:fl_clash/xboard/features/auth/pages/login_page.dart';
import '../widgets/subscription_usage_card.dart';
import '../widgets/xboard_vpn_panel.dart';
class XBoardHomePage extends ConsumerStatefulWidget {
  const XBoardHomePage({super.key});
  @override
  ConsumerState<XBoardHomePage> createState() => _XBoardHomePageState();
}
class _XBoardHomePageState extends ConsumerState<XBoardHomePage> 
    with AutomaticKeepAliveClientMixin {
  bool _hasInitialized = false;
  bool _hasStartedLatencyTesting = false;
  
  @override
  bool get wantKeepAlive => true;  // 保持页面状态，防止重建
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hasInitialized) return;
      _hasInitialized = true;
      final userState = ref.read(xboardUserProvider);
      if (userState.isAuthenticated) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            subscriptionStatusChecker.checkSubscriptionStatusOnStartup(context, ref);
          }
        });
      }
      autoLatencyService.initialize(ref);
      _waitForGroupsAndStartTesting();
    });
    ref.listenManual(xboardUserProvider, (previous, next) {
      if (next.errorMessage == 'TOKEN_EXPIRED') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showTokenExpiredDialog();
        });
      }
    });
    ref.listenManual(currentProfileProvider, (previous, next) {
      if (previous?.label != next?.label && previous != null) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            autoLatencyService.testCurrentNode(forceTest: true);
          }
        });
      }
    });
    ref.listenManual(groupsProvider, (previous, next) {
      if ((previous?.isEmpty ?? true) && next.isNotEmpty && !_hasStartedLatencyTesting) {
        _hasStartedLatencyTesting = true;
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            _performInitialLatencyTest();
          }
        });
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    super.build(context);  // 必须调用，配合 AutomaticKeepAliveClientMixin
    
    return Scaffold(
      appBar: null, 
      body: Builder(
        builder: (context) {
          // 获取屏幕高度并计算自适应间距
          final screenHeight = MediaQuery.of(context).size.height;
          final appBarHeight = 0.0;
          final statusBarHeight = MediaQuery.of(context).padding.top;
          final bottomNavHeight = 0.0; // 底部导航栏高度已隐藏
          final availableHeight = screenHeight - appBarHeight - statusBarHeight - bottomNavHeight;
          
          // 根据可用高度调整间距
          double sectionSpacing;
          double verticalPadding;
          double horizontalPadding;
          
          if (availableHeight < 500) {
            // 小屏幕：紧凑布局
            sectionSpacing = 8.0;
            verticalPadding = 8.0;
            horizontalPadding = 12.0;
          } else if (availableHeight < 650) {
            // 中等屏幕：适中布局
            sectionSpacing = 10.0;
            verticalPadding = 10.0;
            horizontalPadding = 16.0;
          } else {
            // 大屏幕：标准布局
            sectionSpacing = 14.0;
            verticalPadding = 12.0;
            horizontalPadding = 16.0;
          }
          
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  Theme.of(context).colorScheme.surface,
                ],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(vertical: verticalPadding),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - (2 * verticalPadding),
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                              child: _buildConnectionSection(),
                            ),
                            if (availableHeight > 600) const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
  Widget _buildUsageSection() {
    return Consumer(
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
    );
  }
  Widget _buildConnectionSection() {
    return Consumer(
      builder: (context, ref, child) {
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 全新 VPN 加速器面板，包含更顺滑的交互与动画
            XBoardVpnPanel(),
          ],
        );
      },
    );
  }


  Widget _buildProxyModeSection() {
    return const XBoardOutboundMode();
  }
  void _showTokenExpiredDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(appLocalizations.xboardTokenExpiredTitle),
        content: Text(appLocalizations.xboardTokenExpiredContent),
        actions: [
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final userNotifier = ref.read(xboardUserProvider.notifier);
              navigator.pop();
              if (!mounted) return;
              userNotifier.clearTokenExpiredError();
              await userNotifier.handleTokenExpired();
              if (!mounted) return;
              navigator.pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => const LoginPage(),
                ),
                (route) => false, // 清除所有路由
              );
            },
            child: Text(appLocalizations.xboardRelogin),
          ),
        ],
      ),
    );
  }

  void _waitForGroupsAndStartTesting() {
    if (_hasStartedLatencyTesting) {
      return;
    }
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        final groups = ref.read(groupsProvider);
        if (groups.isNotEmpty && !_hasStartedLatencyTesting) {
          timer.cancel();
          _hasStartedLatencyTesting = true;
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              _performInitialLatencyTest();
            }
          });
        }
      } catch (e) {
        debugPrint('XBoardHomePage wait groups error: $e');
      }
    });
  }
  void _performInitialLatencyTest() {
    if (!mounted) return;
    autoLatencyService.testCurrentNode();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        final userState = ref.read(xboardUserProvider);
        if (userState.isAuthenticated) {
          autoLatencyService.testCurrentGroupNodes();
        }
      }
    });
  }
} 