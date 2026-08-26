# MacroDock — Build Specification

> Batch 21AUG, app 07 of 30. This document is the complete brief for
> building this application. Read all of it before writing any code. Anything
> not specified here is your decision, but must stay consistent with section 3.

**One-line positioning:** Know what's in the hold.

| Field | Value |
| --- | --- |
| Product name | MacroDock |
| Bundle identifier | `com.macrodock.harbor` |
| Domain | https://macrodock.pro |
| Contact URL | https://macrodock.pro/contact-us |
| Deployment target | iOS 17.0 |
| Swift version | 6.2, strict concurrency `complete` |
| Devices | iPhone only, portrait |
| Interface style | Dark |
| Asset prefix | `mdk_` |
| User-Agent | `MacroDock/1.0 (iOS; +https://macrodock.pro)` |

---

## 1. Non-negotiable constraints

1. **No CocoaPods.** Dependencies come from Swift Package Manager, a local
   in-repo package, a vendored source folder, or nothing at all — per section 3.
2. **No shared code with the other 29 apps.** Business rules are re-implemented
   here under this app's own type names. Copying files between apps fails review.
3. **All code, identifiers, comments, UI copy and the README are in English.**
4. **No launch gate, no WebView shell, no remote configuration, no analytics.**
5. **No CI files.** No `bitrise.yml`, no `Scripts/`, no `metadata/` folder.
6. **Assets are AI-generated.** No stock photography. SF Symbols may support
   small affordances but must never be the primary iconography — see section 12.
7. **The app must build clean** with
   `xcodegen generate && xcodebuild -scheme MacroDock -destination 'generic/platform=iOS' build`.
8. **Nothing may echo another app in this batch** in naming, layout or visuals.

---

## 2. Product core (identical behaviour in all 30 apps)

The product is an offline calorie and macro tracker built on Open Food Facts.
No account, no sign-in, no ads, no in-app purchase, no analytics SDK, no remote
config. All user data stays on the device.

### 2.1 User flow

1. Onboarding, 3 to 4 screens, shown once. Ends by writing initial targets.
2. Today screen: energy for the day plus protein / carbs / fat against targets.
3. From Today the user reaches Search (by name) or Scan (barcode).
4. Search or Scan resolves to Detail: per-100 g macros plus a grams field.
5. Detail leads to Assign: pick a slot and either eaten-today or a future date.
6. Assign returns to Today (if eaten) or to Plan (if dated ahead).
7. Today also opens the Log (eaten list), Wish list, and Goals (edit targets).
8. Log rows can be deleted. Targets can be edited. Everything works offline
   except the first fetch of a product that is not already cached.

### 2.2 Open Food Facts contract

Search endpoint:

```
GET https://world.openfoodfacts.org/cgi/search.pl
    ?search_terms=<query>
    &search_simple=1
    &action=process
    &json=1
    &page_size=<app choice, 20 to 40>
```

Product endpoint:

```
GET https://world.openfoodfacts.org/api/v2/product/<code>.json
```

Field rules:

- Read `product_name`, falling back to `generic_name`, then `brands`.
- Read `nutriments.energy-kcal_100g` first.
- If missing, use `nutriments.energy_100g` (kJ) and convert.
- Read `nutriments.proteins_100g`, `carbohydrates_100g`, `fat_100g`.
- A missing macro is `nil`, never silently `0`.
- Cache every successfully resolved product locally, keyed by barcode.

### 2.3 Portion maths

```
kcal100 = energy-kcal_100g ?? (energy_100g / 4.184)

kcal    = kcal100    * grams / 100
protein = protein100 * grams / 100
carbs   = carbs100   * grams / 100
fat     = fat100     * grams / 100
```

Round only at the point of display, never in stored values.

### 2.4 Barcode normalisation

- Accept input from the camera, from a typed field, and from a pasted URL.
- Extract runs of consecutive digits from the raw string.
- Keep a run whose length is between 8 and 14 inclusive.
- If the kept run is exactly 12 digits (UPC-A), prefix it with `0`.
- Use the normalised code for the product endpoint.
- Support EAN-8, EAN-13, UPC-A, UPC-E and QR codes carrying any of the above.

### 2.5 The four slots

| Role | Can be planned ahead | Can be eaten |
| --- | --- | --- |
| Morning meal | yes | yes |
| Midday meal | yes | yes |
| Evening meal | yes | yes |
| Snack | no | yes |

### 2.6 Targets

Daily targets: energy in kcal, protein in g, carbs in g, fat in g. Editable at
any time. Onboarding must produce a sensible first set; do not ship zeros.

### 2.7 Wish list

Products the user intends to buy. No duplicate barcodes. An item can be
promoted straight into a log entry or a plan entry.

### 2.8 States that must be designed

Each of these needs a real screen, not a default:

