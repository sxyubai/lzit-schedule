/// 关于 / 介绍页
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// 作者
const String kAuthorName = '生鲜鱼白';

/// 交流 QQ 群
const String kGroupNumber = '1126356335';

/// GitHub 仓库地址
const String kGithubUrl = 'https://github.com/sxyubai/lzit-schedule';

/// 应用版本（与 pubspec 的 version 保持一致，改版本时一起改）
const String kAppVersion = '1.14.0';

/// 项目简介
const String kIntro =
    '一个干净的自用课表 App。\n'
    '因为原来的课表软件被商业化、广告太多，索性自己做了一个。\n\n'
    '· 直接从学校教务系统导入课表，无广告、无推送、不联网上报\n'
    '· 支持多套课表（大一/大二…）、手动添加课程与一次性事件\n'
    '· 上课提醒（响铃 + 震动）、自定义背景与透明度';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _copy(BuildContext context, String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制$what：$text'), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openGithub(BuildContext context) async {
    final uri = Uri.tryParse(kGithubUrl);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('打不开浏览器，地址已复制到剪贴板')),
      );
      await Clipboard.setData(const ClipboardData(text: kGithubUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          // ---- 头部 ----
          Center(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/icon.png',
                    width: 88,
                    height: 88,
                    errorBuilder: (_, _, _) => Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(Icons.calendar_month, size: 44, color: cs.onPrimaryContainer),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('柳工课表',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('版本 $kAppVersion',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ---- 简介 ----
          _card(
            context,
            child: Text(kIntro,
                style: const TextStyle(fontSize: 12.5, height: 1.7)),
          ),
          const SizedBox(height: 12),

          // ---- 作者 / 交流群 / GitHub ----
          _card(
            context,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _row(
                  context,
                  icon: Icons.person_outline,
                  title: '作者',
                  value: kAuthorName,
                ),
                const Divider(height: 1, indent: 52),
                _row(
                  context,
                  icon: Icons.groups_outlined,
                  title: '交流群',
                  value: kGroupNumber,
                  trailing: const Icon(Icons.copy, size: 16),
                  onTap: () => _copy(context, kGroupNumber, '群号'),
                  hint: '点一下复制群号，到 QQ 里搜索加入',
                ),
                const Divider(height: 1, indent: 52),
                _row(
                  context,
                  icon: Icons.code,
                  title: 'GitHub',
                  value: kGithubUrl.replaceFirst('https://', ''),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: () => _openGithub(context),
                  hint: '点一下用浏览器打开源代码仓库',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---- 免责 ----
          _card(
            context,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.grey[700]),
                    const SizedBox(width: 6),
                    const Text('说明',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '· 课表数据来自学校教务系统，仅供个人查看，不做任何上传\n'
                  '· 本 App 不收集、不上报任何个人信息\n'
                  '· 与学校官方无关，若教务系统改版可能影响导入功能',
                  style: TextStyle(fontSize: 11.5, height: 1.8, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context,
      {required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    Widget? trailing,
    VoidCallback? onTap,
    String? hint,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(width: 14),
            Text(title, style: const TextStyle(fontSize: 13)),
            const Spacer(),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(value,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (trailing != null) ...[const SizedBox(width: 4), trailing],
                    ],
                  ),
                  if (hint != null)
                    Text(hint,
                        style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
