# Ludo mode (2–6 players)

Flutter + Riverpod module for Android and Windows. Same code on both.

## Layout
- `engine/` – pure Dart rules (`LudoEngine`, `BoardLayout`, `LudoBot`). No Flutter, no I/O, dice values are injected.
- `state/ludo_controller.dart` – sequences rolls, animations, bots, autosave, online host/guest.
- `data/` – `LudoStore` (local save), `LudoOnlineRepository` (Firestore), `LudoSound`.
- `ui/` – setup, online lobby, game, results screens; board painter, dice, player cards.

## Boards (each has its own geometry, yards, safe squares, home lanes)
| Players | Board | Arms × length | Track | Notes |
|---|---|---|---|---|
| 2 | Classic cross | 4 × 6, seats on opposite arms | 52 | other arms stay neutral |
| 3 | Classic cross | 4 × 6, one arm empty | 52 | same board as 4 players |
| 4 | Classic cross | 4 × 6 | 52 | teams 2v2 |
| 5 | Pentagon star | 5 × 5 | 55 | wider hub |
| 6 | Hexagon star | 6 × 5 | 66 | teams 3×2 or 2×3 |

Every seat walks the same number of cells on its board (rotational symmetry).

## Embed
```dart
Navigator.push(context, MaterialPageRoute(builder: (_) => const LudoHomeScreen()));
```
The host app needs a `ProviderScope`. `lib/main.dart` is a stand-alone launcher.

## Platform folders
This module has no `android/` or `windows/` yet: run `flutter create . --platforms=android,windows`.

## Online (Firebase)
1. `flutterfire configure` (Android + Windows), then pass `DefaultFirebaseOptions.currentPlatform` to `Firebase.initializeApp` in `main.dart`.
2. Enable **Anonymous** sign-in (Authentication → Get started) and create a Firestore database.
3. Publish `firestore.rules`.

Online menu:
- **Quick Start** – pick the player count and rules; you are matched only with players whose player count, team layout and every rule are identical (`MatchCriteria.key`). When the last seat is taken the lobby host starts the game automatically.
- **Create Room** – private room with your own settings and a 6-character code. The creator is the host and can start the match once every seat is taken by a real player.
- **Join Room** – enter a code.

How Quick Start works (no server code): a Quick Start lobby is a public room tagged with the match key. A searcher joins the oldest open lobby with the same key, otherwise creates one. Seat counts change inside Firestore transactions, so the last seat can't be double-booked. Lobbies carry a host heartbeat (stale ones are ignored), and a host who is still alone merges into an older matching lobby, so two simultaneous searchers always end up together.

The host's device is the authority during play: guests only write roll/move "intents"; the host validates them with `LudoEngine` and publishes the new state. If the host leaves, the room closes.

### Players who leave or stop responding
Online seats are only ever held by real players: there are no bots in online games, and a room never starts until every seat is filled.

- **Leaving on purpose** (`LudoOnlineRepository.leaveGame`) and **missing 3 turns in a row** (`LudoEngine.maxMissedTurns`, counted in `GameState.missed`) both end in `LudoEngine.removeSeat`: the player's tokens are removed from the board, the seat is marked `SeatPresence.left` or `SeatPresence.inactive` and skipped from then on.
- The removal is part of the shared game state, so every remaining device notices it from the state change and shows a notice ("X left the game" / "X was removed for missing 3 turns in a row"). The removed player is told too and sent back to the menu.
- A move the player makes resets their counter; a timed-out roll or an auto-played move counts as a miss.
- When only one team is still in play the game ends and that team wins; players who left are ranked last. If everybody is gone the room is closed.

## Hotspot / Wi-Fi multiplayer (no internet)

Home > **Hotspot / Wi-Fi**. One player taps **Host a game** (same rule options as an online private room) and turns on a mobile hotspot, or everyone joins the same Wi-Fi. Other players tap **Join a game**; rooms on the network are listed automatically, and a host address (`ip:45679`) can be typed if a room is not listed. The lobby has the same host controls as online private rooms: add a bot (Easy / Medium / Hard) to an open seat, and remove bots or joined players.

How it works (`data/lan_backend.dart`, no Firebase involved): the host's device runs a WebSocket server and is the authority for the room; it announces the lobby with UDP broadcasts on port 45678. Guests connect over WebSocket. If the host leaves a running game, the host's seat is taken out and the room keeps serving the others until the last guest leaves. If the host's app is closed, guests are told the connection was lost.

Notes: Android needs the `INTERNET` permission in the main manifest (already required by Firebase). Some routers isolate Wi-Fi clients or block broadcasts; then use a phone hotspot or type the host address. On Windows, allow the app through the firewall on private networks.

## Quick chat (online and Wi-Fi games)

