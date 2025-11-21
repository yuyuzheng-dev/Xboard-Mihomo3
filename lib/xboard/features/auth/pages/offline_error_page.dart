import 'package:flutter/material.dart';

/// 离线错误页面
///
/// 在应用启动时无法连接到网络或初始化失败时显示
/// 提供重试选项和离线提示
class OfflineErrorPage extends StatefulWidget {
  final VoidCallback onRetry;

  const OfflineErrorPage({
    super.key,
    required this.onRetry,
  });

  @override
  State<OfflineErrorPage> createState() => _OfflineErrorPageState();
}

class _OfflineErrorPageState extends State<OfflineErrorPage> {
  bool _isRetrying = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Error Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.errorContainer.withValues(alpha: 0.3),
                  ),
                  child: Icon(
                    Icons.wifi_off_rounded,
                    size: 56,
                    color: colorScheme.error,
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  'Network Connection Failed',
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Description
                Text(
                  'Unable to connect to the network. Please check your internet connection and try again.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Retry Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _isRetrying
                        ? null
                        : () async {
                            setState(() {
                              _isRetrying = true;
                            });
                            await Future.delayed(const Duration(milliseconds: 500));
                            widget.onRetry();
                            if (mounted) {
                              setState(() {
                                _isRetrying = false;
                              });
                            }
                          },
                    icon: _isRetrying
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                colorScheme.onPrimary,
                              ),
                            ),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(
                      _isRetrying ? 'Retrying...' : 'Retry',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Additional Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Troubleshooting Tips:',
                        style: textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildTip(context, '• Check WiFi or mobile network connection'),
                      const SizedBox(height: 4),
                      _buildTip(context, '• Turn off airplane mode'),
                      const SizedBox(height: 4),
                      _buildTip(context, '• Try toggling WiFi on/off'),
                      const SizedBox(height: 4),
                      _buildTip(context, '• Check if network is accessible'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTip(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
