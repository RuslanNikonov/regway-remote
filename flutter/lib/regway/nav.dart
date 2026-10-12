import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

import '../models/model.dart';

enum RwNavId { computers, connections, history, settings }

const kRwSkipLoginOption = 'rw-skip-login';

class RwNav {
  RwNav._();

  static final selected = RwNavId.computers.obs;
  static final skipLogin = false.obs;

  static void go(RwNavId id) => selected.value = id;

  static bool get skippedLogin {
    if (skipLogin.value) return true;
    try {
      return bind.mainGetLocalOption(key: kRwSkipLoginOption) == 'Y';
    } catch (_) {
      return false;
    }
  }

  static Future<void> workWithoutLogin() async {
    skipLogin.value = true;
    try {
      await bind.mainSetLocalOption(key: kRwSkipLoginOption, value: 'Y');
    } catch (_) {}
  }

  static bool get shouldShowLogin {
    try {
      if (gFFI.userModel.isLogin) return false;
    } catch (_) {
      return false;
    }
    return !skippedLogin;
  }
}