- No network while resolving an uncached barcode.
- Barcode not present in Open Food Facts.
- Product found but missing energy data.
- Camera permission denied, or restricted by parental controls.
- Search returned zero results.
- Search failed with a transport error.
- Log, plan and wish list each empty.
- First launch, before onboarding has been completed.


---

## 3. Uniqueness assignment for MacroDock

Each row is unique to this app across all 30. Deviating breaks batch acceptance.

| Axis | Assigned value |
| --- | --- |
| Architecture | **MVVM-C (MVVM + Coordinator)** |
| UI approach | **SwiftUI + SceneKit integration** |
| Naming convention | **Nautical lexicon** |
| File organization | **Vertical slices** |
| Dependency strategy | **SPM remote x1 — swift-algorithms** |
| Design direction | **Nautical harbour** |
| Typography | **Optima** |
| Navigation pattern | **Bottom sheet with detents** |
| AI art style | **Gouache maritime illustration** |
| Functional twist | **Pantry inventory** |
| Persistence | **SQLite via SQLite.swift-style typed wrapper (hand-written)** |
| Screen composition | see 3.6 |
| Scanner technology | **AVCaptureMetadataOutput, live, torch control exposed** |
| Search endpoint | **/cgi/search.pl, page_size 28** |
| Day key representation | **Int days since a fixed reference date** |

### 3.1 Architecture contract

MVVM with all navigation extracted into Coordinators. ViewModels expose
`@Observable` state and closure-based navigation callbacks (`onSelectProduct`)
that the Coordinator assigns. ViewModels never construct another ViewModel;
only the Coordinator does.

Put a short comment block at the top of each principal type stating the role it
plays in this architecture. The README must justify the pattern for this product.

### 3.2 UI contract

SwiftUI screens embedding `SceneView` with a 3D harbour/cargo scene where crates
represent pantry stock levels. Scene nodes must be generated from live data and
respond to taps via hit-testing.

### 3.3 Naming contract

Convention: Nautical lexicon.

Examples to follow: `HarborStore`, `CargoManifest`, `BerthAssignment`, `DockMaster`, `LadingEntry`

Apply it to types, files, properties, methods and asset names alike.

### 3.4 Dependency contract

`apple/swift-algorithms` for chunking, windowing and grouping the manifest views.

### 3.5 Navigation contract

Persistent map-like harbour root; all detail flows arrive as `.presentationDetents([.medium, .large])` sheets stacked over it.

### 3.6 Screen composition contract

The reference batch shipped five apps with an identical screen inventory, which
made them feel like the same product reskinned. This app must not have the same
physical screen structure as any other in the batch.

A harbour map is the permanent root. Every function arrives as a sheet at a
medium or large detent. Detail and Assign live in one sheet that grows between
the two detents rather than pushing.

Section 5 lists the logical functions that must exist. This section decides how
they are grouped into actual screens. Where the two disagree, this section wins.

### 3.7 Scanner contract

Technology: **AVCaptureMetadataOutput, live, torch control exposed**

Cargo-hatch framing overlay; the torch toggle is a first-class control.

Do not substitute a different capture technology. The scan screen's composition
and feedback must be recognisably this app's own.

### 3.8 Data representation contract

- Open Food Facts search uses **/cgi/search.pl, page_size 28**.
- A day is represented internally as **Int days since a fixed reference date**. Use this consistently in
  storage, in queries and in identifiers.
- The demo seed flag key is `mdk.demo.v1`.
- `NSCameraUsageDescription` is exactly: "MacroDock reads barcodes to check cargo into the pantry manifest."

---

## 4. Target file organization

Scheme: **Vertical slices**

```
MacroDock/
  Slices/HarborSlice/ Slices/ManifestSlice/ Slices/BerthSlice/ Slices/StockSlice/ Foundation/
  Assets.xcassets/
```

Adapt the leaf files to the architecture, but the top-level shape is fixed. Do
not create a `Utils/` or `Helpers/` dumping ground.

---

## 5. Screens

Build all of the following. Screen names must follow this app's naming
convention rather than the generic labels used here.

### 5.1 Onboarding
Three to four pages. Explains the product, collects the initial targets, writes
them, and sets a completion flag. Re-runnable from Goals for testing.
Accepts: a skip path that still writes sensible default targets.

### 5.2 Today
The primary screen. Energy consumed against target, plus protein, carbs and fat
against theirs. The four slots with what has been eaten in each. Entry points to
Search, Scan and the twist feature. Must render correctly when the day is empty,
when the target is exceeded, and when a macro target is unset.

### 5.3 Search
Debounced text query against Open Food Facts. Cancels the previous request.
States: idle, loading, results, empty, transport error. Results show name, brand
and kcal/100 g. Selecting a result opens Detail.

### 5.4 Scan
Live camera barcode capture via AVFoundation. Handles not-determined, denied and
restricted permission states, each with a route to Settings. A manual-entry field
is mandatory so the app is fully usable on the Simulator. Stop the capture
session when the view disappears and when the app backgrounds.

