# ×2 Cash · Integrated Winter Industrial stand

The Blender source is `blender/x2_cash_stand_integrated.blend`. The refinements build on `a37c7db`. The FBX exports the pedestal, cast nameplate housing, cradle and recessed status lens. The two coin references in Blender are excluded from the export.

The tapered nameplate housing connects to the rim and waist of the round pedestal. The cradle has a flat foot on the deck and a separate steel lip that follows the large coin's edge. The existing large coin tilts back 4° instead of 8°. Its mesh and the entire smaller coin stack are reused.

## Studio placement and rollback

- The local `CashStandIntegrated_Playable.rbxm` contains the installed display geometry with the pivot and material settings used in the House Map. It goes under the existing `Workspace.PassShowcase.Pass_X2Cash.PassAnchor` as `CashStandV2`. This keeps the purchase anchor and the existing dynamic SurfaceGui targets.
- The world-space CFrames and fit measurements are in `studio-placement.json`. Preserve the existing `BigCoin` part and use `coinAfter` for its transform.
- To roll back in the edited House Map, restore `ServerStorage._WinterIndustrialRollback.CashStandV2_a37c7db` as the active model under the same anchor and restore `BigCoin` to `coinBefore`.

## House Map verification

The sampled clearance between the large coin and the stack is 0.056 stud. The lowest point of the lip is 0.032 stud above the pedestal deck. One local TestSave Play checked the owned and active state in English and a client-only unowned and inactive preview in Russian. The Roblox captures are in `blender/renders/x2_cash_stand_integrated`.
