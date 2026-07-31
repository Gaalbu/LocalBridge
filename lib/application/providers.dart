import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bridge_controller.dart';

final bridgeControllerProvider = ChangeNotifierProvider<BridgeController>((
  ref,
) {
  final controller = BridgeController();
  controller.initialize();
  return controller;
});
