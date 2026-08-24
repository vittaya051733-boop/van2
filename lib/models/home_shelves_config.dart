import 'home_page_lock_config.dart';
import 'home_quick_action_config.dart';

class HomeShelvesConfig {
  const HomeShelvesConfig({
    required this.quickActions,
    required this.homeLock,
  });

  static const HomeShelvesConfig defaults = HomeShelvesConfig(
    quickActions: HomeQuickActionConfig.defaults,
    homeLock: HomePageLockConfig.defaults,
  );

  final HomeQuickActionConfig quickActions;
  final HomePageLockConfig homeLock;

  factory HomeShelvesConfig.fromFirestore(Map<String, dynamic>? data) {
    return HomeShelvesConfig(
      quickActions: HomeQuickActionConfig.fromFirestore(data),
      homeLock: HomePageLockConfig.fromFirestore(data),
    );
  }

  String get signature =>
      '${quickActions.signature}||${homeLock.signature}';
}