Players in an online or Wi-Fi game can send a short preset message or an emoji. A speech bubble grows out of the sender's yard on every player's board, stays for 4 seconds, and fades away. A new message from the same player replaces their bubble straight away and restarts the 4 seconds. Local and vs-AI games have no chat. Open it from the speech-bubble button in the game's app bar.

**Adding messages or emojis** - add one line to `QuickChatCatalog.items` in `chat/quick_chat_catalog.dart`:
```dart
QuickChatItem('rematch', text: 'Rematch?', emoji: '🔁', category: QuickChatCategory.message),
QuickChatItem('party',   emoji: '🥳',                    category: QuickChatCategory.reaction),
```
The picker, the bubbles and both backends pick it up with no other change. Never rename or reuse the `id` of a shipped item: only the id travels over the network, so text can be reworded or translated freely. A client that gets an id it does not know ignores it. A new `QuickChatCategory` value adds a new section to the picker. Bubble time and the send cooldown live in `QuickChatConfig`.

How it works:
- `state/quick_chat_controller.dart` - `quickChatProvider` holds at most one bubble per seat. `LudoController` attaches it when an online game starts (`attachOnline`) and detaches it when the game ends.
- `ui/quick_chat_bubble.dart` - `QuickChatBubbleLayer`, drawn by `LudoBoardView` above the tokens; each bubble is anchored at its seat's yard and kept inside the board. `ui/quick_chat_sheet.dart` - the picker.
- Chat is separate from the game state, so it never touches the move version counter. Backends: `RoomBackend.sendQuickChat` / `watchQuickChat`.
  - **Online (Firestore):** one document per player at `ludo_rooms/{code}/chat/{uid}` that each message overwrites, so a room never builds up chat history. It is removed with the room. **Publish the updated `firestore.rules`**, which add the `chat` rule.
  - **Wi-Fi:** a `chat` WebSocket message. The host checks it, takes the sender from the connection, drops floods, and relays it to everyone.
- The sender sees their own bubble the same way everyone else does (the event comes back through the backend), so what you see is what they see.

Tests: `test/quick_chat_test.dart`.

## Tests
`flutter test` – quick chat (`test/quick_chat_test.dart`), layout checks for 2–6 players, rule cases, JSON round-trip, full bot games for every layout and team preset, and `test/ludo_presence_test.dart` (leaving, 3-timeout removal, team games, randomized games with departures).

## Board themes & customisation

The theme picker (palette button on the home screen) offers 14 board themes —
Classic, Ocean, Forest, Midnight, Wooden, Candy, Desert, Neon, Frost, Royal,
Blueprint, Galaxy, Lava and Arcade. Each one defines its own surface texture,
frame, track cell shape/depth, safe-cell marker, home-lane decoration, yard
shape, token slots and centre hub (see `BoardStyle.all` in `ui/ludo_style.dart`).

On top of a theme the player can override cell shape, depth, marker, lane
style, an optional road under the path, cell size, yard shape, token slots,
surface pattern, frame, and the board / frame / track colours. Overrides are
stored as a small JSON map (`BoardCustom`) and survive restarts.

To add a theme, append a `BoardStyle` to `BoardStyle.all`; to add a new shape
or pattern, extend the matching enum and handle it in `ui/board_painter.dart`.

### Dice styles

The picker also has a **Dice** section next to Tokens: Classic, Player (tinted
with the current player's colour), Neon, Wooden, Gold, Ice, Candy, Pixel and
Royal. A **Pip shape** tweak (Round / Square / Diamond / Star) in *Customise ›
Dice* overrides the pips of whichever dice is selected. The choice is saved with
the other style settings (`ludo.diceStyle`).

To add a dice style, append a value to `DiceStyle` (the index is persisted, so
only ever append) and a matching `DiceSkin` at the same position in
`DiceSkin._all` (`ui/ludo_style.dart`). `DiceFace` in `ui/dice_widget.dart`
renders a skin both in the game and in the picker.

### Safe-cell stars under tokens

A token is nearly as large as a cell, so it would hide the star printed on a
safe cell. While a token stands on a star or start cell, `LudoBoardView` draws a
larger gold star with a soft glow *under* the token (`SafeCellGlowPainter`), so
the star's points stay visible around the token. Nothing is drawn on top of the
token. It pops in as the token lands.

## Online room cleanup

Rooms are deleted from the client (no Cloud Functions / TTL, so the free Spark
plan is enough). The host deletes a room when it closes it, and after a game
the last player to leave deletes it together with its `members` and `intents`
sub-collections. Rooms abandoned by a crashed or force-closed app can't clean
themselves up and stay until removed manually. Deploy the updated
`firestore.rules` (`firebase deploy --only firestore:rules`) for this to work.
