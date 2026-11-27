import '../engine/engine.dart';
import '../state/ludo_controller.dart';

/// Whether [seat] is the player sitting at this device ("you").
///
///  * Online / LAN: the seat that belongs to this device.
///  * Local and vs-AI games: when exactly one seat is human, that seat is you
///    (everybody else is a bot). With several humans sharing the device
///    (pass-and-play) nobody is "you".
bool isMySeat(LudoUiState ui, int seat) {
  final game = ui.game;
  if (game == null) return false;
  if (ui.mode == GameMode.online) return ui.mySeat == seat;
  final seats = game.config.seats;
  if (seat < 0 || seat >= seats.length || seats[seat].isBot) return false;
  final humans = seats.where((s) => !s.isBot).length;
  return humans == 1;
}

/// Whether the team [team] contains the player at this device.
bool isMyTeam(LudoUiState ui, int team) {
  final game = ui.game;
  if (game == null) return false;
  for (var i = 0; i < game.config.playerCount; i++) {
    if (game.config.teams[i] == team && isMySeat(ui, i)) return true;
  }
  return false;
}