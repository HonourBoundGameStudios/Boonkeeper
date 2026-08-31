# Boonkeeper

**How much buff room is left on the people you are about to heal.**

World of Warcraft Classic Era holds **32 buffs** on a player. Past that, the *oldest* one falls off —
which is how a reflex Renew costs somebody the Rallying Cry they spent an evening collecting. There
is no way to see that coming in the default UI, and counting a raider's buff icons mid-fight is not
a thing anyone has time for.

Boonkeeper puts the number where you are already looking, before you cast.

- **A live slot count** on the units you heal — `28/32` — so "is there room" is a glance, not a count.
- **Louder as it gets tighter**, quiet when it doesn't matter.
- **Knows what's actually at stake.** A world buff near the cap is a different warning from a full
  bar of flasks. A raider who has stored their buffs in a Chronoboon is safe, and is told so.
- **Never guesses.** If the client will not show us a unit's auras, Boonkeeper shows `?` — not a
  number it cannot stand behind.

## Status

Early. The pure judgement (counts, headroom, severity, what is at risk) is written and covered by
57 offline assertions; the on-screen display is not built yet. `/boon probe` is in first, because
everything rests on one thing the documentation cannot settle: exactly how much of another player's
aura list the client will hand an addon. That gets answered in a raid before a number goes on screen.

## Install

Copy the `Boonkeeper` folder into `World of Warcraft\_classic_era_\Interface\AddOns\`, or run
`./deploy.ps1`.

## Commands

| | |
|---|---|
| `/boon probe` | Dump what aura data this client will actually give us |
| `/boon help` | The command list |

## Development

```
pwsh -File Tests/run-all.ps1     # every pure-logic test; the gate
lua Tests/core_test.lua          # one file
./deploy.ps1                     # then /reload in the client
```

The deciding lives in `BoonkeeperCore.lua`, which touches no WoW API and runs under plain Lua 5.1.
The client layer only fetches and renders. That split is deliberate: this addon's answer is read
mid-fight, and a judgement that only exists inside the game can only be tested by getting it wrong
in Naxxramas.

## Licence

MIT — see `LICENSE`.
