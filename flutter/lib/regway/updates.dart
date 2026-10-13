import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../common.dart';
import '../models/platform_model.dart';
import 'theme.dart';
import 'widgets.dart';

/// Badge on Настройки when an update is waiting (v4 / v4.1).
class RwUpdates {
  RwUpdates._();
  static final badge = false.obs;
  static final status = <String, dynamic>{}.obs;

  static void ingest(Map<String, dynamic> st) {
    status.assignAll(st);
    final s = st['state']?.toString() ?? '';
    badge.value = s == 'available' || s == 'ready' || s == 'downloading';
  }
}

class RwUpdatesPage extends StatefulWidget {
  const RwUpdatesPage({super.key});

  @override
  State<RwUpdatesPage> createState() => _RwUpdatesPageState();
}

class _RwUpdatesPageState extends State<RwUpdatesPage> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    bind.mainSetCommon(key: 'rw-update-check', value: '1');
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _refresh() {
    try {
      final raw = bind.mainGetCommonSync(key: 'rw-update-status');
      if (raw.isEmpty) return;
      final st = jsonDecode(raw);
      if (st is Map<String, dynamic>) {
        RwUpdates.ingest(st);
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Map<String, dynamic> get _st => Map<String, dynamic>.from(RwUpdates.status);

  String get _state => _st['state']?.toString() ?? 'idle';
  String get _mode => _st['mode']?.toString() ?? 'auto';
  int get _progress => int.tryParse('${_st['progress'] ?? 0}') ?? 0;
  bool get _resuming => _st['resuming'] == true;
  String get _error => _st['error']?.toString() ?? '';
  String get _version => _st['version']?.toString() ?? '';
  bool get _rollback => _st['rollback_allowed'] != false;

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    final failed = _state == 'error' && _error == 'download-failed';
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      children: [
        Text(translate('Updates'), style: p.textH2),
        const SizedBox(height: 6),
        Text(
          translate('Signed updates from remote.regway.group'),
          style: p.textMuted,
        ),
        const SizedBox(height: 18),
        RwPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(translate('Mode'), style: p.textLabel),
              const SizedBox(height: 10),
              Row(
                children: [
                  _modeChip(p, 'auto', translate('Auto')),
                  const SizedBox(width: 8),
                  _modeChip(p, 'manual', translate('Manual')),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _mode == 'auto'
                    ? translate(
                        'In Auto mode installation starts only after the active session ends')
                    : translate('In Manual mode you install the update yourself'),
                style: p.textMuted.copyWith(fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        RwPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _version.isEmpty
                    ? translate('You have the latest version')
                    : '${translate('Version')} $_version',
                style: p.textH3,
              ),
              const SizedBox(height: 8),
              if (_state == 'downloading')
                Text(
                  '${translate('Downloading…')} $_progress % · ${translate('resume after drop')}',
                  style: p.textMuted,
                ),
              if (_state == 'ready')
                Text(translate('Ready to install'), style: p.textMuted),
              if (_state == 'checking')
                Text(translate('Checking for updates…'), style: p.textMuted),
              if (failed)
                Text(
                  translate(
                      'Could not download the update. Check your connection'),
                  style: p.textError,
                ),
              if (_state == 'error' && !failed && _error.isNotEmpty)
                Text(_error, style: p.textError),
              if (!_rollback) ...[
                const SizedBox(height: 8),
                Text(
                  translate('This version cannot be rolled back to'),
                  style: p.textMuted.copyWith(fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  if (_state == 'available' || _state == 'idle' || _state == 'error')
                    RwButton(
                      label: translate('Check'),
                      ghost: true,
                      onPressed: () => bind.mainSetCommon(
                          key: 'rw-update-check', value: '1'),
                    ),
                  if (_state == 'available') ...[
                    const SizedBox(width: 8),
                    RwButton(
                      label: translate('Download'),
                      onPressed: () => bind.mainSetCommon(
                          key: 'rw-update-download', value: '1'),
                    ),
                  ],
                  if (_state == 'ready')
                    RwButton(
                      label: translate('Install'),
                      onPressed: () => bind.mainSetCommon(
                          key: 'rw-update-install', value: '1'),
                    ),
                  if (failed) ...[
                    const SizedBox(width: 8),
                    RwButton(
                      label: translate('Retry'),
                      onPressed: () => bind.mainSetCommon(
                          key: 'rw-update-retry', value: '1'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => launchUrlString(
                      'https://remote.regway.group/help/#updates'),
                  child: Text(translate('Help'), style: p.textLink),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _modeChip(RwPalette p, String id, String label) {
    final on = _mode == id;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      onSelected: (_) {
        bind.mainSetCommon(key: 'rw-update-mode', value: id);
        _refresh();
      },
      selectedColor: p.accent.withOpacity(0.18),
      labelStyle: TextStyle(
        fontFamily: RwFonts.body,
        fontWeight: FontWeight.w600,
        color: on ? p.accent : p.muted,
      ),
      side: BorderSide(color: on ? p.accent.withOpacity(0.45) : p.cardBorder),
      backgroundColor: p.card,
    );
  }
}
