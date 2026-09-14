# CrewListr Pro for iOS

**Why the phone.** The passport photograph is already on it. A charter agent is
sent a page on WhatsApp, and on a Mac everything between that message and a crew
list is clerical: save it, find it, move it across, import it. On iPhone the
picture is in the hand holding the phone, and the only thing standing between it
and a crew list is a way out of the messaging app. That way is the share sheet.

Nothing about the review is relaxed to fit the smaller screen. Extraction still
returns `review` and never `cleared`, every field is still confirmed one at a
time against the image it was read from, and the export is still shut until it
has been. A phone is a reason to lay that out differently, not a reason to trust
the OCR more.

---

## One module, two apps

`Sources/CrewListrProMac` is still the one module, and the iOS target compiles
the **same files** — the pattern `project.yml` already established for the UI
tests. There is no second domain model, no second MRZ parser, and no second
export gate to keep in step.

| Layer | On iOS | Why |
| --- | --- | --- |
| `Models`, `CrewFields`, `MRZ`, `DateFormats`, `Settings`, `CrewLibrary`, `TripCalendar`, `Activity`, `Version` | unchanged | already pure Foundation |
| `CrewStore` and its extensions | unchanged but for the local-model section | `@MainActor @Observable`, no AppKit |
| `OCRService`, `DocumentProcessor` | rewritten on Core Graphics and ImageIO | `NSImage` was the only thing holding them to the Mac |
| `ExportService` | text drawing moved to Core Text | see below |
| `SecureStore` | system SQLite, Keychain key, Data Protection | SQLCipher is a Homebrew library |
| `UI/Design` — `Theme`, `Components`, `Brand` | shared | so the two apps are visibly one product |
| `UI/` screens | replaced by `Sources/CrewListrProiOS` | a three-column desktop window is not a phone |
| `LlamaVisionRescuer`, `ModelManager`, `HeadlessExport` | excluded | a 5.8 GB model served by a spawned process, and a command line |

Four things had to be rewritten, and each one had a way of being quietly wrong
on a phone rather than loudly broken:

- **Decoding.** `UIImage(data:)` applies the EXIF rotation and `NSImage`
  reports a point size that is not the pixel size. The machine-readable-zone
  crop is measured in pixels, so `PlatformImageCodec` goes through ImageIO on
  both platforms and applies orientation itself. A PDF — how a scanned passport
  arrives about as often as a photographed one — is rendered to pixels at about
  200 dpi, because Vision cannot read a PDF.
- **Editing.** Rotate, crop and enhance went through `NSImage.lockFocus`, which
  renders at the display's backing scale. Rewriting them on `CGContext` fixed
  three bugs the Mac's own tests had recorded and left failing: a quarter turn
  now swaps the sides exactly, four turns are the identity, and a revision is
  written as JPEG instead of uncompressed TIFF — a 300 KB photograph used to
  become a 3.6 MB revision, sealed and kept forever beside every other revision
  of the same page.
- **Printing.** The crew list is drawn into a `CGContext`, but every string on
  it went through `NSString.draw(at:)`. AppKit's origin is the bottom-left
  corner and UIKit's is the top-left, so the same code on a phone printed the
  whole form upside down. Core Text is the layer under both and has no opinion
  about the page.
- **Storing.** SQLCipher is Homebrew's, and a phone has no Homebrew. What iOS
  has instead is the whole app container encrypted by the system under a key the
  passcode releases. The property that actually matters is unchanged and is
  asserted on both platforms: the database holds one AES-GCM sealed box and
  nothing else, so the file contains no plaintext whichever SQLite opened it.
  The key goes in the Keychain — the long argument in `SecureStore` for keeping
  it in a file is entirely about macOS code-signing prompts, and none of it
  applies here.

---

## Getting a document in

Four routes, one destination. Every one of them stages the bytes as a real file
and hands the file to `CrewStore.importDocuments`, which is the same call the
Mac makes.

