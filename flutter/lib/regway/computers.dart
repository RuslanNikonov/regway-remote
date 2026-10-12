import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../common.dart';
import '../common/formatter/id_formatter.dart';
import '../common/widgets/peer_tab_page.dart';
import '../consts.dart';
import '../models/peer_model.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';
import 'nav.dart';
import 'theme.dart';
import 'widgets.dart';

String rwPeerTitle(Peer peer) {
  if (peer.alias.trim().isNotEmpty) return peer.alias.trim();
  if (peer.hostname.trim().isNotEmpty) return peer.hostname.trim();
  if (peer.username.trim().isNotEmpty) return peer.username.trim();
  return formatID(peer.id);
}

String rwPlatformLabel(String platform) {
  switch (platform.toLowerCase()) {
    case 'windows':
      return 'Windows';
    case 'macos':
    case 'osx':
    case 'darwin':
      return 'macOS';
    case 'linux':
      return 'Linux';
    case 'android':
      return 'Android';
    case 'ios':
      return 'iOS';
    default:
      return platform.trim().isEmpty ? '—' : platform;
  }
}

LinearGradient rwWallpaper(Peer peer, [RwPalette? p]) {
  final light = p != null && !p.cosmicBackdrop;
  if (!peer.online) {
    return light ? RwDecor.wallpaperOfflineLight : RwDecor.wallpaperOffline;
  }
  if (peer.id.hashCode.isEven) {
    return light ? RwDecor.wallpaper1Light : RwDecor.wallpaper1;
  }
  return light ? RwDecor.wallpaper2Light : RwDecor.wallpaper2;
}

class RwComputersPage extends StatefulWidget {
  final Widget? helpBanner;
  const RwComputersPage({super.key, this.helpBanner});

  @override
  State<RwComputersPage> createState() => _RwComputersPageState();
}

class _RwComputersPageState extends State<RwComputersPage> {
  final _search = TextEditingController();
  Timer? _onlineTimer;

