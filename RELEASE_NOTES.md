# HexAid Release Notes

## v2.3.1 — Quality-of-life update

- Open the main patcher workspace at a wider, taller default size so its primary content is less likely to require scrolling.
- Simplified status rows and section styling, and removed redundant optimization explanations.
- Added an explicit warning before purging rebuildable shader and registry caches.
- Reduced the app bundle by excluding duplicate legacy icon files while preserving all four dynamic appearances; stripped nonessential binary symbols.
- Rebuilt the app with an ad-hoc signature in GitHub Actions using Xcode 26.6; the app supports macOS 13 and later.

CrossOver patch and bottle-optimization routines are unchanged from v2.3.0. The Metal HUD setting remains a per-bottle launch setting; this release does not add a shortcut.
