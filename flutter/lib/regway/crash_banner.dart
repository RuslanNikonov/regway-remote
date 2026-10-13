import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../common.dart';
import '../models/platform_model.dart';
import 'theme.dart';

/// C12: next-launch banner after a recorded crash.
class RwCrashBanner extends StatefulWidget {
  const RwCrashBanner({super.key});

  @override
  State<RwCrashBanner> createState() => _RwCrashBannerState();
}

class _RwCrashBannerState extends State<RwCrashBanner> {
  bool _show = false;
  String _path = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pending = bind.mainGetCommonSync(key: 'rw-crash-pending');
      final path = bind.mainGetCommonSync(key: 'rw-crash-log-path');
      if (pending == 'Y' && mounted) {
        setState(() {
          _show = true;
          _path = path;
        });
      }
    } catch (_) {}
  }

  void _dismiss() {
    bind.mainSetCommon(key: 'rw-crash-ack', value: '1');
    setState(() => _show = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final p = rwOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.danger.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: p.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              translate(
                  'The app was closed because of an error. A report was saved'),
              style: p.textBodyStrong.copyWith(fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () async {
              if (_path.isEmpty) return;
              final uri = Uri.file(_path);
              if (await canLaunchUrlString(uri.toString())) {
                await launchUrlString(uri.toString());
              } else {
                try {
                  await Process.run(
                      Platform.isWindows ? 'explorer' : 'open', [_path]);
                } catch (_) {}
              }
            },
            child: Text(translate('Show file'), style: p.textLink),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: p.muted),
            onPressed: _dismiss,
          ),
        ],
      ),
    );
  }
}