### 5.5 Detail
Per-100 g macros for the resolved product, a grams input, and live-computed
totals. Unknown macros display as unknown, never zero. Actions: assign, or add
to the wish list. Guard against zero, negative and absurd gram values.

### 5.6 Assign
Choose a slot — Dawn Watch, Forenoon Watch, Dog Watch, Ship's Biscuit — and choose
eaten-today or a future date. Ship's Biscuit is eaten-only and must be unavailable
when a future date is selected. Confirm returns to the right destination.

### 5.7 Log
Everything eaten on the selected day, grouped by slot, with per-slot subtotals.
Delete with confirmation. Day switching without leaving the screen.

### 5.8 Plan
Future-dated entries. The horizon and its presentation are this app's choice;
state the horizon in the README. Converting a planned item to eaten is one action.

### 5.9 Wish
Products the user wants to buy. Barcode-unique — adding a duplicate updates the
existing row rather than inserting. Promote to log or to plan.

### 5.10 Goals
Edit the four daily targets, with validation. Also hosts: re-run onboarding,
reset all data (confirmed), and the contact link to
https://macrodock.pro/contact-us.

### 5.11 Twist screen
See section 11. The twist needs at least one screen of its own plus a surface on
Today.

---

## 6. Domain model

Minimum entities, named per this app's convention:

- **Product** — barcode, name, brand, kcal/100 g, protein/carbs/fat per 100 g
  (each optional), last refresh timestamp.
- **Entry** — id, product reference, grams, slot, date, eaten-or-planned flag.
- **Targets** — kcal, protein, carbs, fat.
- **WishItem** — product reference, added date.
- Plus whatever the twist in section 11 requires.

Day totals, remaining budget and macro percentages are computed, never stored.

---

## 7. Design system

Direction: **Nautical harbour**

### 7.1 Palette

| Token | Hex | Use |
| --- | --- | --- |
| `background` | `#0B2545` | Screen background |
| `surface` | `#13375F` | Cards, rows, sheets |
| `ink` | `#E8D5B7` | Primary text and icons |
| `accent` | `#D62828` | Primary action, key figure, progress fill |
| `muted` | `#6E8CAE` | Secondary text, dividers, disabled |

Define these as named colours in `Assets.xcassets` and reach them through one
typed accessor. Never hard-code a hex string anywhere else.

### 7.2 Typography

Family: **Optima**

Optima Regular/Bold; wide letter spacing on section headers to echo signage.

Define a type scale of at most six steps behind one accessor and use only those
steps. Text stays legible at the largest Dynamic Type size.

### 7.3 Layout

- One base spacing unit (4 or 8 pt); only multiples of it.
- One corner radius value applied consistently, or deliberately none if the
  design direction calls for hard edges.
- Every interactive element is at least 44x44 pt.

---

## 8. UI and UX quality bar

Every item here is a defect if it is missing. Do not treat this as advice.

**Layout**

- Respect safe areas on every screen. Nothing sits under the notch, the Dynamic
  Island or the home indicator.
- The app is portrait-only on iPhone. Lock it in the Info settings and do not
  write rotation-dependent layout.
- No layout shift when asynchronous data arrives. Reserve the final size up
  front, or use a redacted placeholder of the same dimensions.
- Long product names must truncate gracefully, never push a number off screen.
  Numbers win; names truncate.
- Minimum tap target 44x44 pt for every interactive element, including small
  icon buttons and list accessories.
- Pick one base spacing unit and use only multiples of it. No arbitrary values.

**Keyboard**

- The grams field uses `.decimalPad`, and the decimal separator matches the
  user's locale.
- Content scrolls out from under the keyboard. The focused field is always
  visible.
- Tapping outside the field, or scrolling, dismisses the keyboard.
- Validate on the fly: reject negative and non-numeric input rather than
  crashing the parser later.

**Loading and state**

- Every asynchronous operation has a visible loading state.
- Guard against the spinner flash: if the work finishes in under 150 ms, do not
  show a spinner at all.
- Every list has a designed empty state containing a primary action, not just a
  sentence of text.
- Every error state offers a retry, and states plainly what failed.
- Disable the primary button while its action is in flight so it cannot be
  double-tapped into a double push or a duplicate entry.

**Typography and accessibility**

- All text scales with Dynamic Type. Verify at the largest accessibility size:
  nothing may clip or overlap.
- Every icon-only control has an `accessibilityLabel`. Decorative images are
  marked as decorative so VoiceOver skips them.
- Colour is never the only signal. Pair it with a label, a shape or an icon.
- Honour Reduce Motion: replace movement-heavy transitions with a fade.
- Meet contrast requirements against the palette in section 7. Check the muted
  colour against the background specifically; that is where these palettes fail.

**Formatting**

- Format every number with `NumberFormatter`, never string interpolation. Group
  separators and decimal separators must follow the locale.
