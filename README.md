# MacroDock

Know what is in the hold.

MacroDock is a personal offline calorie and macro tracker for iPhone. It logs food against daily energy and macro targets, using Open Food Facts for product data. There is no account, no ads, and no analytics. It is a food log, not medical advice. Nutrition data is credited to Open Food Facts.

## Who it is for

People who want a harbour-styled pantry log: scan or search cargo, berth it on a watch, and see how the hold is running.

## Architecture

MacroDock uses **MVVM-C** (MVVM + Coordinator).

- `DockMaster` is the only type that constructs ViewModels. It assigns closures such as `onSelectProduct`.
- ViewModels are `@Observable` and `@MainActor`. They never construct other ViewModels.
- Views bind to a ViewModel and call those closures. They never touch SQLite.
- `HarborStore` is the persistence seam. Domain types cross that seam, never statements or cursors.

This fits a harbour root that never leaves the map. Every function is a stacked detent sheet. The coordinator owns that stack so search, scan, wish and the hold can all open the same lading sheet without ViewModels coupling to one another.

## Unique feature: pantry inventory

Stock is tracked in grams per product. Logging eaten cargo decrements hold stock. Low crates light up on the harbour map and can be pushed to a **restock list**. Restock is independent of the wish ledger. That is why someone picks MacroDock over a plain logger: the 3D hold shows what is left in the pantry.

## Navigation and screens

The harbour map is the permanent root. Functions arrive as `.presentationDetents([.medium, .large])` sheets. Detail and berth assignment share one sheet that grows from medium to large.

Plan horizon: **14 voyage days**, shown as two 7-day watch windows.

Watches: Dawn Watch, Forenoon Watch, Dog Watch, Ship's Biscuit (snack, eaten only). A future date remaps Ship's Biscuit to Dog Watch (evening).

A day is an `Int` ordinal since 1 January 2024 (`VoyageDay`).

## How it differs

- Nautical lexicon and a SceneKit harbour, not a tabbed “today” list.
- Hand-rolled typed SQLite builder over libsqlite3 (WAL, prepared statements, `PRAGMA user_version`). No SQLite.swift package.
- `apple/swift-algorithms` for chunking and grouping manifests.
- Pantry stock + restock list as the marketed twist.
- Gouache maritime illustration, Optima, hard crate edges, palette `#0B2545 / #13375F / #E8D5B7 / #D62828 / #6E8CAE`.

## Build

```bash
cd App07_MacroDock
/path/to/xcodegen generate
xcodebuild -scheme MacroDock -destination 'generic/platform=iOS' build
xcodebuild -scheme MacroDock -destination 'platform=iOS Simulator,name=iPhone 16' test
```

XcodeGen binary used in this batch: `tools/xcodegen/bin/xcodegen`.

Requires iOS 17+, Swift 6.2, strict concurrency complete. SPM: `apple/swift-algorithms`.

Demo seed runs only on the Simulator, once, behind `mdk.demo.v1`.

## AI art

Style: gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster.

| Asset | Prompt |
| --- | --- |
| `mdk_AppIcon` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a single emblem filling the entire square canvas edge to edge: a closed wooden cargo crate stamped with a rope circle and a small lighthouse painted on the crate face, dock planks and dark harbour water behind, no text, no letters, no words, no numbers, no rounded corners, no drop shadow, no transparency, subject centered in the middle 80 percent, opaque navy background |
| `mdk_Splash` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a tall vertical hero of a quiet night harbour, wooden piers receding, stacked crates at the sides, calm uncluttered dark water band across the middle third of the canvas with almost no objects so a wordmark could sit there, lantern glow, no readable text |
| `mdk_Onboarding1` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a dock worker in a wool coat opening a wooden provision crate on a quay to inspect sacks and tins of food, discovering what is packed inside, vertical composition, no readable text or logos |
| `mdk_Onboarding2` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a brass spyglass and cargo-hatch frame aimed at a tin of provisions on a crate, measuring and identifying a packaged food, vertical composition, no readable text or barcodes |
| `mdk_Onboarding3` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a brass compass and tide gauge on a captain desk with four marked rings showing daily progress toward a harbour destination, goal and target motif, vertical composition, no readable text |
| `mdk_EmptyLog` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, an empty open wooden barge at a quiet quay waiting to be filled with cargo, calm inviting mood never sad, dawn light, no text |
| `mdk_EmptySearch` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a brass spyglass pointed into thick harbour fog with nothing found beyond, empty search motif, coiled unused rope, no text |
| `mdk_EmptyPlan` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, an empty pier with vacant rope-tied bollards and a blank wooden tide board showing an empty schedule horizon, nothing berthed, no text |
| `mdk_EmptyWish` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, an empty wicker market basket sitting on a warehouse shelf with vacant cubbies, no items wished for, no text |
| `mdk_SlotDawnWatch` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a single clear morning emblem: rising sun over a harbour mast with a steaming mug on a crate, dawn watch, simple centered icon composition, no text |
| `mdk_SlotForenoonWatch` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a single clear midday emblem: high sun over a loaded cargo derrick at noon, forenoon watch, simple centered icon composition, no text |
| `mdk_SlotDogWatch` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a single clear evening emblem: crescent moon and lantern hanging over dark harbour water, dog watch, simple centered icon composition, no text |
| `mdk_SlotShipSBiscuit` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a single clear snack emblem: a small hard biscuit on a coil of rope beside a tiny crate, ship's biscuit extra, simple centered icon composition, no text |
| `mdk_MacroProtein` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a single clear protein emblem: a coiled hawser rope knot shaped like a muscle, one simple centered symbol, high contrast silhouette readable at tiny size, no text |
| `mdk_MacroCarbs` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a single clear carbohydrate emblem: a sheaf of wheat grain painted on a flour sack, one simple centered symbol, high contrast readable at tiny size, no text |
| `mdk_MacroFat` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a single clear dietary fat emblem: a golden oil amphora jug with a drip, one simple centered symbol, high contrast readable at tiny size, no text |
| `mdk_ProductPlaceholder` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a generic unlabeled brown paper grocery packet and tin sitting on a crate, no branding, no letters, no logos, packaged food silhouette, centered |
| `mdk_CardBackdrop` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, an abstract low-contrast backdrop of distant harbour fog, muted dock silhouettes and faint crate outlines, very quiet so text can sit on top, no bright objects in the center, landscape wide |
| `mdk_Texture` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, gouache painted seamless repeating surface pattern, maritime, muted navy wash with faint rope-beige brush dabs and tiny crate wood grain marks, even density edge to edge so it tiles with no visible seam, no focal object, no text |
| `mdk_ControlFace` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, the face of a single brass ship compass dial with a red needle, physical control handle, centered circular instrument, abstract tick marks only |
| `mdk_ScanOverlay` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a cargo-hatch framing reticle: thick painted wooden hatch corners and rope brackets only at the four corners, the entire center of the image must be empty dark void like an open hatch with nothing in the middle, targeting bracket open in the middle, no text |
| `mdk_TwistHero` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, emblem for pantry inventory: a cutaway warehouse hold stacked with unlabeled crates showing stock levels, signature pantry feature hero, centered, no text |
| `mdk_SuccessMark` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a celebratory confirmation emblem: a red wax seal with a painted check-like rope knot, success mark for cargo logged, simple centered, no text |
| `mdk_HeaderDecor` | gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a wide decorative band: painted rope swag, brass bollards and distant masts along a harbour horizon, ornamental header, landscape, no text |
