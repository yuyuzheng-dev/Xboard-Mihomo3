import 'dart:io';
import 'package:fl_clash/xboard/features/auth/providers/xboard_user_provider.dart';
import 'package:fl_clash/xboard/features/auth/models/auth_state.dart';
import 'package:fl_clash/xboard/features/subscription/providers/xboard_subscription_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/models/models.dart' as fl_models;
import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
import 'package:go_router/go_router.dart';
import '../services/subscription_status_service.dart';
import 'package:fl_clash/l10n/l10n.dart';
class SubscriptionUsageCard extends ConsumerWidget {
  final SubscriptionData? subscriptionInfo;
  final UserInfoData? userInfo;
  final fl_models.SubscriptionInfo? profileSubscriptionInfo;
  const SubscriptionUsageCard({
    super.key,
    this.subscriptionInfo,
    this.userInfo,
    this.profileSubscriptionInfo,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final userState = ref.watch(xboardUserProvider);

    // 当前是否已经有任何订阅/用户相关数据
    final hasSubscriptionData = profileSubscriptionInfo != null ||
        userInfo != null ||
        subscriptionInfo != null;

    // 过滤掉 TOKEN_EXPIRED，这类错误由专门的对话框与路由处理
    final rawError = userState.errorMessage;
    final hasGenericError = rawError != null && rawError != 'TOKEN_EXPIRED';

    // 当还没有任何数据时，使用 AsyncValue 统一处理 加载 / 错误 / 空状态
    if (!hasSubscriptionData) {
      final AsyncValue<void> loadState;
      if (userState.isLoading) {
        loadState = const AsyncValue.loading();
      } else if (hasGenericError) {
        loadState = AsyncValue.error(rawError!, StackTrace.current);
      } else {
        loadState = const AsyncValue.data(null);
      }

      return loadState.when(
        loading: () => _buildLoadingCard(theme, context),
        error: (error, _) => _buildErrorCard(
          theme,
          context,
          error.toString(),
          ref,
        ),
        data: (_) => _buildEmptyCard(theme, context),
      );
    }

    // 已有数据时，根据订阅状态展示不同卡片，同时在卡片内部附加错误提示
    SubscriptionStatusResult? subscriptionStatus;
    if (userState.isAuthenticated && subscriptionInfo != null) {
      subscriptionStatus = subscriptionStatusService.checkSubscriptionStatus(
        userState: userState,
        profileSubscriptionInfo: profileSubscriptionInfo,
      );
    }

    final inlineErrorMessage =
        !userState.isLoading && hasGenericError ? rawError : null;

    if (subscriptionStatus != null &&
        (subscriptionStatus.type == SubscriptionStatusType.expired ||
            subscriptionStatus.type == SubscriptionStatusType.exhausted ||
            subscriptionStatus.type == SubscriptionStatusType.noSubscription)) {
      return _buildStatusCard(
        subscriptionStatus,
        theme,
        context,
        userState,
        ref,
        inlineErrorMessage,
      );
    }

    return _buildUsageCard(
      theme,
      context,
      userState,
      ref,
      inlineErrorMessage,
    );
  }
  Widget _buildEmptyCard(ThemeData theme, BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off,
            size: 40,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).xboardNoSubscriptionInfo,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            AppLocalizations.of(context).xboardLoginToViewSubscription,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    ),
  );
  }

  Widget _buildLoadingCard(ThemeData theme, BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 16,
                        width: 120,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: 180,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(
    ThemeData theme,
    BuildContext context,
    String errorMessage,
    WidgetRef ref,
  ) {
    final localization = AppLocalizations.of(context);
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localization.xboardLoadingFailed,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        errorMessage,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  await ref.read(xboardUserProvider.notifier).refreshSubscriptionInfo();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(localization.xboardRetry),
                ),
                ),
                ],
                ),
                ),
                );
                }

                Widget _buildInlineErrorBanner(
                ThemeData theme,
                BuildContext context,
                WidgetRef ref,
                String errorMessage,
                ) {
                final localization = AppLocalizations.of(context);
                return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text(
                  localization.xboardLoadingFailed,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  errorMessage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.9),
                  ),
                ),
                ],
                ),
                ),
                const SizedBox(width: 8),
                TextButton(
                onPressed: () async {
                await ref.read(xboardUserProvider.notifier).refreshSubscriptionInfo();
                },
                style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onErrorContainer,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(localization.xboardRetry),
                ),
                ],
                ),
                );
                }

                Widget _buildStatusCard(SubscriptionStatusResult statusResult, ThemeData theme, BuildContext context, UserAuthState userState, WidgetRef ref, String? inlineErrorMessage) {
    IconData statusIcon;
    Color statusColor;
    String statusText;
    String statusDetail;
    switch (statusResult.type) {
      case SubscriptionStatusType.noSubscription:
        statusIcon = Icons.card_giftcard;
        statusColor = Colors.blue.shade600;
        statusText = AppLocalizations.of(context).xboardNoAvailableSubscription;
        statusDetail = AppLocalizations.of(context).xboardPurchaseSubscriptionToUse;
        break;
      case SubscriptionStatusType.expired:
        statusIcon = Icons.schedule;
        statusColor = Colors.red.shade600;
        statusText = AppLocalizations.of(context).xboardSubscriptionExpired;
        statusDetail = statusResult.getDetailMessage(context) ?? AppLocalizations.of(context).xboardRenewToContinue;
        break;
      case SubscriptionStatusType.exhausted:
        statusIcon = Icons.data_usage;
        statusColor = Colors.orange.shade600;
        statusText = AppLocalizations.of(context).xboardTrafficExhausted;
        statusDetail = statusResult.getDetailMessage(context) ?? AppLocalizations.of(context).xboardBuyMoreTrafficOrUpgrade;
        break;
      default:
        statusIcon = Icons.info;
        statusColor = theme.colorScheme.primary;
        statusText = statusResult.getMessage(context);
        statusDetail = statusResult.getDetailMessage(context) ?? '';
    }
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              statusColor.withValues(alpha: 0.03),
              statusColor.withValues(alpha: 0.01),
            ],
          ),
        ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  statusIcon,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusDetail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: userState.isLoading
                    ? null
                    : () async {
                        await ref
                            .read(xboardUserProvider.notifier)
                            .refreshSubscriptionInfo();
                      },
                icon: userState.isLoading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: statusColor,
                        ),
                      )
                    : Icon(
                        Icons.refresh,
                        color: statusColor,
                        size: 20,
                      ),
                tooltip: AppLocalizations.of(context).xboardRefresh,
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(20, 20),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          if (statusResult.expiredAt != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${AppLocalizations.of(context).xboardExpiryTime}: ${_formatDateTime(statusResult.expiredAt!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 续费按钮
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                await _handleRenewAction(context, ref);
              },
              style: FilledButton.styleFrom(
                backgroundColor: statusColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.shopping_bag, size: 18),
              label: Text(_getRenewButtonText(statusResult.type, context)),
            ),
          ),
          if (inlineErrorMessage != null && inlineErrorMessage.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildInlineErrorBanner(theme, context, ref, inlineErrorMessage),
          ],
        ],
      ),
      ),
    );
  }
  
  String _getRenewButtonText(SubscriptionStatusType type, BuildContext context) {
    switch (type) {
      case SubscriptionStatusType.noSubscription:
        return AppLocalizations.of(context).xboardPurchasePlan;
      case SubscriptionStatusType.expired:
        return AppLocalizations.of(context).xboardRenewPlan;
      case SubscriptionStatusType.exhausted:
        return AppLocalizations.of(context).xboardPurchaseTraffic;
      default:
        return AppLocalizations.of(context).xboardPurchasePlan;
    }
  }
  
  Future<void> _handleRenewAction(BuildContext context, WidgetRef ref) async {
    final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    
    // 尝试获取用户当前订阅的套餐ID
    final userState = ref.read(xboardUserProvider);
    final currentPlanId = userState.subscriptionInfo?.planId;
    
    if (currentPlanId != null) {
      // 确保套餐列表已加载
      var plans = ref.read(xboardSubscriptionProvider);
      if (plans.isEmpty) {
        await ref.read(xboardSubscriptionProvider.notifier).loadPlans();
        plans = ref.read(xboardSubscriptionProvider);
      }
      
      final currentPlan = plans.cast<PlanData?>().firstWhere(
        (plan) => plan?.id == currentPlanId,
        orElse: () => null,
      );
      
      if (currentPlan != null) {
        if (isDesktop) {
          // 桌面端：通过URL参数传递套餐ID，Plans页面内部会显示购买界面
          context.go('/plans?planId=$currentPlanId');
        } else {
          // 移动端：直接跳转到全屏购买页面
          context.push('/plans/purchase', extra: currentPlan);
        }
        return;
      }
    }
    
    // 没找到套餐：跳转到套餐列表页面
    if (isDesktop) {
      context.go('/plans');
    } else {
      context.push('/plans');
    }
  }

  Widget _buildUsageCard(
    ThemeData theme,
    BuildContext context,
    UserAuthState userState,
    WidgetRef ref,
    String? inlineErrorMessage,
  ) {
    final progress = _getProgressValue();
    final usedTraffic = _getUsedTraffic();
    final totalTraffic = _getTotalTraffic();
    final remainingDays = _calculateRemainingDays();
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary.withValues(alpha: 0.03),
              theme.colorScheme.secondary.withValues(alpha: 0.02),
            ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${(progress * 100).toInt()}% ${AppLocalizations.of(context).xboardUsed}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: userState.isLoading
                      ? null
                      : () async {
                          await ref
                              .read(xboardUserProvider.notifier)
                              .refreshSubscriptionInfo();
                        },
                  icon: userState.isLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : Icon(
                          Icons.refresh,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                  tooltip: AppLocalizations.of(context).xboardRefresh,
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(20, 20),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
              ),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _getProgressColor(progress, theme),
                ),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildStatItem(
                    icon: Icons.cloud_download,
                    label:
                        AppLocalizations.of(context).xboardUsedTraffic,
                    value: _formatBytes(usedTraffic),
                    subtitle: '/ ${_formatBytes(totalTraffic)}',
                    theme: theme,
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: theme.colorScheme.outline
                      .withValues(alpha: 0.15),
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12),
                ),
                Expanded(
                  child: _buildStatItem(
                    icon: Icons.schedule,
                    label: AppLocalizations.of(context)
                        .xboardValidityPeriod,
                    value: '$remainingDays',
                    subtitle: AppLocalizations.of(context).xboardDays,
                    theme: theme,
                  ),
                ),
              ],
            ),
            if (inlineErrorMessage != null &&
                inlineErrorMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildInlineErrorBanner(
                theme,
                context,
                ref,
                inlineErrorMessage,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required String subtitle,
    required ThemeData theme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              TextSpan(
                text: subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  String _formatBytes(double bytes) {
    if (bytes < 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes;
    int unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    if (size >= 100) {
      return '${size.toStringAsFixed(0)} ${units[unitIndex]}';
    } else if (size >= 10) {
      return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
    } else {
      return '${size.toStringAsFixed(2)} ${units[unitIndex]}';
    }
  }
  int _calculateRemainingDays() {
    DateTime? expiredAt;
    if (profileSubscriptionInfo?.expire != null && profileSubscriptionInfo!.expire != 0) {
      expiredAt = DateTime.fromMillisecondsSinceEpoch(profileSubscriptionInfo!.expire * 1000);
    } else if (subscriptionInfo?.expiredAt != null) {
      expiredAt = subscriptionInfo!.expiredAt;
    }
    if (expiredAt == null) return 0;
    final now = DateTime.now();
    final difference = expiredAt.difference(now);
    return difference.inDays.clamp(0, double.infinity).toInt();
  }
  double _getProgressValue() {
    if (profileSubscriptionInfo != null && profileSubscriptionInfo!.total > 0) {
      final used = profileSubscriptionInfo!.upload + profileSubscriptionInfo!.download;
      return (used / profileSubscriptionInfo!.total).clamp(0.0, 1.0);
    }
    return 0.0;
  }
  double _getUsedTraffic() {
    if (profileSubscriptionInfo != null) {
      return (profileSubscriptionInfo!.upload + profileSubscriptionInfo!.download).toDouble();
    }
    return 0;
  }
  double _getTotalTraffic() {
    if (profileSubscriptionInfo != null && profileSubscriptionInfo!.total > 0) {
      return profileSubscriptionInfo!.total.toDouble();
    }
    return userInfo?.transferEnable ?? 0;
  }
  Color _getProgressColor(double progress, ThemeData theme) {
    if (progress >= 0.9) {
      return Colors.red.shade400;
    } else if (progress >= 0.7) {
      return Colors.orange.shade400;
    } else {
      return theme.colorScheme.primary;
    }
  }
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
           '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}