- Energy is shown as a whole number of kcal. Macros are shown with at most one
  decimal place.
- Round only at the point of display. Stored values keep full precision.
- Day boundaries use `Calendar.current.startOfDay(for:)` in the user's current
  time zone. Handle the day changing while the app is open, and handle the
  short and long days that daylight saving produces.
- Unknown macro values render as a dash or the word "unknown", never as 0.

**Motion and feedback**

- One haptic on a successful commit (a food logged, a target saved). No haptic
  on navigation.
- Animations are short (0.2 to 0.35 s) and use a single shared easing curve.
- Nothing animates on first appearance of a screen except an intentional entry
  transition.

**Navigation**

- Back always works and never loses entered data without asking.
- A destructive action (delete a log row, reset all data) is confirmed.
- Modal sheets can always be dismissed; there is no dead end.
- Deep state is restorable: relaunching returns the user to a sane screen.


---

## 9. Concurrency

The target builds with Swift 6.2 and `SWIFT_STRICT_CONCURRENCY = complete`. It
must compile with **zero concurrency warnings**. Warnings here become crashes
later, so they are not negotiable.

- All UI types are `@MainActor`. Annotate the type, not individual methods.
- Any value crossing an actor boundary is `Sendable`. Prefer immutable structs
  of primitives.
- Do not use `@unchecked Sendable`. If it is genuinely unavoidable, it needs a
  comment explaining what guarantees the safety.
- No mutable global state. No `static var` that is written after launch.
- Networking and storage APIs are `async` and honour cancellation. When the
  search query changes, cancel the in-flight task; do not let a stale response
  overwrite fresh results.
- Use structured concurrency. Avoid `Task.detached` unless there is a stated
  reason. Never fire a `Task` that outlives the view without owning it.
- Never use `DispatchQueue.main.asyncAfter` to paper over an ordering problem.
  Fix the ordering.
- `Timer` and notification observers are invalidated in `deinit` or on
  disappear.


---

## 10. Persistence engineering

Chosen technology: **SQLite via SQLite.swift-style typed wrapper (hand-written)**

Hand-rolled typed query builder over libsqlite3; no external SQLite package.

This app talks to **SQLite through the C API**. The following are mandatory.

- Open with `sqlite3_open_v2` and the flags you actually need. Check the return
  code of every single `sqlite3_*` call and map failures to a typed Swift error.
- Every prepared statement is finalised. Use `defer { sqlite3_finalize(stmt) }`
  immediately after a successful `sqlite3_prepare_v2`. A leaked statement holds
  a read transaction open and eventually blocks all writes.
- Bind text with the `SQLITE_TRANSIENT` destructor, otherwise the string can be
  deallocated before the statement runs:
  `sqlite3_bind_text(stmt, i, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))`.
- Enable `PRAGMA journal_mode = WAL;` and `PRAGMA foreign_keys = ON;` at open.
- Wrap every multi-row write in `BEGIN` / `COMMIT`, with `ROLLBACK` on error.
  Row-at-a-time autocommit is roughly two orders of magnitude slower.
- Serialise all database access through one actor or one serial queue. Do not
  share a connection across threads.
- Version the schema with `PRAGMA user_version` and apply migrations in order at
  startup.
- Create indices for every column you filter or sort by, in particular the day
  column and the barcode column.
- Store dates as integer epoch seconds, never as localised strings.
- The UI layer never sees a statement or a row cursor; the storage layer returns
  fully materialised value types.


Regardless of technology:

- One seam between domain logic and storage; the UI never touches storage types.
- Writes survive a force-quit. Do not rely on `applicationWillTerminate`.
- Deleting a log row is immediately durable.
- Provide `resetAllData()`, used by tests and reachable from Goals.

---

## 11. Networking

- One client type owns both Open Food Facts endpoints.
- Set `User-Agent` on every request. Open Food Facts throttles clients that do
  not identify themselves.
- 15 second timeout. One retry on a transient transport failure, then a typed
  error. Do not retry a 404.
- Cancel the in-flight search when the query changes. Debounce input by roughly
  300 ms.
- Decode into DTO types that mirror the JSON exactly, then map to domain types.
  Never decode straight into your domain model.
- Open Food Facts data is user-contributed and frequently incomplete. Every
  numeric field is optional. A product with no energy value is a normal case
  that the UI must present, not an error.
- Some numeric fields arrive as strings. The decoder must accept both a number
  and a numeric string for every nutriment.
- `status` of `0` in the product response means not found. Map it to a distinct
  error case so the UI can offer manual entry.
- Never crash on malformed JSON. A decoding failure is a handled error.
- Cache every resolved product locally on success, so the app degrades to a
  working offline catalogue.


Set `User-Agent: MacroDock/1.0 (iOS; +https://macrodock.pro)` on every request. Never reuse another app's string.
Use the **/cgi/search.pl, page_size 28** search endpoint for this app.