**The share sheet** is the one that matters. A share extension cannot open the
encrypted store — extensions are separate processes with their own sandbox, and
giving one the key would put the key in two places — so it takes the bytes, puts
them in an App Group inbox, and says so. The app drains that inbox on launch and
on coming back to the front, and draining is a *move*: the staged file is erased
as it is taken, so a passport photograph sits in a folder two processes can read
for seconds rather than for the life of the installation.

It works from anything that offers a picture to another app: WhatsApp, Viber,
Telegram, Signal, Messages, Mail, Photos, Files.

**Photos** (`PhotosPicker`), **Files** (`fileImporter`, which reaches iCloud
Drive and every other Files provider), and **the camera** — the last through
`VNDocumentCameraViewController`, the scanner behind Notes, which finds the edges
of the page and corrects the perspective. That matters more than it looks:
extraction lives or dies on two lines of OCR-B along the bottom of the page, and
a passport photographed at an angle across a desk gives Vision a trapezoid whose
characters lean. It also means the phone can do something the Mac never could —
the passport goes straight from the page into the encrypted store without ever
being a photograph in anybody's camera roll.

A document that arrives from outside the app has no charter: the operator was in
WhatsApp, not in this app, and nothing about a picture says which crew list it
belongs on. So it waits in a banner above the tab bar until somebody says where
it goes. Guessing would be guessing which charter a stranger's passport belongs
to, which is not a guess this app gets to make.

---

## Getting the crew list out

The same `ExportService`, writing the same CSV and the same PDF with the same
file names. Where the Mac ends at a folder, the phone ends at the share sheet —
Mail, WhatsApp, AirDrop, or Save to Files — because on a phone the useful
question is not "where on the disk" but "to whom". The written files are erased
as soon as the sheet is finished with them: they are an unencrypted crew list
with five people's passport numbers on it.

---

## Where the data lives

| What | Where | Protection |
| --- | --- | --- |
| Application state | the app container, `CrewListrPro/crewlistr.sqlite` | Data Protection, plus AES-GCM on the payload |
| Original documents, revisions, the crew library's scans | the app container | AES-GCM |
| Encryption key | Keychain | `WhenUnlockedThisDeviceOnly` |
| A document on its way in | the App Group inbox, then the app's own temporary directory | Data Protection; erased as it is sealed |
| A crew list on its way to the share sheet | the app's own temporary directory | Data Protection; erased when the sheet closes |

**Three places write plaintext on purpose** — a document staged before it is
sealed, the photo library's own copy of a picture, and the exported crew list —
and all three go through `Scratch`, which is one policy rather than three: each
gets a protected directory of its own, the path that made it erases it, and
whatever survives is swept at the next launch. That last part is not
belt-and-braces. An error between writing and erasing is not the only way a file
lives on: being killed while the share sheet is open is a *normal* thing for iOS
to do, and it leaves a crew list carrying every passport number on the trip in a
directory the system reclaims whenever it feels like it.

**A device with no passcode** has no Data Protection worth the name and no
meaningful "locked" state, so the file protection above and the Keychain's
`WhenUnlockedThisDeviceOnly` both come to nothing while it is switched off. That
is true of every iOS app; it is stated here because this one's promise is
specifically about what a stolen phone gives up. The key is deliberately *not*
`WhenPasscodeSetThisDeviceOnly`, which would refuse to store at all on such a
phone and leave the operator with an app that cannot open.

**Not backed up.** The key is `WhenUnlockedThisDeviceOnly`, which by definition
does not travel to a restored device. Letting the documents travel without it
would put passport scans in iCloud in a form nothing can ever open — the worst
of both, the data leaves the phone and is useless when it lands. So the store is
excluded from backup, and what survives a lost phone is the crew list already
exported.

---