  @override
  void initState() {
    super.initState();
    bind.mainLoadRecentPeers();
    bind.mainLoadFavPeers();
    gFFI.recentPeersModel.addListener(_onPeers);
    gFFI.favoritePeersModel.addListener(_onPeers);
    _search.addListener(() => setState(() {}));
    _onlineTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _queryOnlines();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _queryOnlines());
  }

  @override
  void dispose() {
    _onlineTimer?.cancel();
    gFFI.recentPeersModel.removeListener(_onPeers);
    gFFI.favoritePeersModel.removeListener(_onPeers);
    _search.dispose();
    super.dispose();
  }

  void _onPeers() {
    if (mounted) setState(() {});
    _queryOnlines();
  }

  void _queryOnlines() {
    final ids = _mergedPeers().map((p) => p.id).where((id) => id.isNotEmpty);
    if (ids.isEmpty) return;
    bind.queryOnlines(ids: ids.toList(growable: false));
  }

  List<Peer> _mergedPeers() {
    final map = <String, Peer>{};
    for (final p in gFFI.favoritePeersModel.peers) {
      map[p.id] = p;
    }
    for (final p in gFFI.recentPeersModel.peers) {
      final prev = map[p.id];
      if (prev == null) {
        map[p.id] = p;
      } else {
        prev.online = prev.online || p.online;
      }
    }
    return map.values.toList();
  }

  List<Peer> _filtered() {
    final q = _search.text.trim().toLowerCase().replaceAll(' ', '');
    final all = _mergedPeers();
    if (q.isEmpty) return all;
    return all.where((p) {
      return p.id.toLowerCase().replaceAll(' ', '').contains(q) ||
          p.alias.toLowerCase().contains(q) ||
          p.hostname.toLowerCase().contains(q) ||
          p.username.toLowerCase().contains(q);
    }).toList();
  }

  void _addComputer() {
    final idCtrl = TextEditingController();
    gFFI.dialogManager.show((setState, close, ctx) {
      submit() {
        final id = idCtrl.text.replaceAll(' ', '');
        close();
        if (id.isEmpty) return;
        connect(context, id);
      }

      final pal = rwOf(ctx);
      return CustomAlertDialog(
        title: Text(translate('Add'), style: pal.textH2),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(translate('Computer ID'), style: pal.textLabel),
            const SizedBox(height: 8),
            RwTextField(
              controller: idCtrl,
              hint: translate('Enter Remote ID'),
              inputFormatters: [IDTextInputFormatter()],
              onSubmitted: (_) => submit(),
            ),
          ],
        ),
        actions: [
          dialogButton('Cancel', onPressed: close, isOutline: true),
          dialogButton('Connect', onPressed: submit),
        ],
        onSubmit: submit,
        onCancel: close,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    final peers = _filtered();
    final recent = gFFI.recentPeersModel.peers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.helpBanner != null) widget.helpBanner!,
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(translate('Computers'), style: p.textH1),
                  const SizedBox(height: 6),
                  Text(translate('Devices of your account'), style: p.textMuted),
                ],
              ),
            ),
            SizedBox(
              width: 210,
              child: RwTextField(
                controller: _search,
                hint: translate('Search by name or ID'),
              ),
            ),
            const SizedBox(width: 10),
            RwButton(label: '+ ${translate('Add')}', onPressed: _addComputer),
          ],
        ),
        const SizedBox(height: 18),
        if (peers.isEmpty)
          RwPanel(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  translate('No computers yet'),
                  style: p.textMuted,
                ),
              ),
            ),
          )
        else
          LayoutBuilder(builder: (context, c) {
            final n = c.maxWidth < 700 ? 2 : 3;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: peers.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: n,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.92,
              ),
              itemBuilder: (_, i) => RwPeerCard(peer: peers[i]),
            );
          }),
        const SizedBox(height: 18),
        Expanded(
          child: RwRecentTable(
            peers: recent,
            onSeeAll: () => RwNav.go(RwNavId.history),
          ),
        ),
      ],
    );
  }
}

class RwPeerCard extends StatelessWidget {
  final Peer peer;
  const RwPeerCard({super.key, required this.peer});

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    final online = peer.online;
    return RwPanel(
      hoverable: true,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              height: 110,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.cardBorder),
                gradient: rwWallpaper(peer, p),
              ),
              alignment: Alignment.center,
              child: online
                  ? null
                  : Icon(Icons.grid_view_rounded,
                      size: 34, color: p.text.withOpacity(0.8)),
            ),
          ),
          const SizedBox(height: 9),
          Text(rwPeerTitle(peer),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: p.textH3),
          const SizedBox(height: 6),
          RwStatusDot(
            online: online,
            label: translate(online ? 'Online' : 'Offline'),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(rwPlatformLabel(peer.platform),
                    style: p.textMuted.copyWith(fontSize: 12.5)),
              ),
              Text(formatID(peer.id),
                  style: p.textNumSm.copyWith(color: p.muted)),
            ],
          ),
          const SizedBox(height: 9),
          RwButton(
            label: translate('Connect'),
            ghost: !online,
            onPressed: online ? () => connect(context, peer.id) : null,
          ),
        ],
      ),
    );
  }
}