---

## 11a. Patterns proven in the reference batch

The five reference apps in the 18AUG batch were shipped and then hand-polished.
The behaviours below are the ones that survived that polish. Reproduce every one
of them, implemented from scratch under this app's own naming and structure.

**Catalog resilience**

- Keep a bundled local shelf (section 14). When an Open Food Facts search returns
  zero rows, or fails, fall back to matching against the local shelf instead of
  showing an empty screen. A search must never dead-end.
- Merge remote results with local shelf matches and de-duplicate by barcode.
- When resolving a scanned code, generate every plausible candidate (see 2.4) and
  try them in order. Only report a miss after all candidates fail.
- Drop any result whose product name is empty; it is unusable in a list.

**Scanner resilience**

- Detect whether a capture device exists at all. On the Simulator there is none,
  so the scan screen must degrade to sample barcode chips plus manual entry, and
  still be fully functional.
- Debounce repeated reads. After a successful decode, ignore further reads for
  roughly 1.5 to 2 seconds, otherwise one barcode fires a burst of lookups.
- Guard against re-firing on the same payload.
- Start the session when the view appears and stop it when it disappears or the
  app backgrounds. A running session in the background drains battery and trips
  review.

**Slot rules**

- The snack slot cannot be planned ahead. When a user picks a future date, remap
  the snack slot to **Evening** rather than rejecting the action
  outright. The reference apps all do this remap and it avoids a dead end.

**Wish list**

- De-duplicate by barcode. If an item is already wished, show the button in a
  disabled 'already saved' state rather than silently inserting a duplicate.

**Product imagery**

- Three-tier fallback for every product thumbnail: remote image URL, then a
  bundled asset if the product came from the local shelf, then the generic
  placeholder. Never show a blank box.

**Demo data**

- Seed a demo day only under `#if targetEnvironment(simulator)`, guarded by a
  versioned UserDefaults key so it runs exactly once. Never seed on device.

**Onboarding**

- Gate onboarding behind a persisted flag. Completing it writes targets.

**Support**

- The Goals screen carries a link to the contact URL. App Review looks for it.

**Presentation touches that made the reference apps feel finished**

- The main energy number animates when it changes, rather than snapping.
- Lists stagger their appearance slightly instead of all arriving at once.
- A newly added row is briefly highlighted so the user sees where it landed.
- Empty states pair generated art with a headline and one line of explanation.
- Error copy is written in the app's own voice, not as a raw error code.

**Deficiencies in the reference apps — do NOT reproduce these**

The reference batch needed manual fixing in these areas. This app must get them
right the first time:

1. **No haptic feedback anywhere.** This app adds haptics on successful commits.
2. **No accessibility labels anywhere.** This app fully supports VoiceOver.
3. **SQL built by string interpolation.** If this app uses SQLite it must use
   prepared statements with bound parameters.
4. **No caching of resolved products.** This app caches every resolved product so
   it works offline afterwards.
5. **No schema versioning.** This app versions its store from day one.
6. **A denied camera permission silently did nothing.** This app explains the
   state and offers a route to Settings.
7. **Search fired a network request on every keystroke in some apps.** This app
   debounces and cancels the previous request.


---

## 11b. App Store readiness

The app must be submittable without further work.

- `PrivacyInfo.xcprivacy` in the target, declaring the UserDefaults access API
  reason `CA92.1` and the file timestamp reason `C617.1`, with
  `NSPrivacyTracking` false and no collected data types.
- `NSCameraUsageDescription` written specifically for this app. Generic strings
  get rejected.
- `LSApplicationCategoryType` of `public.app-category.healthcare-fitness`.
- Portrait only, iPhone only (`TARGETED_DEVICE_FAMILY = "1"`).
- No account, no sign-in, no delete-account flow, no in-app purchase, no ads, no
  user-generated content, and therefore no report or block UI.
- App Tracking Transparency is never invoked.
- The camera is the only sensitive permission requested.
- The app must not present itself as medical advice. It is a personal food log.
- Nutrition data is credited to Open Food Facts, a public database.


Project settings that follow from the above:

```yaml
INFOPLIST_KEY_UIUserInterfaceStyle: Dark
INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait
INFOPLIST_KEY_NSCameraUsageDescription: MacroDock reads barcodes to check cargo into the pantry manifest.
INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.healthcare-fitness
TARGETED_DEVICE_FAMILY: "1"
SWIFT_STRICT_CONCURRENCY: complete
```

---

## 12. Functional twist: Pantry inventory

Track stock on hand per product in grams. Logging a food decrements stock.
Low-stock items surface on the harbour screen and can be pushed to a restock
list. Stock is independent of the wishlist.

This is the app's marketed differentiator. It must be:

- visible on the Today screen, not buried in settings;
- backed by real persisted data, not a cosmetic flourish;
- covered by at least one unit test;
- described in the README as the reason a user would pick this app.

