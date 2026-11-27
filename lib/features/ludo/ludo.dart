/// Public surface of the Ludo mode. Embed it in an existing Riverpod app by
/// pushing [LudoHomeScreen] as a route; no other wiring is required beyond
/// Firebase initialisation if online play is wanted.
library;

export 'chat/quick_chat_catalog.dart';
export 'engine/engine.dart';
export 'state/quick_chat_controller.dart';
export 'state/ludo_controller.dart';
export 'ui/ludo_game_screen.dart';
export 'ui/ludo_home_screen.dart';
export 'ui/ludo_lan_menu_screen.dart';
export 'ui/ludo_online_menu_screen.dart';
export 'ui/ludo_online_screen.dart';
export 'ui/ludo_results_screen.dart';
export 'ui/ludo_setup_screen.dart';
export 'ui/ludo_theme.dart';
