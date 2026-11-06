# Studio smoke test (about 15 minutes)

Run this once in real Roblox Studio before the first upload, and again before each new version. Lune covers the code, but only Studio shows the real panel, theme colors, undo and script permission prompts.

## Before you start

1. Run `./scripts/build.sh`. It must end with "all builds and tests passed".
2. In Studio, open the Plugins tab and click Plugins Folder. Copy `build/ZovoBackdoorScanner.rbxm` into that folder.
3. Restart Studio and open a new Baseplate.

## Steps

1. Open the Plugins tab. A Zovo section with a Backdoor Scanner button must be there. Click it. The panel opens on the right with three buttons and a gray help line.
2. Click Scan selection with nothing selected. The status line says "Nothing is selected".
3. In the Explorer, right click Workspace and choose Insert from File. Pick `build/fixtures/clean.rbxm` (DoorKit). Select DoorKit and click Scan selection. Expected result is "No risky code found. 3 scripts checked".
4. Insert `build/fixtures/infected.rbxm` (FreeCarKit). Select it and click Scan selection. Expected result is "Dangerous code found. 10 scripts checked, 2 critical, 11 high, 14 medium, 1 low." Take screenshot 1 of the panel.
5. On FreeCarKit.Body.Loader, click Open at line 4. The script opens at line 4. Scroll right on that line to see the hidden require.
6. Click Delete on FreeCarKit.Body.Loader. The script leaves the Explorer and the list scans again (9 scripts). Press Ctrl+Z. The script comes back.
7. Click Disable on FreeCarKit.Wheel1.Vaccine. In Properties, Enabled is now off. Press Ctrl+Z and check that it is on again.
8. Click Ignore on one finding. That row goes away. Close and reopen Studio, then scan again. The row is back (the free edition keeps ignores for the session only).
9. Select FreeCarKit and click Creator Store check. The status says "Not ready for the Creator Store", and only rows marked "(Creator Store rule)" are listed. Take screenshot 2.
10. Click Scan whole place. The status counts the scripts in all services.
11. Switch Studio to the light theme (File, Studio Settings, Theme) and reopen the panel. Text must be readable. Take screenshot 3 in the light theme.
12. Delete the test kits from Workspace and close the place without saving.

## Pro edition

Remove the free .rbxm from the Plugins folder, copy `build/ZovoBackdoorScannerPro.rbxm` in, and restart Studio.

1. The footer shows Export report and "Auto-scan on insert is off". Click the auto-scan button. It changes to "is on".
2. Insert `build/fixtures/infected.rbxm`. Within a second the panel opens and says "You just inserted FreeCarKit". Take screenshot 4.
3. Insert `build/fixtures/clean.rbxm`. Nothing happens. Click Play, wait for the character to spawn, then Stop. The panel must not open during the playtest.
4. Click Export report. Studio asks for script injection permission. Allow it. ServerStorage now has a ZovoScanReports folder with a Text and a Csv module.
5. Click Ignore on one finding, restart Studio, open the same place and scan again. The ignored row stays hidden.

## Pass rule

Every step behaves as written and the Output window shows no red errors from the plugin. If a step fails, write the step number and the Output text in `docs/smoke-results.md` and do not upload.

## Screenshots for the listing

Crop screenshots 1 to 4 to the panel and the Explorer. Save them as `listing/shot-1.png` to `listing/shot-4.png` (1280 x 720 or larger). The Creator Store takes up to 5 images and 1 video.