---

## 13. AI-generated assets

Art style: **Gouache maritime illustration**

Base prompt, reused and extended for every asset:

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster
```

All 24 images below are required. Generate each one, export
as PNG, and add it to `Assets.xcassets` as its own image set named exactly as
given. Every name carries the `mdk_` prefix. No asset may be reused
in any other app in this batch.

### 13.1 App icon rules (strict)

The icon is rejected by App Store Connect if any of these are wrong:

- Exactly **1024 x 1024 px**.
- **No alpha channel.** Not "transparent pixels are unused" — the channel itself
  must be absent. Flatten onto an opaque background before export.
- sRGB colour profile, 8 bits per channel, PNG.
- **No text and no words** in the artwork.
- **No rounded corners and no built-in mask.** iOS applies the mask itself.
- No drop shadow that relies on canvas transparency.
- The subject stays inside the middle 80% so the system mask does not clip it.

Verify before shipping:

```bash
sips -g pixelWidth -g pixelHeight -g hasAlpha mdk_AppIcon.png
# expected: pixelWidth: 1024, pixelHeight: 1024, hasAlpha: no
```

If `hasAlpha: yes`, strip it:

```bash
sips -s format jpeg mdk_AppIcon.png --out tmp.jpg \
  && sips -s format png tmp.jpg --out mdk_AppIcon.png && rm tmp.jpg
```

### 13.2 Full asset list

| # | Image set | Size (px) | Alpha | Purpose |
| --- | --- | --- | --- | --- |
| 1 | `mdk_AppIcon` | 1024x1024 | **NO** | App Store icon. NO alpha channel, NO transparency, NO text, NO rounded corners, NO drop shadow outside the canvas. |
| 2 | `mdk_Splash` | 1290x2796 | allowed | Launch background. The middle third must stay quiet so the wordmark reads on top. |
| 3 | `mdk_Onboarding1` | 1024x1536 | allowed | Onboarding page 1 illustration: what the app is for. |
| 4 | `mdk_Onboarding2` | 1024x1536 | allowed | Onboarding page 2 illustration: scan and search. |
| 5 | `mdk_Onboarding3` | 1024x1536 | allowed | Onboarding page 3 illustration: setting daily targets. |
| 6 | `mdk_EmptyLog` | 1024x1024 | allowed | Empty state: nothing logged today yet. Calm and inviting, never sad. |
| 7 | `mdk_EmptySearch` | 1024x1024 | allowed | Empty state: search returned no products. |
| 8 | `mdk_EmptyPlan` | 1024x1024 | allowed | Empty state: no planned entries. |
| 9 | `mdk_EmptyWish` | 1024x1024 | allowed | Empty state: wish list has no items. |
| 10 | `mdk_SlotDawnWatch` | 512x512 | allowed | Icon for the 'Dawn Watch' slot. |
| 11 | `mdk_SlotForenoonWatch` | 512x512 | allowed | Icon for the 'Forenoon Watch' slot. |
| 12 | `mdk_SlotDogWatch` | 512x512 | allowed | Icon for the 'Dog Watch' slot. |
| 13 | `mdk_SlotShipSBiscuit` | 512x512 | allowed | Icon for the 'Ship's Biscuit' slot. |
| 14 | `mdk_MacroProtein` | 512x512 | allowed | Macro icon: protein. Must be visually distinct from carbs and fat at 24pt. |
| 15 | `mdk_MacroCarbs` | 512x512 | allowed | Macro icon: carbohydrates. |
| 16 | `mdk_MacroFat` | 512x512 | allowed | Macro icon: fat. |
| 17 | `mdk_ProductPlaceholder` | 600x600 | allowed | Fallback thumbnail shown when a product has no image. Used in every list row. |
| 18 | `mdk_CardBackdrop` | 1200x800 | allowed | Backdrop art for the product detail card. Low contrast so text stays readable. |
| 19 | `mdk_Texture` | 2048x2048 | allowed | Tiling background texture used at low opacity behind content. MUST tile with no visible seam. |
| 20 | `mdk_ControlFace` | 512x512 | allowed | Custom control artwork used for the primary interactive element. |
| 21 | `mdk_ScanOverlay` | 1024x1024 | required | Camera overlay art framing the barcode. The centre must be fully transparent. |
| 22 | `mdk_TwistHero` | 1024x1024 | allowed | Hero art for the 'Pantry inventory' feature screen. |
| 23 | `mdk_SuccessMark` | 512x512 | allowed | Shown briefly when a food is logged successfully. |
| 24 | `mdk_HeaderDecor` | 1200x600 | allowed | Decorative header accent on the main screen. |

### Prompt per asset

**`mdk_AppIcon`** — 1024x1024

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, the app's single emblem, centred, filling the canvas edge to edge
```

