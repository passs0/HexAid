# HexAid Release Notes

## v2.4.0 — CrossOver Preview support

- Detect CrossOver and CrossOver Preview app bundles in `/Applications` and `~/Applications`; choose the installation when both are present.
- Inspect and patch the selected app bundle, and use its configured bottle directory when available.
- Keep the bottom patch action visible in shorter windows.
- Built with Xcode 26.6 and ad-hoc code-signed in GitHub Actions; supports macOS 13 and later.

## v2.3.2 — Window layout fix

- Reduced the minimum content height and matched the native window minimum so the persistent patch action stays fully inside the window on shorter displays.
- Kept the patch workspace scrollable while preserving the sticky bottom action bar.
- Rebuilt and ad-hoc code-signed with the GitHub Actions workflow.


## v2.3.1 — Quality-of-life update

- Open the main patcher workspace at a wider, taller default size so its primary content is less likely to require scrolling.
- Simplified status rows and section styling, and removed redundant optimization explanations.
- Added an explicit warning before purging rebuildable shader and registry caches.
- Reduced the app bundle by excluding duplicate legacy icon files while preserving all four dynamic appearances; stripped nonessential binary symbols.
- Rebuilt the app with an ad-hoc signature in GitHub Actions using Xcode 26.6; the app supports macOS 13 and later.

CrossOver patch and bottle-optimization routines are unchanged from v2.3.0. The Metal HUD setting remains a per-bottle launch setting; this release does not add a shortcut.
