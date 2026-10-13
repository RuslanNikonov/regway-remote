import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../common/widgets/login.dart';
import '../models/platform_model.dart';
import '../models/user_model.dart';
import 'nav.dart';
import 'theme.dart';
import 'updates.dart';
import 'widgets.dart';

class RwMetrics {
  final bool narrow;
  final double sidebar;
  final double rail;
  final double gap;
  final double pad;
  final TextStyle h1;
  const RwMetrics({
    required this.narrow,
    required this.sidebar,
    required this.rail,
    required this.gap,
    required this.pad,
    required this.h1,
  });

  factory RwMetrics.of(BoxConstraints c) {
    final narrow = c.maxWidth <= RwDim.breakNarrow;
    return RwMetrics(
      narrow: narrow,
      sidebar: narrow ? RwDim.sidebarNarrow : RwDim.sidebar,
      rail: narrow ? RwDim.railNarrow : RwDim.rail,
      gap: narrow ? RwDim.gapNarrow : RwDim.gap,
      pad: narrow ? RwDim.padNarrow : RwDim.pad,
      h1: narrow ? RwText.h1Narrow : RwText.h1,
    );
  }
}

class RwShell extends StatelessWidget {
  final RwNavId nav;
  final ValueChanged<RwNavId> onNav;
  final Widget child;
  final Widget? rail;
  const RwShell({
    super.key,
    required this.nav,
    required this.onNav,
    required this.child,
    this.rail,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final m = RwMetrics.of(constraints);
      final p = rwOf(context);
      return Material(
        color: p.bg,
        child: DefaultTextStyle(
          style: p.textBody,
          child: Stack(
            children: [
              const Positioned.fill(child: _CosmicBackdrop()),
              Padding(
                padding: EdgeInsets.all(m.pad),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: m.sidebar,
                      child: RwSidebar(nav: nav, onNav: onNav),
                    ),
                    SizedBox(width: m.gap),
                    Expanded(child: child),
                    if (rail != null) ...[
                      SizedBox(width: m.gap),
                      SizedBox(width: m.rail, child: rail),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _CosmicBackdrop extends StatelessWidget {
  const _CosmicBackdrop();

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    if (!p.cosmicBackdrop) {
      return ColoredBox(color: p.bg);
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: p.bg),
      child: CustomPaint(painter: _CosmicPainter()),
    );
  }
}

class _CosmicPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final top = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x2E7C5CFF), Color(0x0004030B)],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.8, -size.height * 0.08),
        radius: 500,
      ));
    canvas.drawRect(Offset.zero & size, top);
    final bot = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x1AFF7A2F), Color(0x0004030B)],
      ).createShader(Rect.fromCircle(
        center: Offset(0, size.height * 1.05),
        radius: 420,
      ));
    canvas.drawRect(Offset.zero & size, bot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class RwSidebar extends StatelessWidget {
  final RwNavId nav;
  final ValueChanged<RwNavId> onNav;
  const RwSidebar({super.key, required this.nav, required this.onNav});

  @override
  Widget build(BuildContext context) {
    return RwPanel(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 26),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: loadIcon(36),
                ),
                const SizedBox(width: 10),
                const _RwWordmark(),
              ],
            ),
          ),
          _NavItem(
            icon: Icons.desktop_windows_outlined,
            label: translate('Computers'),
            selected: nav == RwNavId.computers,
            onTap: () => onNav(RwNavId.computers),
          ),
          _NavItem(
            icon: Icons.swap_horiz,
            label: translate('Connections'),
            selected: nav == RwNavId.connections,
            onTap: () => onNav(RwNavId.connections),
          ),
          _NavItem(
            icon: Icons.history,
            label: translate('History'),
            selected: nav == RwNavId.history,
            onTap: () => onNav(RwNavId.history),
          ),
          if (!bind.isDisableSettings())
            Obx(() => _NavItem(
              icon: Icons.settings_outlined,
              label: translate('Settings'),
              selected: nav == RwNavId.settings,
              onTap: () => onNav(RwNavId.settings),
              badge: RwUpdates.badge.value,
            )),
          const Spacer(),
          const _ProfileTile(),
        ],
      ),
    );
  }
}

/// Two-line lockup «RegWay» / «Remote», 36px tall, aligned with the 36×36 icon.
class _RwWordmark extends StatelessWidget {
  const _RwWordmark();

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    return SizedBox(
      height: 36,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 18,
            child: Text(
              'RegWay',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontFamily: RwFonts.head,
                fontWeight: FontWeight.w600,
                fontSize: 16,
                height: 18 / 16,
                color: p.text,
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 16,
            child: Text(
              'Remote',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontFamily: RwFonts.head,
                fontWeight: FontWeight.w500,
                fontSize: 12,
                height: 16 / 12,
                letterSpacing: 0.04 * 12,
                color: p.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool badge;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(RwDim.radiusField),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: selected ? p.navOnBg : Colors.transparent,
              borderRadius: BorderRadius.circular(RwDim.radiusField),
              border: Border.all(
                color: selected ? p.navOnBorder : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(icon,
                    size: 18,
                    color: selected ? p.text : p.muted),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    label,
                    style: p.textNav.copyWith(
                      color: selected ? p.text : p.muted,
                    ),
                  ),
                ),
                if (badge) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: p.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile();

  @override
  Widget build(BuildContext context) {
    final p = rwOf(context);
    return Obx(() {
      final loggedIn = gFFI.userModel.isLogin;
      final name = loggedIn
          ? gFFI.userModel.displayNameOrUserName
          : translate('Login');
      final info = UserModel.getLocalUserInfo();
      final email = (info?['email'] ?? '').toString();
      final subtitle = loggedIn
          ? (email.isNotEmpty ? email : gFFI.userModel.userName.value)
          : translate('Sign in to see your computers');
      return InkWell(
        onTap: () async {
          if (loggedIn) {
            logOutConfirmDialog();
          } else {
            await loginDialog();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.cardBorder)),
          ),
          child: Row(
            children: [
              RwAvatar(letter: name),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: p.textBodyStrong.copyWith(fontSize: 13)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: p.textMuted.copyWith(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