## Building and running

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install
xcodegen`). The project is generated from `ios-project.yml` and is not
committed, for the same reason the UI-test project is not.

```bash
./scripts/ios.sh build           # compile for the simulator
./scripts/ios.sh test            # the iOS test bundle
./scripts/ios.sh run             # install and launch on a booted simulator
./scripts/ios.sh shot out.png    # screenshot whatever is on screen
./scripts/ios.sh share page.png  # put a file in the share inbox, as the
                                 # extension would
```

```bash
CREWLISTR_SIM="iPad Pro 11-inch (M5)" ./scripts/ios.sh run
CREWLISTR_SEED=demo ./scripts/ios.sh run      # the fictional fleet, debug only
```

`share` exists because `simctl` cannot press a button in WhatsApp, and the half
of that path this project owns begins at the inbox. The fictional passports to
feed it with are generated by the Mac suite, which is where the ICAO specimen
data already lives:

```bash
CREWLISTR_SPECIMEN_OUT=/tmp/specimens swift test --filter testWritesTheFictionalPassports
```

Signing is ad-hoc and **required** rather than merely allowed. The App Group is
what hands a passport from the extension to the app, and an entitlement only
reaches the binary through a signature: with signing off the build succeeds, the
app runs, and every share silently vanishes with nothing in the log to say why.

### Onto a real iPhone

The simulator needs nothing. A device needs three things from the Apple
Developer account — external steps in the same way Developer ID signing and
notarization are for the Mac build — and two on the phone:

1. **An iOS development certificate.** The Developer ID certificate this Mac
   already has signs software for macOS outside the App Store and cannot sign
   an iOS app for a device.
2. **The App Group registered** — `group.com.tsevis.crewlisterpro`, added to
   both identifiers: `com.tsevis.crewlisterpro.ios` and
   `…ios.share`. Without it the extension and the app cannot hand a passport
   between them, and the failure is silent.
3. **A provisioning profile for each**, including that group.

And two things on the device itself:

4. **Developer Mode on**, in Settings → Privacy & Security → Developer Mode,
   which asks for a restart. Without it the phone is paired and visible to
   `xcrun xctrace list devices` but is not a destination `xcodebuild` will
   wait for.
5. **Plugged in and trusted.** The build registers the connected device with
   the account, which is what the provisioning profile is issued against.

Then set the team and let Xcode manage signing:

```bash
CREWLISTR_TEAM=XXXXXXXXXX ./scripts/ios.sh device
```

It builds for the first connected device; `CREWLISTR_DEVICE=<udid>` picks
another. The `-destination` naming that device is load-bearing: with only
`-sdk iphoneos` Xcode has no device to register and fails with *"your team has
no devices from which to generate a provisioning profile"*, which reads as an
account problem and is really a missing argument.

A **free personal team** will install the app on a device for seven days, but it
cannot have App Groups — so the share extension, which is the whole reason the
iOS build exists, would install and do nothing. Use a paid team.

---

## Testing

`swift test` still covers the shared code on macOS, and it is the gate: the Mac
app behaves identically after every edit the port required. The iOS bundle
covers what is genuinely new or platform-specific.

| Suite | Covers |
| --- | --- |
| `SharedInboxTests` | What may be shared in, what a hostile file name cannot do, and that a run of shares arrives in the order it was sent |
| `DocumentIntakeTests` | Each route in, that draining is a move, that delivering seals every document and erases the staged copies, and that a shared passport arrives awaiting review |
| `PlatformPipelineTests` | Decoding at true pixel size, PDF rendering, rotation, the Core Text crew list read back through PDFKit, and that the database file contains no plaintext |
| `ScratchTests` | That every plaintext file this app writes is erased by the path that made it, by the path that failed, and by the sweep at the next launch |

One test is device-only and skips on the simulator: the Simulator has no Data
Protection — there is no passcode-derived key on a Mac — so it accepts a
protection class and reports nothing back, and asserting there would be
asserting that the Simulator is a phone.
