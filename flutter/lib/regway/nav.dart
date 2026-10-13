import 'package:get/get.dart';

enum RwNavId { computers, connections, history, settings }

class RwNav {
  RwNav._();

  static final selected = RwNavId.computers.obs;

  static void go(RwNavId id) => selected.value = id;
}
