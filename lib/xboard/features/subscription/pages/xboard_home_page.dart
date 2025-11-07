import 'dart:async';
import 'dart:io';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/xboard/features/auth/providers/xboard_user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fl_clash/xboard/features/shared/shared.dart';
import 'package:fl_clash/xboard/features/latency/services/auto_latency_service.dart';
import 'package:fl_clash/xboard/features/subscription/services/subscription_status_checker.dart';
import 'package:fl_clash/xboard/features/auth/pages/login_page.dart';
import 'package:fl_clash/xboard/features/invite/dialogs/theme_dialog.dart';
import 'package:fl_clash/xboard/features/invite/dialogs/logout_dialog.dart';
import '../widgets/subscription_usage_card.dart';
import '../widgets/xboard_connect_button.dart';
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
    
    final appLocalizations = AppLocalizations.of(context);
    // 根据操作系统平台判断设备类型
    final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    
    return Scaffold(
      appBar: isDesktop ? null : AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 120,
        leading: TextButton.icon(
          icon: const Icon(Icons.support_agent, size: 20),
          label: Text(appLocalizations.onlineSupport),
          onPressed: () {
            // 移动端独有的按钮，使用 push 创建路由栈
            context.push('/support');
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.card_giftcard, size: 20),
            label: Text(appLocalizations.xboardPlanInfo),
            onPressed: () {
              // 移动端独有的按钮，使用 push 创建路由栈
              context.push('/plans');
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
      body: Consumer(
        builder: (_, ref, __) {
          // 获取屏幕高度并计算自适应间距
          final screenHeight = MediaQuery.of(context).size.height;
        final appBarHeight = kToolbarHeight;
        final statusBarHeight = MediaQuery.of(context).padding.top;
        final bottomNavHeight = 60.0; // 底部导航栏高度
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
                          const NoticeBanner(),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                            child: _buildUsageSection(),
                          ),
                          SizedBox(height: sectionSpacing),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                            child: _buildProxyModeSection(),
                          ),
                          SizedBox(height: sectionSpacing),
                          const NodeSelectorBar(),
                          SizedBox(height: sectionSpacing),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                            child: _buildConnectionSection(),
                          ),
                          // 添加弹性空间，确保内容不会太紧凑
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const XBoardConnectButton(isFloating: false),
            const SizedBox(height: 10),
            ...List.generate(5, (index) => _buildTxtButton(context, index)).expand((w) => [w, const SizedBox(height: 10)]).toList()..removeLast(),
          ],
        );
      },
    );
  }
  Widget _buildTxtButton(BuildContext context, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.blue.shade200 : colorScheme.primary;
    final appLocalizations = AppLocalizations.of(context);

    // 根据索引设置按钮文本与功能
    String label;
    Future<void> Function()? onTap;
    switch (index) {
      case 0:
        label = appLocalizations.xboardPlanInfo; // 购买订阅
        onTap = () async {
          if (!context.mounted) return;
          context.push('/plans');
        };
        break;
      case 1:
        label = appLocalizations.invite; // 邀请好友
        onTap = () async {
          if (!context.mounted) return;
          context.go('/invite');
        };
        break;
      case 2:
        label = appLocalizations.contactSupport; // 联系客服 -> 内置网页
        onTap = () async {
          final uri = Uri.parse('https://www.baidu.com');
          if (!await canLaunchUrl(uri)) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(appLocalizations.openWebFailed)),
              );
            }
            return;
          }
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.inAppWebView,
          );
          if (!launched && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(appLocalizations.openWebFailed)),
            );
          }
        };
        break;
      case 3:
        label = appLocalizations.switchTheme; // 切换主题
        onTap = () async {
          if (!context.mounted) return;
          showDialog(
            context: context,
            builder: (context) => const ThemeDialog(),
          );
        };
        break;
      case 4:
        label = appLocalizations.logout; // 退出登录
        onTap = () async {
          if (!context.mounted) return;
          showDialog(
            context: context,
            builder: (context) => const LogoutDialog(),
          );
        };
        break;
      default:
        label = 'txt';
        onTap = () async {};
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.black : Colors.white,
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