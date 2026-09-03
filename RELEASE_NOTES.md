# CrewListr Pro 0.1.11

Offline crew-list preparation for charter yachts.

## Requirements

- **Apple silicon only.** This build will not launch on an Intel Mac.
- macOS 15 or later.

The Apple silicon requirement is not a packaging choice that can be lifted by
rebuilding: CrewListr Pro links SQLCipher for its encrypted database, and the
available SQLCipher build provides an arm64 slice only. Intel support would
require SQLCipher to be compiled from source for x86_64 first.

## Install

1. Open `CrewListr-Pro-0.1.11.dmg`.
2. Drag **CrewListr Pro** onto the Applications folder.
3. Open it from Applications.

No Terminal command is needed. This build is signed with a Developer ID
certificate and notarized by Apple, so macOS opens it without a Gatekeeper
prompt, including on a Mac that has never seen it before.

## Verifying the download

    spctl -a -t exec -vv "/Applications/CrewListr Pro.app"

Expected: `accepted`, `source=Notarized Developer ID`.

## Privacy

Documents and extracted data never leave the machine. Application state lives
in a SQLCipher database; original files are sealed with AES-GCM under a
Keychain-held key. Nothing can be exported until an operator has confirmed
every field against the document image.

<!--
TODO before publishing: list what changed since the previous release.
Left blank deliberately rather than guessed at.
-->
