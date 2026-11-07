# Backdoor & Virus Scanner for Roblox Studio

A Studio plugin that finds backdoors and viruses in models before they reach your game. It also checks your own models and plugins against the Creator Store asset rules before you list them.

The scanner reads script sources in the open place. It makes no web requests, and it changes nothing until you click Disable, Delete or Export.

## What it finds

23 rules in four groups. Rules marked "store" are practices that the Creator Store asset rules forbid in models and plugins you distribute.

| Rule | Level | Store | Example |
|---|---|---|---|
| Loads code by asset ID | critical | store | `require(4815162342)` |
| Loads code by asset ID through a variable or string | critical | store | `local id = 123456789 require(id)` |
| Runs code from a string | critical | store | `loadstring(game:HttpGet(url))()` |
| Code from a known obfuscator | critical | store | Luraph, IronBrew, MoonSec and PSU markers in code or comments |
| Changes the script environment | high | store | `getfenv`, `setfenv`, `getrenv` |
| Inserts assets at run time | high | store | `InsertService:LoadAsset`, `game:GetObjects` |
| Uses LinkedSource | high | store | a LinkedSource value, or code that sets it |
| Builds a dangerous name from pieces | high | store | `"re" .. "quire"`, `("gnirtsdaol"):reverse()`, `string.char(108,111,...)` |
| String written as escape codes | high | store | `"\108\111\97\100..."` |
| Code pushed off screen with spaces | high | store | `print("hi")` followed by 300 spaces and `require(...)` |
| Sends data to a Discord webhook | high | | `PostAsync("https://discord.com/api/webhooks/...")` |
| Script name used by known viruses | high | | Vaccine, Infected, Spread, 4D Being |
| Text built with string.char | medium | store | 6 or more character codes |
| Very long encoded string | medium | store | 2,000+ characters of base64 or hex |
| Extremely long line | medium | store | 2,000+ characters on one line |
| Prompts players to buy something | medium | | `PromptGamePassPurchase` in a free model |
| Teleports players to a fixed place | medium | | `TeleportService:Teleport(1818181818, plr)` |
| Script hides or renames itself | medium | | `script.Parent = nil` |
| Special handling for a fixed user ID | medium | | `if plr.UserId == 77777777 then` |
| Script inside an object that does not run scripts | medium | | a Script inside a Weld, Decal or Sound |
| Same script copied many times | medium | | 5 or more identical risky scripts |
| Makes web requests | low | | `HttpService:RequestAsync` |
| Very large script | low | store | 200 KB or more |

The scanner works on the code, not on text. A comment or a string that mentions `loadstring` or `require(123)` is not reported.

## How to use it

1. Open the Plugins tab and click Backdoor Scanner. The panel docks on the right.
2. Select a model in the Explorer and click Scan selection, or click Scan whole place.
3. Each script with results shows the level, the rule, the line and the code on that line. The panel explains why it matters and what to do.
4. Click Open at line to jump to the code. Select selects the script. Disable turns it off. Delete removes it. Both can be undone with Ctrl+Z.
5. Click Ignore to hide a finding you have checked.

To check something you want to sell, select it and click Creator Store check. The panel lists only the problems that break the Creator Store asset rules. When the list is empty, it says "Ready for the Creator Store".

## Free and Pro

Scanning, the Creator Store check and all fix buttons are free and stay free.

Pro is a separate plugin on the Creator Store for 4.99 USD, paid one time. It adds three things.

- Auto-scan on insert. Each model added to Workspace is scanned. If it has risky code, the panel opens.
- Export report. The last scan is saved as text and CSV in ServerStorage.ZovoScanReports. Studio asks for script permission the first time.
- Ignore lists saved per place.

## Build from source

You need [Rojo](https://rojo.space) 7.7 or newer and [Lune](https://lune-org.github.io/docs) 0.11 or newer.

```sh
./scripts/build.sh            # builds both editions, builds the test models, runs all tests
rojo build default.project.json -o ZovoBackdoorScanner.rbxm
```

To install a local build, copy `build/ZovoBackdoorScanner.rbxm` into your Studio plugins folder (Plugins tab, then Plugins Folder) and restart Studio.

## Tests

- `tests/unit.luau` has 33 tests for the lexer, every rule, the tree scan, the reports and the speed on very large scripts.
- `tests/studio_sim.luau` loads the built .rbxm files, runs the plugin code with instance requires as Studio does, and clicks the real buttons on two test models. It checks 52 results, including undo recording, rescans, the Creator Store check, the Pro tools and that auto-scan stays off during playtests.
- `scripts/selfscan.luau` runs the Creator Store check on the plugin itself. Both editions pass.
- `scripts/corpus.luau` scans a folder of real Luau code to count false positives. On 1,954 files from Knit, ProfileService, Fusion, Roact, roblox-lua-promise and NevermoreEngine, it reported no backdoor-type findings. It reported only real uses of getfenv, loadstring, LoadAsset, purchase prompts and HttpService.

The two test models are in `tests/fixtures`. They contain inert copies of common backdoor patterns and are never published.

## Limits

- The scanner reads code. It does not run it. A backdoor that downloads code at run time is found by the download call (require, loadstring, LoadAsset), not by what it downloads.
- Scripts that Studio does not let plugins read, such as CoreScripts, are skipped.
- A rule can match code that is safe in your game. For example, a purchase prompt in your own shop is fine. Use Ignore for those.

[zovo-support-start]: #

## Support Zovo

Zovo builds and maintains this plugin. If it saves you time, you can support the work on [GitHub Sponsors](https://github.com/sponsors/theluckystrike). Sponsorship is optional, and the tool works the same without it.

The Creator Store listing has no outside links, because Roblox does not allow them there.

Zovo is made by [theluckystrike](https://github.com/theluckystrike) on GitHub.

## More tools by Zovo

- [All Zovo tools on GitHub](https://github.com/theluckystrike?tab=repositories). Free developer tools for VS Code, Apify, Confluence, Jira and Minecraft servers.

[zovo-support-end]: #

## License

MIT. See [LICENSE](LICENSE).