class RwRecentTable extends StatelessWidget {
  final List<Peer> peers;
  final VoidCallback onSeeAll;
  const RwRecentTable({super.key, required this.peers, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    return RwPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(translate('Recent connections'), style: p.textH2),
              ),
              RwLink(
                label: '${translate('All connections')} →',
                onTap: onSeeAll,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _header(context),
          Expanded(
            child: peers.isEmpty
                ? Center(
                    child: Text(translate('No recent connections'),
                        style: p.textMuted))
                : ListView.builder(
                    itemCount: peers.length,
                    itemBuilder: (_, i) => _row(context, peers[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final p = rwOf(context);
    TextStyle st = p.textLabel.copyWith(fontSize: 12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.cardBorder)),
      ),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(translate('Device'), style: st)),
          Expanded(flex: 2, child: Text(translate('ID'), style: st)),
          Expanded(flex: 3, child: Text(translate('Date and time'), style: st)),
          Expanded(flex: 2, child: Text(translate('Duration'), style: st)),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Peer peer) {
    final p = rwOf(context);
    return InkWell(
      onTap: peer.online ? () => connect(context, peer.id) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.cardBorder)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 26,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: rwWallpaper(peer, p),
                      border: Border.all(color: p.cardBorder),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rwPeerTitle(peer),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: p.textBodyStrong.copyWith(fontSize: 13)),
                        Text(rwPlatformLabel(peer.platform),
                            style: p.textMuted.copyWith(fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(formatID(peer.id), style: p.textNumSm),
            ),
            Expanded(
              flex: 3,
              child: Text('—', style: p.textNumSm.copyWith(color: p.muted)),
            ),
            Expanded(
              flex: 2,
              child: Text('—', style: p.textNumSm.copyWith(color: p.muted)),
            ),
          ],
        ),
      ),
    );
  }
}

class RwHistoryPage extends StatelessWidget {
  const RwHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(translate('History'), style: p.textH1),
        const SizedBox(height: 6),
        Text(translate('Recent connections'), style: p.textMuted),
        const SizedBox(height: 18),
        Expanded(
          child: RwRecentTable(
            peers: gFFI.recentPeersModel.peers,
            onSeeAll: () {},
          ),
        ),
      ],
    );
  }
}

class RwConnectionsPage extends StatelessWidget {
  const RwConnectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(translate('Connections'), style: p.textH1),
        const SizedBox(height: 6),
        Text(translate('Devices of your account'), style: p.textMuted),
        const SizedBox(height: 18),
        const Expanded(child: PeerTabPage()),
      ],
    );
  }
}

class RwQuickConnect extends StatefulWidget {
  const RwQuickConnect({super.key});

  @override
  State<RwQuickConnect> createState() => _RwQuickConnectState();
}

class _RwQuickConnectState extends State<RwQuickConnect> {
  final _id = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    _id.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _go() {
    final id = _id.text.replaceAll(' ', '');
    if (id.isEmpty) return;
    connect(context, id,
        password: _pass.text.isEmpty ? null : _pass.text);
  }

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    return RwPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(translate('Quick connect'), style: p.textH2),
          const SizedBox(height: 14),
          Text(translate('Computer ID'), style: p.textLabel),
          const SizedBox(height: 6),
          RwTextField(
            controller: _id,
            inputFormatters: [IDTextInputFormatter()],
            onSubmitted: (_) => _go(),
          ),
          const SizedBox(height: 10),
          Text(translate('Password'), style: p.textLabel),
          const SizedBox(height: 6),
          RwTextField(
            controller: _pass,
            obscure: true,
            onSubmitted: (_) => _go(),
          ),
          const SizedBox(height: 16),
          RwButton(label: translate('Connect'), onPressed: _go),
        ],
      ),
    );
  }
}

class RwThisComputer extends StatefulWidget {
  const RwThisComputer({super.key});

  @override
  State<RwThisComputer> createState() => _RwThisComputerState();
}

class _RwThisComputerState extends State<RwThisComputer> {
  bool _hidePass = true;
  Timer? _statusTimer;
  bool _usingPublic = true;
  bool _apiUnreachable = false;

  RxBool get _svcStopped {
    if (Get.isRegistered<RxBool>(tag: 'stop-service')) {
      return Get.find<RxBool>(tag: 'stop-service');
    }
    return Get.put(false.obs, tag: 'stop-service');
  }

  void _refreshLocalFlags() {
    _apiUnreachable =
        bind.mainGetLocalOption(key: 'rw-api-reachable') == 'N';
  }

