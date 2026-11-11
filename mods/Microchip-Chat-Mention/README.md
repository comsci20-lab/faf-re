# Microchip Chat Mention

UI-only mod for the current FAF ChatController. It watches your actual local player name and optional extra nicknames. Mentions match literal whole names without caring about ASCII case, so `chip` does not match `microchip`. Non-ASCII names match literally; Unicode case folding is not provided.

The sender and original message slide down below the top HUD. Each popup stays for **10 seconds** by default, with a countdown, shrinking timer bar and corner **X**. The timer uses real time, including while the simulation is paused. Up to five additional mentions queue behind the current popup; a larger burst drops the oldest waiting message.

Enable the mod in the FAF mod manager. Open **UI Mods Options > Microchip Chat Mention** (UI Mod Tools), or press **Ctrl+Shift+M** without UI Mod Tools. Enter comma-separated nicknames and a duration of **1–120 seconds**, then Save. Settings persist in your current player profile. Duration changes apply to future mentions. Test Popup previews the draft duration without saving it.

Only received chat already accepted by FAF is eligible. Muted messages, outgoing messages, system notifications and camera/location links do not trigger popups. This mod does not send chat or change the simulation. It chains the same ChatController hooks as Microchip Offline Chat Translation.

Extract the distributed ZIP into your FAF user `mods` directory, keeping the `Microchip-Chat-Mention` folder intact. Restart the game after enabling the mod. The GIF is an illustrative mockup, not captured gameplay.
