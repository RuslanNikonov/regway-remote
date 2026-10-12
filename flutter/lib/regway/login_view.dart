import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common.dart';
import '../common/hbbs/hbbs.dart';
import '../common/widgets/login.dart';
import '../models/platform_model.dart';
import '../models/user_model.dart';
import 'nav.dart';
import 'theme.dart';
import 'widgets.dart';

class RwLoginPage extends StatelessWidget {
  final VoidCallback? onSkip;
  const RwLoginPage({super.key, this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: RwColors.bg,
      child: Stack(
        children: [
          const Positioned.fill(child: _LoginBackdrop()),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: RwLoginCard(onSkip: onSkip),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _LoginPainter());
  }
}

class _LoginPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = RwColors.bg);
    final a = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x477C5CFF), Color(0x0004030B)],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.2, size.height * 0.2),
        radius: 420,
      ));
    canvas.drawRect(Offset.zero & size, a);
    final b = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x2E38D9FF), Color(0x0004030B)],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.85, size.height * 0.85),
        radius: 380,
      ));
    canvas.drawRect(Offset.zero & size, b);
    final star = Paint()..color = const Color(0x66FFFFFF);
    for (final p in const [
      Offset(0.10, 0.30),
      Offset(0.70, 0.15),
      Offset(0.40, 0.80),
      Offset(0.90, 0.50),
    ]) {
      canvas.drawCircle(
          Offset(size.width * p.dx, size.height * p.dy), 1.1, star);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class RwLoginCard extends StatefulWidget {
  final VoidCallback? onSkip;
  final void Function(bool ok)? onFinished;
  const RwLoginCard({super.key, this.onSkip, this.onFinished});

  @override
  State<RwLoginCard> createState() => _RwLoginCardState();
}

class _RwLoginCardState extends State<RwLoginCard> {
  late final TextEditingController username;
  late final TextEditingController password;
  final userFocus = FocusNode();
  bool hidePass = true;
  bool remember = true;
  bool inProgress = false;
  String? usernameMsg;
  String? passwordMsg;
  final oidcAuth = _LoginOidc();
  final loginOptions = <dynamic>[].obs;

  @override
  void initState() {
    super.initState();
    username = TextEditingController(
        text: UserModel.getLocalUserInfo()?['name'] ?? '');
    password = TextEditingController();
    username.addListener(() {
      if (usernameMsg != null) setState(() => usernameMsg = null);
    });
    password.addListener(() {
      if (passwordMsg != null) setState(() => passwordMsg = null);
    });
    Timer(const Duration(milliseconds: 80), () {
      if (mounted) userFocus.requestFocus();
    });
    UserModel.queryOidcLoginOptions().then((ops) {
      if (mounted) loginOptions.value = ops;
    }).catchError((_) {});
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    userFocus.dispose();
    oidcAuth.close();
    super.dispose();
  }

  Future<void> _onLogin() async {
    if (inProgress || oidcAuth.curOP.value.isNotEmpty) return;
    if (username.text.isEmpty) {
      setState(() => usernameMsg = translate('Username missed'));
      return;
    }
    if (password.text.isEmpty) {
      setState(() => passwordMsg = translate('Password missed'));
      return;
    }
    oidcAuth.curOP.value = 'rustdesk';
    setState(() => inProgress = true);
    try {
      final resp = await gFFI.userModel.login(LoginRequest(
        username: username.text,
        password: password.text,
        id: await bind.mainGetMyId(),
        uuid: await bind.mainGetUuid(),
        autoLogin: remember,
        type: HttpType.kAuthReqTypeAccount,
      ));
      if (resp.type == HttpType.kAuthResTypeToken &&
          resp.access_token != null) {
        await bind.mainSetLocalOption(
            key: 'access_token', value: resp.access_token!);
        await bind.mainSetLocalOption(
            key: 'user_info', value: jsonEncode(resp.user ?? {}));
        await UserModel.updateOtherModels();
        widget.onFinished?.call(true);
        return;
      }
      passwordMsg = translate('Login Error');
    } on RequestException catch (err) {
      passwordMsg = translate(err.cause);
    } catch (err) {
      passwordMsg = '$err';
    }
    oidcAuth.curOP.value = '';
    if (mounted) setState(() => inProgress = false);
  }

  @override
  Widget build(BuildContext context) {
    return RwPanel(
      width: 420,
      padding: const EdgeInsets.fromLTRB(36, 36, 36, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: loadIcon(64),
            ),
          ),
          const SizedBox(height: 12),
          Text(bind.mainGetAppNameSync(),
              textAlign: TextAlign.center, style: RwText.h1.copyWith(fontSize: 22)),
          const SizedBox(height: 6),
          Text(translate('Sign in to see your computers'),
              textAlign: TextAlign.center, style: RwText.muted),
          const SizedBox(height: 22),
          Text(translate('Email or login'), style: RwText.label),
          const SizedBox(height: 6),
          RwTextField(
            controller: username,
            focusNode: userFocus,
            hint: translate('Email or login'),
            errorText: usernameMsg,
            onSubmitted: (_) => _onLogin(),
          ),
          const SizedBox(height: 12),
          Text(translate('Password'), style: RwText.label),
          const SizedBox(height: 6),
          RwTextField(
            controller: password,
            hint: translate('Password'),
            obscure: hidePass,
            errorText: passwordMsg,
            onSubmitted: (_) => _onLogin(),
            suffix: RwLink(
              label: translate(hidePass ? 'Show' : 'Hide'),
              onTap: () => setState(() => hidePass = !hidePass),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => remember = !remember),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: Checkbox(
                          value: remember,
                          activeColor: RwColors.accent,
                          checkColor: RwColors.onAccent,
                          side: const BorderSide(color: RwColors.muted),
                          onChanged: (v) =>
                              setState(() => remember = v ?? true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(translate('Remember me'),
                            style: RwText.muted.copyWith(fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
              ),
              RwLink(
                label: translate('Forgot password?'),
                fontSize: 12.5,
                onTap: () async {
                  final url = await bind.mainGetApiServer();
                  final uri = Uri.tryParse(url);
                  if (uri != null) {
                    await launchUrl(uri);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (inProgress)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(
                color: RwColors.accent,
                backgroundColor: RwColors.toggleOff,
              ),
            ),
          Obx(() => RwButton(
                label: translate('Login'),
                onPressed: oidcAuth.curOP.value.isEmpty && !inProgress
                    ? _onLogin
                    : null,
              )),
          const SizedBox(height: 12),
          Center(
            child: RwLink(
              label: translate('Work without signing in'),
              onTap: () async {
                await RwNav.workWithoutLogin();
                widget.onSkip?.call();
                widget.onFinished?.call(false);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginOidc {
  final curOP = ''.obs;
  void close() {
    curOP.value = '';
  }
}
