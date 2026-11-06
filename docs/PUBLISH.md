# Publish on the Creator Store

Nothing here was done by an agent. Each step needs the owner's Roblox login, ID or bank details. Times are estimates.

## Owner steps

### A. One time account setup (about 15 minutes, plus review time)

1. Sign in at create.roblox.com with the Roblox account that will own the plugins. It must be an individual account, not a group, because group-owned assets cannot be sold.
2. Turn on 2-step verification at roblox.com, Settings, Security. Selling requires it.
3. Verify the account with a government ID at roblox.com, Settings, Account Info, Verify My Age. Phone verification is not enough. A verified account may distribute 10 plugins per 30 days (2 when unverified).

### B. Studio smoke test (about 15 minutes)

4. Follow `docs/SMOKE-TEST.md` and save the 4 screenshots in `listing/`.

### C. Publish the free plugin (about 10 minutes)

5. In Studio, open any place. In the Explorer, right click ServerStorage, choose Insert from File, and pick `build/ZovoBackdoorScanner.rbxm`.
6. Right click the inserted ZovoBackdoorScanner script and choose Publish as Plugin (in some Studio versions it is under Save / Export). The Asset Configuration window opens.
7. Paste the name from `listing/free-name.txt` and the text from `listing/free-description.txt`. Set the thumbnail to `listing/icon-512.png`. Click Save.
8. Delete the inserted script from ServerStorage and close the place without saving.
9. Open create.roblox.com/dashboard/creations?activeTab=Plugin and click the new plugin. On the Configure page, add up to 5 images (`listing/shot-1.png` to `shot-4.png`).
10. In Distribution, turn on Distribute on Creator Store. Leave USD Pricing at Free. Click Save Changes.
11. Copy the asset URL (create.roblox.com/store/asset/ID) and send it to the orchestrator.

### D. Seller account for Pro (about 15 minutes, then up to 7 days)

12. Open create.roblox.com/settings/eligibility/priced-assets. If all checks are green, click the link to the Stripe form.
13. Have ready the bank account, home address, phone, email, tax ID and the W-8 or W-9 answers. Leave statement descriptor and website empty. Check the country twice. It cannot be changed later.
14. Wait for the email. The status on the same page must read Success.

### E. Publish Pro (about 10 minutes, after D is Success)

15. Repeat steps 5 to 9 with `build/ZovoBackdoorScannerPro.rbxm`, `listing/pro-name.txt` and `listing/pro-description.txt`.
16. On the Configure page, turn on Distribute on Creator Store and set USD Pricing to 4.99. Prices cannot be set in Studio. Click Save Changes.
17. Send the Pro asset URL to the orchestrator.

## Orchestrator steps

1. After step 11, nothing changes in code. Record the free asset ID in the product notes.
2. After step 17, put the Pro URL in `editions/free/Edition.luau` (`proUrl`), bump the version in both editions and in `CHANGELOG.md`, run `./scripts/build.sh`, and ask the owner to publish the update. Updates use the same Publish as Plugin menu on the existing asset ("Overwrite" the existing plugin).
3. Optional toolbar icon. The owner uploads `listing/icon-toolbar-32.png` as an image at create.roblox.com (Development Items, Images). Put `rbxassetid://ID` into `icon` in both edition files and rebuild.
4. Check the listing once a day for the first week with the public API (no login needed).

```sh
curl -s "https://apis.roblox.com/toolbox-service/v1/items/details?assetIds=FREE_ID,PRO_ID"
```

## Store facts that affect us

- Sellers get the sale price minus taxes and payment fees. Each sale sits 30 days in escrow, then pays out on the first of the month.
- Refunds and chargebacks come out of the seller balance, and the buyer loses the asset.
- Only individual accounts can buy. Groups cannot.
- The asset must not use remote require, loadstring, getfenv or setfenv, LoadAsset, LinkedSource or obfuscated code. Both builds pass this check (`scripts/selfscan.luau`).
