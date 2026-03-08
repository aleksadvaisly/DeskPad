# Red Flags: DeskPad Displays Contract
# Date: 20260308
# Iteration: 1
# Review score: convergence=1.00

## 1. Scope Reduction / Requirement Non-Compliance

No instance found.

Methodology:

- Re-read the specification sections covering DeskPad responsibilities, file format, startup/update triggers, and version 1 scope.
- Cross-checked root/display fields and write triggers against [DeskPad/AppDelegate.swift:73](/Users/developer/Projects5/DeskPad/DeskPad/AppDelegate.swift#L73) through [DeskPad/AppDelegate.swift:295](/Users/developer/Projects5/DeskPad/DeskPad/AppDelegate.swift#L295).

Severity: LOW
Impact: No concrete scope drop was found in the implemented DeskPad responsibilities.

## 2. Lack of Algorithm Grounding

The implementation has no automated tests for snapshot ordering, atomic file replacement, or change-signature suppression. Evidence: the project has no unit-test target in `DeskPad.xcodeproj`, and verification was limited to `make build` plus one manual launch that produced `~/.DeskPad/displays.json`.

Severity: MEDIUM
Impact: Future refactors could silently break arrangement ordering or write semantics without a fast regression signal.

## 3. Implicit Logic Changes / Hidden Simplifications

`activeDisplayID` is currently derived from `NSApp.keyWindow?.screen?.displayID` and otherwise falls back to `CGMainDisplayID()`, rather than tracking a stronger notion of “last active / last used” display. Evidence: [DeskPad/AppDelegate.swift:131](/Users/developer/Projects5/DeskPad/DeskPad/AppDelegate.swift#L131) through [DeskPad/AppDelegate.swift:132](/Users/developer/Projects5/DeskPad/DeskPad/AppDelegate.swift#L132).

Severity: LOW
Impact: Consumers receive a valid soft hint, but it reflects DeskPad's current key window more than broader system activity.
