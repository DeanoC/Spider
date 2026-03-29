# SpiderSuite macOS Release Notes

Release date: {{RELEASE_DATE}}

Installer:
- `{{SUITE_PKG_NAME}}`

Included products:
- `Spiderweb {{SPIDERWEB_VERSION}}`
- `SpiderApp {{SPIDERAPP_VERSION}}`

## Highlights

- Spiderweb now leads onboarding with `Start Local Workspace`, using a resumable macOS quickstart that installs local prerequisites, bootstraps a workspace, mounts a deterministic drive under `~/Spiderweb/<workspace-name>`, and reveals it in Finder when native mounting succeeds.
- SpiderApp now opens into a workspace-centered newcomer shell with first-class `Workspace`, `Devices`, `Capabilities`, `Explore`, and `Settings` routes, while the older operator-style setup flow is kept behind `Advanced`.
- `Just Try It` now uses a smaller dedicated workspace template so first-run setup lands in a lighter local environment instead of a broader development preset.
- Spiderweb can now hand successful onboarding off into SpiderApp directly, and the parent `Spider` repo now builds a signed suite installer that ships both products together.

## Known issue

- Apple’s FSKit mount state can still wedge on some Macs. When that happens, `Just Try It` may not attach the Spiderweb drive until after a reboot. This release makes onboarding degrade more gracefully when the OS mount path is stuck, but it cannot fully repair the Apple-side FSKit wedge in-process.

## What to validate after install

- Run `Just Try It` from Spiderweb and confirm the local workspace reaches a usable ready state.
- Open SpiderApp from the Spiderweb success state and confirm the workspace shell shows `Workspace`, `Devices`, `Capabilities`, and `Explore`.
- If native mounting times out, reboot the Mac and retry before treating it as a product regression.