  @override
  void initState() {
    super.initState();
    _refreshLocalFlags();
    _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        _usingPublic = await bind.mainIsUsingPublicServer();
        _refreshLocalFlags();
        if (mounted) setState(() {});
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Consumer<ServerModel>(
        builder: (context, model, _) {
          return Obx(() {
            final stopped = _svcStopped.value;
            // ServerModel polls bind.mainGetConnectStatus every 500ms.
            // Do not use stateGlobal.svcStatus here: ConnectionPage (which
            // used to write it) is no longer in the redesigned home tree.
            final statusNum = model.connectStatus;
            final connected = !stopped && statusNum == 1;
            final String statusText;
            if (stopped) {
              statusText = translate('Service is not running');
            } else if (statusNum == 1) {
              statusText = translate('Ready');
            } else if (statusNum == -1) {
              statusText = translate('not_ready_status');
            } else {
              statusText = translate('connecting_status');
            }
            final p = rwOf(context);
            return RwPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(translate('This computer'), style: p.textH2),
                  const SizedBox(height: 14),
                  Text(translate('Your ID'), style: p.textLabel),
                  const SizedBox(height: 6),
                  RwTextField(
                    controller: model.serverId,
                    readOnly: true,
                    big: true,
                    suffix: RwIconHit(
                      icon: Icons.copy,
                      tooltip: translate('Copy'),
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: model.serverId.text));
                        showToast(translate('Copied'));
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(translate('Password'), style: p.textLabel),
                  const SizedBox(height: 6),
                  RwTextField(
                    controller: model.serverPasswd,
                    readOnly: true,
                    obscure: _hidePass,
                    big: true,
                    suffix: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RwIconHit(
                          icon: _hidePass
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          tooltip: translate(_hidePass ? 'Show' : 'Hide'),
                          onTap: () =>
                              setState(() => _hidePass = !_hidePass),
                        ),
                        const SizedBox(width: 6),
                        RwIconHit(
                          icon: Icons.copy,
                          tooltip: translate('Copy'),
                          onTap: () {
                            Clipboard.setData(ClipboardData(
                                text: model.serverPasswd.text));
                            showToast(translate('Copied'));
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(translate('Allow incoming'),
                            style: p.textBodyStrong.copyWith(fontSize: 13)),
                      ),
                      RwSwitch(
                        value: !stopped,
                        onChanged: (v) async {
                          await start_service(v);
                        },
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (!stopped && _apiUnreachable)
                    _apiOfflineBanner(p)
                  else
                    _hbbsStatusPlaque(p, connected, statusText),
                ],
              ),
            );
          });
        },
      ),
    );
  }

  Widget _apiOfflineBanner(RwPalette p) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.danger.withOpacity(0.45), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: p.danger,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  translate('No server connection'),
                  style: p.textBodyStrong.copyWith(fontSize: 13, color: p.danger),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            translate(
                'Access closed. It will restore itself when the connection returns'),
            style: p.textMuted.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _hbbsStatusPlaque(RwPalette p, bool connected, String statusText) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: RwStatusDot(online: connected),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${translate('Server')}: $statusText',
                  style: p.textBodyStrong.copyWith(fontSize: 13),
                  maxLines: 3,
                  softWrap: true,
                ),
              ),
            ],
          ),
          if (!_usingPublic) ...[
            const SizedBox(height: 6),
            Text(translate('Encryption on'),
                textAlign: TextAlign.end,
                style: p.textMuted
                    .copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ],
      ),
    );
  }
}

class RwRightRail extends StatelessWidget {
  const RwRightRail({super.key});

  @override
  Widget build(BuildContext context) {
    final outgoing = bind.isOutgoingOnly();
    return Column(
      children: [
        const RwQuickConnect(),
        const SizedBox(height: 18),
        if (!outgoing) const Expanded(child: RwThisComputer()),
      ],
    );
  }
}
