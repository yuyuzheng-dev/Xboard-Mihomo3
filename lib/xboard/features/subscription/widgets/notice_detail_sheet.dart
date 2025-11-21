import 'package:fl_clash/xboard/sdk/xboard_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

class NoticeDetailSheet extends StatefulWidget {
  final List<NoticeData> notices;
  final ScrollController scrollController;
  final int initialIndex;

  const NoticeDetailSheet({
    super.key,
    required this.notices,
    required this.scrollController,
    this.initialIndex = 0,
  });

  @override
  State<NoticeDetailSheet> createState() => _NoticeDetailSheetState();
}

class _NoticeDetailSheetState extends State<NoticeDetailSheet> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.notices.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.notices.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                return SingleChildScrollView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: _buildNoticeContent(widget.notices[index]),
                );
              },
            ),
          ),
          if (widget.notices.length > 1) _buildNavigationBar(),
          const SizedBox(
            height: 16,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final notice = widget.notices[_currentIndex];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              notice.title,
              style: Theme.of(context).textTheme.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          widget.notices.length,
          (index) => Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _currentIndex == index
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoticeContent(NoticeData notice) {
    // 检查内容是否可能是HTML
    final isHtml = notice.content.contains(RegExp(r'<[a-z][\s\S]*>'));

    if (isHtml) {
      // 这是一个临时的解决方案，因为我无法添加 `flutter_html` 依赖
      // 我将使用 `MarkdownBody` 来尝试渲染它，它支持一部分HTML标签
      return MarkdownBody(
        data: notice.content,
        onTapLink: (text, href, title) {
          if (href != null) {
            launchUrl(Uri.parse(href));
          }
        },
      );
    } else {
      return MarkdownBody(
        data: notice.content,
        onTapLink: (text, href, title) {
          if (href != null) {
            launchUrl(Uri.parse(href));
          }
        },
      );
    }
  }
}