**`mdk_Splash`** — 1290x2796

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a vertical hero composition with a calm, uncluttered centre band
```

**`mdk_Onboarding1`** — 1024x1536

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a person or object representing discovering what is in packaged food
```

**`mdk_Onboarding2`** — 1024x1536

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a scanning or measuring motif showing a product being identified
```

**`mdk_Onboarding3`** — 1024x1536

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a goal or target motif showing daily progress being met
```

**`mdk_EmptyLog`** — 1024x1024

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, an empty vessel, surface or container waiting to be filled
```

**`mdk_EmptySearch`** — 1024x1024

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a search motif that has come back with nothing found
```

**`mdk_EmptyPlan`** — 1024x1024

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, an empty schedule, grid or horizon with nothing scheduled
```

**`mdk_EmptyWish`** — 1024x1024

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, an empty basket, list or shelf
```

**`mdk_SlotDawnWatch`** — 512x512

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a morning motif appropriate to the theme
```

**`mdk_SlotForenoonWatch`** — 512x512

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a midday motif appropriate to the theme
```

**`mdk_SlotDogWatch`** — 512x512

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, an evening motif appropriate to the theme
```

**`mdk_SlotShipSBiscuit`** — 512x512

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a small extra or in-between motif appropriate to the theme
```

**`mdk_MacroProtein`** — 512x512

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a symbol standing for protein, rendered as a single clear emblem
```

**`mdk_MacroCarbs`** — 512x512

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a symbol standing for carbohydrate, rendered as a single clear emblem
```

**`mdk_MacroFat`** — 512x512

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a symbol standing for dietary fat, rendered as a single clear emblem
```

**`mdk_ProductPlaceholder`** — 600x600

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a generic packaged grocery item with no readable branding
```

**`mdk_CardBackdrop`** — 1200x800

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, an abstract backdrop suitable for sitting behind a product card
```

**`mdk_Texture`** — 2048x2048

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a seamless repeating surface pattern
```

**`mdk_ControlFace`** — 512x512

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, the face of a single physical control such as a dial, key or slider handle
```

**`mdk_ScanOverlay`** — 1024x1024

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a framing reticle or targeting bracket, open in the middle
```

**`mdk_TwistHero`** — 1024x1024

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, an emblem representing this app's signature feature
```

**`mdk_SuccessMark`** — 512x512

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a confirmation mark or celebratory emblem
```

**`mdk_HeaderDecor`** — 1200x600

```
gouache painted maritime illustration, harbour and cargo crates, muted navy and rope beige, visible brush texture, vintage travel poster, a wide decorative band or ornament
```


### 13.3 Asset rules

- Assets must be semantically different from each other. Do not generate one
  image and recolour it; each entry has its own subject.
- Slot icons and macro icons must be distinguishable from one another at 24 pt.
  Test them small before accepting them.
- `mdk_Texture` must tile seamlessly. Verify by placing four copies
  edge to edge.
- `mdk_ScanOverlay` needs a genuinely transparent centre.
- Record the exact prompt used for every asset in the README.
- SF Symbols are permitted only for close, chevron, share and similar system
  affordances.

---

## 14. Demo shelf

Seed these six products locally so the app is usable with no network. Adapt the
display names to this app's naming style; keep barcodes and nutrition values
exactly as given.

| Product | Barcode | kcal/100g | Protein | Carbs | Fat |
| --- | --- | --- | --- | --- | --- |
| Granola | `0018627103257` | 471 | 10.0 | 64.0 | 20.0 |
| Couscous | `3038350208002` | 376 | 12.8 | 77.4 | 0.6 |
| Canned Sweetcorn | `0024000163015` | 81 | 2.9 | 17.1 | 1.0 |
| Cheddar Cheese | `0021000658084` | 403 | 24.9 | 1.3 | 33.1 |
| Quinoa | `8410054010128` | 368 | 14.1 | 64.2 | 6.1 |
| Apple | `4013000000000` | 52 | 0.3 | 13.8 | 0.2 |

On the Simulator only, optionally seed one demo day of entries so screenshots
are not empty. Never seed on a physical device.

---

## 15. Slot labels

| Role | Label in MacroDock | Planned | Eaten |
| --- | --- | --- | --- |
| Morning meal | Dawn Watch | yes | yes |
| Midday meal | Forenoon Watch | yes | yes |
| Evening meal | Dog Watch | yes | yes |
| Snack | Ship's Biscuit | no | yes |

---

## 16. Anti-patterns

The following will fail review:

- `try!`, `as!`, or force-unwrapping anything derived from the network, the
  database or a file.
- `fatalError` anywhere reachable at runtime. It is acceptable only for a
  programmer error in an initialiser that cannot fail in practice, and needs a
  comment.
- Swallowing an error with an empty `catch`.
- `print` used as production logging.
- A hard-coded hex colour outside the single colour accessor.
- A hard-coded font name outside the single typography accessor.
- An SF Symbol used as primary iconography.
- Storing a value that can be computed (day totals, remaining budget, macro
  percentages).
