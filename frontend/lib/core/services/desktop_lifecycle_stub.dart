class DesktopLifecycleService {
  DesktopLifecycleService._();

  static final DesktopLifecycleService instance = DesktopLifecycleService._();

  String? get notificationIconPath => null;

  Future<void> initialize({bool startHidden = false}) async {}

  Future<void> showWindow() async {}
}
