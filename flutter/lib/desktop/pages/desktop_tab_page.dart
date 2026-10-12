import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/regway/login_view.dart';
import 'package:flutter_hbb/regway/nav.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../../common/shared_state.dart';

class DesktopTabPage extends StatefulWidget {
  const DesktopTabPage({Key? key}) : super(key: key);

  @override
  State<DesktopTabPage> createState() => _DesktopTabPageState();

  static void onAddSetting(
      {SettingsTabKey initialPage = SettingsTabKey.general}) {
    if (!gFFI.userModel.isLogin) return;
    if (!bind.isIncomingOnly()) {
      RwNav.go(RwNavId.settings);
      try {
        if (Get.isRegistered<PageController>(tag: 'settingPageController') &&
            Get.isRegistered<Rx<SettingsTabKey>>(tag: 'settingPageTabKey')) {
          final index = DesktopSettingPage.tabKeys.indexOf(initialPage);
          if (index != -1) {
            Get.find<PageController>(tag: 'settingPageController')
                .jumpToPage(index);
            Get.find<Rx<SettingsTabKey>>(tag: 'settingPageTabKey').value =
                initialPage;
          }
        }
      } catch (e) {
        debugPrintStack(label: '$e');
      }
      return;
    }
    try {
      DesktopTabController tabController = Get.find<DesktopTabController>();
      tabController.add(TabInfo(
          key: kTabLabelSettingPage,
          label: kTabLabelSettingPage,
          selectedIcon: Icons.build_sharp,
          unselectedIcon: Icons.build_outlined,
          page: DesktopSettingPage(
            key: const ValueKey(kTabLabelSettingPage),
            initialTabkey: initialPage,
          )));
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopTabPageState extends State<DesktopTabPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);
  Worker? _loginGateWorker;

  _DesktopTabPageState() {
    RemoteCountState.init();
    Get.put<DesktopTabController>(tabController);
    tabController.add(TabInfo(
        key: kTabLabelHomePage,
        label: kTabLabelHomePage,
        selectedIcon: Icons.home_sharp,
        unselectedIcon: Icons.home_outlined,
        closable: false,
        page: DesktopHomePage(
          key: const ValueKey(kTabLabelHomePage),
        )));
    if (bind.isIncomingOnly()) {
      tabController.onSelected = (key) {
        if (key == kTabLabelHomePage) {
          windowManager.setSize(getIncomingOnlyHomeSize());
          setResizable(false);
        } else {
          windowManager.setSize(getIncomingOnlySettingsSize());
          setResizable(true);
        }
      };
    }
  }

  @override
  void initState() {
    super.initState();
    _loginGateWorker = ever(gFFI.userModel.userName, (name) {
      if (name.toString().isEmpty && isDesktop) {
        rustDeskWinManager.closeAllSubWindows();
      }
    });
  }

  @override
  void dispose() {
    _loginGateWorker?.dispose();
    Get.delete<DesktopTabController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabWidget = Container(
        child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.background,
            body: DesktopTab(
              controller: tabController,
              tail: const Offstage(
                offstage: true,
                child: SizedBox.shrink(),
              ),
            )));
    final framed = isMacOS || kUseCompatibleUiMode
        ? tabWidget
        : Obx(
            () => DragToResizeArea(
              resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
              enableResizeEdges: windowManagerEnableResizeEdges,
              child: tabWidget,
            ),
          );
    return Stack(
      children: [
        framed,
        Obx(() {
          if (gFFI.userModel.isLogin) {
            return const SizedBox.shrink();
          }
          return const Positioned.fill(child: RwLoginPage());
        }),
      ],
    );
  }
}