- Blocking the main thread on disk or network work.
- `UIScreen.main` for sizing. Use the geometry the layout system gives you.
- Index positions used as list identity. Identity is a stable identifier.
- A view that reaches into the persistence layer directly, bypassing the
  architecture's designated seam.
- Business logic inside a `View` body or a `UIViewController` method, when the
  assigned architecture places it elsewhere.
- Copying a source file from another app in this batch.


---

## 17. Tests

Add a unit test target `MacroDockTests` covering at minimum:

1. Portion maths, including the kJ fallback path.
2. Barcode normalisation: EAN-8, EAN-13, UPC-A padding, a URL input, and a
   string containing no valid digit run.
3. Missing-macro handling — unknown stays unknown and never becomes zero.
4. Day total aggregation across all four slots.
5. Wish list barcode uniqueness, including the duplicate-add path.
6. Day boundary behaviour across a daylight-saving transition.
7. Decoding a realistic Open Food Facts payload with missing and
   string-encoded nutriment values.
8. The section 12 twist logic.
9. One architecture-specific test proving the pattern holds — a pure reducer or
   update function, an interactor in isolation, or a state machine rejecting an
   illegal transition.
10. A persistence round-trip: write, relaunch-equivalent reload, verify.

---

## 18. README.md

Write `README.md` at the app folder root covering:

1. What the app does and who it is for.
2. The architecture used and **why** it suits this product.
3. The unique feature added and how it works.
4. The AI art style and the exact prompt used for every asset.
5. How this app differs from the reference and from the other apps in the batch.
6. Build instructions.

---

## 19. Definition of done

**Build**
- [ ] `xcodegen generate` succeeds.
- [ ] `xcodebuild -scheme MacroDock -destination 'generic/platform=iOS' build` succeeds.
- [ ] Zero new compiler warnings.
- [ ] Strict concurrency `complete` compiles clean.
- [ ] Test target passes.

**Function**
- [ ] Onboarding to first logged food works on a clean install.
- [ ] Search, scan and manual barcode entry each resolve a product.
- [ ] All four slots accept entries; Ship's Biscuit rejects future dates.
- [ ] Plan, wish, log deletion and target editing persist across relaunch.
- [ ] Force-quitting immediately after a write loses nothing.
- [ ] Every state in section 2.8 has a designed screen.

**Uniqueness**
- [ ] Architecture matches **MVVM-C (MVVM + Coordinator)** with no leakage across layers.
- [ ] UI approach matches **SwiftUI + SceneKit integration**.
- [ ] Navigation matches **Bottom sheet with detents**.
- [ ] Screen composition follows section 3.6, not the generic list in section 5.
- [ ] Scanner uses **AVCaptureMetadataOutput, live, torch control exposed**.
- [ ] Day key is **Int days since a fixed reference date**.
- [ ] Typography uses **Optima** and nothing else.
- [ ] Palette matches section 7.1 exactly.
- [ ] No source file is shared with another app in the batch.

**Reference parity**
- [ ] Empty or failed search falls back to the local shelf.
- [ ] Remote and local results merge, de-duplicated by barcode.
- [ ] All barcode candidates tried before reporting a miss.
- [ ] Scanner degrades to sample codes plus manual entry with no capture device.
- [ ] Scan reads are debounced and do not re-fire on the same payload.
- [ ] Snack remaps to Evening when a future date is chosen.
- [ ] Wish list shows a disabled 'already saved' state for duplicates.
- [ ] Product thumbnails fall back remote, then bundled, then placeholder.
- [ ] Demo seed runs only on Simulator, once, behind `mdk.demo.v1`.
- [ ] Contact link present on Goals.
- [ ] `PrivacyInfo.xcprivacy` present and correct.
- [ ] Haptics, accessibility, product caching and schema versioning all present
      (the four things the reference batch was missing).

**Assets**
- [ ] All 24 images generated in the **Gouache maritime illustration** style, prefixed `mdk_`.
- [ ] Icon is 1024x1024 with `hasAlpha: no`, verified with `sips`.
- [ ] Texture tiles without a seam; scan overlay centre is transparent.
- [ ] Slot and macro icons are distinguishable at 24 pt.
- [ ] Every prompt recorded in the README.

**Quality**
- [ ] Section 8 UI/UX bar satisfied end to end.
- [ ] Largest Dynamic Type size clips nothing.
- [ ] VoiceOver reaches and correctly labels every control.
- [ ] No item from section 16 present in the codebase.
- [ ] README complete.

---

## 20. Build commands

```bash
cd App07_MacroDock
xcodegen generate
xcodebuild -scheme MacroDock -destination 'generic/platform=iOS' build
xcodebuild -scheme MacroDock -destination 'platform=iOS Simulator,name=iPhone 16' test
```
