# Keyboard Bar

An on-screen keyboard that doubles as your action bar, for **World of Warcraft Forever** (client 1.60.1,
interface `16001`). Every key on screen is an action slot: drop a spell, item or macro on a key and pressing that
key on your real keyboard (or clicking it) uses it. It replaces the Blizzard action bars.

> Status: active development. Built and tested against WoW Forever; other clients are untested.

## Features

- **Keyboard as the bar.** Main block, navigation cluster and numpad, drawn like a real keyboard. Drag spells,
  items and macros onto keys; click or press to use them. Right-click uses a key (on release); right-hold and
  drag moves it.
- **Game keys show up too.** Existing game bindings (map, bags, talents, sit, movement...) appear on their keys
  with icons. Drag them to other keys to rebind. When you put an ability on a key that has a game binding, the
  binding is moved to the Alt version of that key and returns when the key is free again.
- **View cycle.** One key cycles Full -> Bound -> Play -> Cooldowns. Collapsed views hide empty keys; rows and the
  three sections (main / nav / numpad) collapse independently. The layout is combat-safe: it is rearranged by
  secure code, so views and layers change in combat.
- **Shift / Ctrl / Alt layers.** Hold a modifier to see and use that layer's mappings. Optional: keep the base
  layout while a modifier is held, and show a key's modifier mappings as small icons along its bottom edge.
- **Cooldown tray, key effects.** A tray shows only what is cooling down. Optional effects: new-ability sparkle,
  new-rank sparkle, cooldown-ready flash, out-of-range / out-of-mana flash, active-spell glow.
- **Auto-place and Fill.** Newly learned abilities go on the first free key (top-down or bottom-up); `/kb fill`
  places every missing class ability and racial.
- **Icon grid.** An optional, separate, draggable X-by-Y pane of click-only slots (no key bindings) for things
  you only click. It follows the keyboard's size, style and view cycle.
- **Extras.** Profession skill numbers (`45/75`) on profession keys, a gathering-node tooltip pane for
  Herbalism and Mining (skill needed, skill-up color arrows), mana cost on spells, item counts with graying at
  zero, per-character profiles, and a built-in debug log.

## Install

1. Copy this folder into `World of Warcraft/_forever_/Interface/AddOns/` **and name it `KeyboardBar`**
   (the folder name must match `KeyboardBar.toc`):

   ```
   git clone <repo-url> "<WoW>/_forever_/Interface/AddOns/KeyboardBar"
   ```

2. Start the game (or `/reload`) and make sure *Keyboard Bar* is enabled on the character select AddOns screen.

For development, a directory junction from the AddOns folder to your working copy keeps the two in sync:

```
mklink /J "<WoW>\_forever_\Interface\AddOns\KeyboardBar" "<path to this repo>"
```

## Using it

| Do this | To |
|---|---|
| Drag from the spellbook, bags or macros onto a key | Map it |
| Left-click / press the key | Use it |
| Right-click an empty-handed key | Use it (on release) |
| Right-hold and drag | Move or swap it; let go off the keys to remove it |
| Pick something up, then right-click or left-click a key | Drop / swap it there |
| Shift + right-click a key | Clear it |
| Middle-click a game-bound key | Unbind the game binding |
| `~` (the Cycle key) | Cycle the view |

## Slash commands

`/kb` opens the settings window (tabs: Layout, Behavior, Effects, Grid, Profile). Others:

| Command | Does |
|---|---|
| `/kb` | Open the settings pane for keyboard bars |
| `/kb fill` | Place every missing class ability and racial on free keys |

| `/kb toggle` | Show / hide the keyboard |
| `/kb bars` | Hide the Blizzard action bars (reload to undo) |
| `/kb grid` | Show / hide the icon grid |
| `/kb nav`, `/kb numpad` | Toggle the navigation cluster / numpad |
| `/kb cyclekey <KEY\|off>` | Choose the view-cycle key |
| `/kb profile [name]` | Show or switch profile |
| `/kb reset` | Clear every key in the current profile |
| `/kb whoami` | Show the character name / profile this addon sees |
| `/kb scale <n>`, `/kb gap [tight\|normal\|loose]`, `/kb sizes`, `/kb style` | Quick layout changes |
| `/kb view [full\|bound\|assigned\|cooldown]` | Set or cycle the view |
| `/kb layout\|behavior\|effects\|profiles` | Open that settings tab |
| `/kb debug`, `/kb snapshot`, `/kb clearlog` | Debug log tools (written to SavedVariables on `/reload`) |

## Notes

- Settings are account-wide; keys and the grid contents belong to the current profile, and each character starts
  on its own profile.
- Spells are stored by name, so a key always uses your highest known rank.
- Many details (skill-up color ranges, the racial list) come from Classic-era data and may need adjusting for
  other client versions.
