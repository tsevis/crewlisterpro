# CrewListr Pro 0.2.0

Offline crew-list preparation for charter yachts.

## What changed

All of it came from one operator's report after a season of real use.

**A departure picked as 29/08 was exported as 28/08.** A voyage date is a day on
your own calendar; a document date is a day fixed in UTC by the check digits
behind it. Both went through one UTC formatter, and local midnight in Athens is
21:00 the previous day in UTC — so every crew list exported east of Greenwich
carried the wrong departure. The two are now kept apart. **Re-export any crew
list produced by an earlier version and check its dates.**

**Dates read the way the document prints them.** `20 OCT 1972` on screen and on
the printed form, rather than `1972-10-20`. Stored as ISO-8601 still, and either
form can be typed into the field. The CSV keeps ISO, because software reads it.

**New trips run Saturday to Saturday**, the rhythm this trade actually works to.
Moving the departure moves the return with it and keeps the charter the same
length; pick a return date to override that.

**A fleet.** Every yacht you charter, described once — name, flag, port of
registry and registration number are facts about the vessel, not about this
August's booking. A trip picks one, and its details reach the crew list without
being retyped. Duplicate gives a sister ship; retire takes a sold yacht out of
the picker while leaving it named on its past charters; a yacht any trip still
uses cannot be deleted.

**A settings screen**, grouped by when each default applies: the charter's start
day and length, the yacht new trips are for, the flag and port most of a fleet
shares, what an export writes and where, the optional local model, and how many
earlier versions of the database to keep.

**The client** — the one person who signs the papers. A checkbox beside the
role, not a third role, because they are aboard as the skipper or as a
passenger. Their row is set in bold on the printed form and a signature line
names them.

**The skipper's email**, collected and printed for the skipper alone.

**Every trip is visible at once.** The dropdown became a horizontal strip of
yachts, each carrying its own cleared-count.

**Names come off more passports.** Everything except the name is read from the
zone's second line, which carries check digits; the name is the only thing the
first line holds, and it has no arithmetic behind it. That line now gets a
second, closer look when the first pass misses it, and every reading the
recogniser proposed is considered rather than only the likeliest. Measured
against six real passports: three names before, five after. The sixth stays
blank, correctly — its name line came back with digits in it, and deciding which
letters those were would be inventing a name.

**Country codes with digits in them.** `ROU` read as `R0U` reached the crew list
unchallenged, because the issuing state is the one field on that line no check
digit covers. It is now repaired against the first line where possible, and
against the shapes OCR genuinely confuses otherwise — and a nationality that
still contains a digit is refused rather than quietly confirmed.

Hungarian and Romanian were also missing from the recogniser's languages, which
is the likeliest reason extraction was good on Ukrainian passports and mediocre
on others.

## Upgrading

Open it and carry on; your existing trips, documents and confirmations are read
as they are.

Two things are worth knowing:

- **The exported CSV has two new columns**, `skipper_email` and `is_client`.
  They are appended after the existing thirteen, so anything reading that file
  by position is unaffected.
- **The database records a new schema version.** An older build still opens a
  store this version has written, but the settings and yacht retirements in it
  will mean nothing to it.

## Requirements

- **Apple silicon only.** This build will not launch on an Intel Mac.
- macOS 15 or later.

The Apple silicon requirement is not a packaging choice that can be lifted by
rebuilding: CrewListr Pro links SQLCipher for its encrypted database, and the
available SQLCipher build provides an arm64 slice only. Intel support would
require SQLCipher to be compiled from source for x86_64 first.

## Install

1. Open `CrewListr-Pro-0.2.0.dmg`.
2. Drag **CrewListr Pro** onto the Applications folder.
3. Open it from Applications.

No Terminal command is needed when the disk image has been signed with a
Developer ID certificate and notarized — `scripts/release.sh --notarize` — in
which case macOS opens it without a Gatekeeper prompt, including on a Mac that
has never seen it before. A build signed any other way will prompt.

## Verifying the download

    spctl -a -t exec -vv "/Applications/CrewListr Pro.app"

Expected for a notarized build: `accepted`, `source=Notarized Developer ID`.

## Privacy

Documents and extracted data never leave the machine. Application state lives
in a SQLCipher database; original files are sealed with AES-GCM under a
Keychain-held key. Nothing can be exported until an operator has confirmed
every field against the document image.

There is no setting that changes this. No preference auto-confirms a field,
trusts a clean check digit, or exports a document nobody has looked at — and
there is no server to configure, no account to sign into and no sync to switch
on.
