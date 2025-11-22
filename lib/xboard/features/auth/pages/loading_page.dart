import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/xboard/features/domain_status/domain_status.dart';

/// 全局启动加载页
///
/// 在应用进行快速认证和首次数据同步期间展示，避免首页出现空白或
/// 旧数据的闪烁状态。同时集成域名/网络状态检测，在网络异常或
/// 面板不可用时给出明确提示，避免长时间白屏无反馈。
class XBoardLoadingPage extends ConsumerStatefulWidget {
  const XBoardLoadingPage({super.key});

  @override
  ConsumerState<XBoardLoadingPage> createState() => _XBoardLoadingPageState();
}

class _XBoardLoadingPageState extends ConsumerState<XBoardLoadingPage> {
  bool _hasRequestedDomainCheck = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerDomainCheckIfNeeded();
    });
  }

  void _triggerDomainCheckIfNeeded() {
    if (_hasRequestedDomainCheck) return;
    _hasRequestedDomainCheck = true;

    final domainState = ref.read(domainStatusProvider);
    // 冷启动且还未检查过域名时，触发一次检测
    if (domainState.lastChecked == null) {
      ref.read(domainStatusProvider.notifier).checkDomain();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final domainState = ref.watch(domainStatusProvider);

    final isChecking = domainState.status == DomainStatus.checking;
    final hasError = domainState.errorMessage != null;
    final hasCheckedOnce = domainState.lastChecked != null;

    String subtitle;
    if (isChecking && !hasCheckedOnce) {
      subtitle = '正在检测线路与网络状态，请稍候...';
    } else if (isChecking) {
      subtitle = '正在重新检查线路状态...';
    } else if (domainState.status == DomainStatus.success) {
      subtitle = '线路已就绪，正在同步账户信息...';
    } else if (hasError) {
      subtitle = '当前无法连接到加速面板，请检查网络或稍后重试。';
    } else {
      subtitle = l10n.xboardProcessing;
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              colorScheme.surface,
            ],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorScheme.primary.withValues(alpha: 0.1),
                    ),
                    child: Icon(
                      Icons.vpn_key_outlined,
                      size: 48,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'XBoard',
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 域名 / 网络状态指示
                  DomainStatusIndicator(
                    showText: true,
                    showLatency: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                  ),
                  if (hasError && domainState.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    _buildErrorHint(context, domainState.errorMessage!),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: isChecking
                          ? null
                          : () {
                              ref
                                  .read(domainStatusProvider.notifier)
                                  .refresh();
                            },
                      icon: isChecking
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.primary,
                              ),
                            )
                          : const Icon(
                              Icons.refresh_rounded,
                              size: 18,
                            ),
                      label: Text(
                        isChecking ? '正在检测...' : '重新检查线路',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                      ),
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

  Widget _buildErrorHint(BuildContext context, String message) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
