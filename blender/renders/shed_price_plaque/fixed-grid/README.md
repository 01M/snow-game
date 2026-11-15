# Shed plaque: fixed information grid

UI-only refinement of the single Shovel prototype after the independent review of `81abd91`. The imported five-mesh geometry, mounting, materials and source art are unchanged. This does not propagate the design to other shelves or begin Commit 16.

## Information design

- Fixed price column on the left, fixed state column on the right; neither moves when Cash or ownership changes.
- Existing CashS icon accompanies the number in every state. After purchase, the price remains a muted reference.
- Insufficient Cash uses a readable outline warning triangle and the single-line localized label `Need Cash` / `Не хватает`. It does not imply a progression lock. The triangle is built from SurfaceGui vector strokes, with no uploaded image or new 3D parts.
- Owned uses the existing larger check icon with navy text. Green is confined to the check.
- Available uses `Buy` / `Купить` in the same state column, without a redundant tool or cart icon.
- Decorative gold dots were removed. A restrained printed divider remains.
- Nunito ExtraBold title: 80 px for short names and Snow Pusher; only the longest RU name scales slightly, within 76–80 px. The title box has 53 px side insets on the 530 px canvas. Price is 88 px, status 44 px.

## Actual verification

One House Map Play with TestSave, plus Output review. The Shovel showed the three actual live states at one normal-distance camera: 5 Cash = insufficient; 10 Cash = available; native E purchase deducted 8 Cash, leaving 2 Cash and adding Shovel to OwnedTools. The owned prompt was disabled and the reference price remained 8.

The same Play supplied lightweight SurfaceGui previews on this same model for the real Config examples `Snow Pusher` / 30 and `Снегоуборщик` / 100. These are explicitly labeled previews, not changed Shovel prices or purchases of those products. A normal-angle capture also records the long RU case. The original live print was restored after the previews.

Measured text bounds: Snow Pusher 371.2 / 424 px at 80 px; Снегоуборщик 420.8 / 424 px at about 76.8 px; 100 is 117.6 / 130 px; Не хватает is 180 / 190 px. All report TextFits. The 424 px title area itself is inset from the enamel edge, so these bounds do not imply contact with the physical border.

The title and price are the primary reads at normal gameplay distance. The smaller state words still require more attention at that distance; the triangle and check provide the faster state distinction. No phone/device matrix was run.

Mandatory checks completed for this source revision: `stylua src`, `stylua --check src`, Selene with 0 errors / 0 warnings / 0 parse errors, fresh `scripts/analyze.ps1` for both places with 0 errors, and `git diff --check`. Output contained no plaque errors; the known Rojo notification-sound warning remains unrelated.

Play was stopped. TestSave, StartCash, ForceLanguage and temporary preview/debug state were cleared. Before/after snapshots of all five mesh IDs, sizes, transforms, materials, colors, reflectance and physical flags matched exactly. No real PlayerData_v1 writes, Roblox publication, asset upload or git push occurred.

## Captures and boards

All eight JPEG files are actual Roblox Play captures, 1124 × 793. Boards contain identical crops at native pixel scale, plus captions; no scene paintover or AI imagery.

- `normal-states.png`: three actual live states at the same normal-distance camera.
- `face-layouts.png`: four close views, with GUI previews clearly identified.
- `01-normal-insufficient-en.jpg`, `02-normal-buy-en.jpg`, `03-normal-owned-en.jpg`: full normal-distance gameplay captures.
- `04-normal-long-ru-preview.jpg`: full normal-distance long RU preview.
- `05-front-short-preview.jpg`, `06-front-snow-pusher-preview.jpg`, `07-front-snowblower-ru-preview.jpg`: close GUI previews.
- `08-front-owned-ru.jpg`: close view of actual ownership after the purchase.
- `verification.json`: coordinates, metrics and verification details.
- `compose-preview.ps1`: reproducible board composition from the raw captures.

Normal camera: position `(-22.92, 6.46, -42.35)`, look-at `(-24.1, 3.3, -49.3225)`, FOV 70. Close camera: position `(-24.1, 3.3, -45.9)`, same look-at and FOV. These captures use the current actual Studio viewport, not the previous 1920 px screenshot scale.

The initial Studio viewport stalled at 1 × 1. Bringing the already-open House Map window to the foreground restored rendering; the Play was not restarted. All gameplay inputs and final captures used Studio MCP.

Rollback remains available at `81abd91`; the previously saved native prototype in `blender/exports/shed_price_plaque/ShedPricePlaque_Playable.rbxm` was not altered. The pre-existing uncommitted `.blend`, `.codex/` and `AGENTS.md` changes are preserved and excluded from this refinement's commit.
