# Design 0.21 · Smart Catfish System

Applied from [elayadesign/ai-design-skills](https://github.com/elayadesign/ai-design-skills) at `456d9e0d3e2d84c748bb143c6ca3d90c45e16213`, specifically landing-page-design visual system, and its linked [redesign-existing-projects](https://github.com/elayadesign/redesign-skill/tree/main/skills/redesign-existing-projects). These are design references, not runtime code or instructions shipped to users.

## Diagnosis and implementation

The previous preview overused rounded cards, decorative gauges, repeated status pills and verbose setup instructions. This iteration groups water readings in one panel, makes the photo shutter the primary camera action, brings QR pairing to the top of settings, and moves manual connection forms to dedicated pages.

A neutral light surface and one teal accent run through all screens. The dark camera viewport is reserved for image capture. Phosphor Regular replaces the mixed Material icons. Its MIT font is bundled directly because phosphor_flutter 2.1.0 subclasses IconData, which Flutter 3.44.6 seals. The glyph constants remain compile-time constants for tree shaking; license is in aqua_hatch/assets/fonts/PHOSPHOR_LICENSE.

## Adaptation for this product

This is a Thai native Flutter device app, not a marketing site or Figma document. Noto Sans Thai remains the single font for legible Thai combining marks. Landing-page SEO, testimonials, tagline reveals, browser navigation and Figma-specific variable APIs do not apply. No invented production metrics or camera results are used; simulated data stays explicitly labeled.

Typography uses 12/14/16/20/24/30/48/60 for the redesigned surfaces with tabular figures. Spacing is organized around 4/8/12/16/24/32. New cards use 16px corners and buttons 12px. Theme tokens are in lib/app/theme.dart. Navigation/content entry uses cubic(.22,1,.36,1); numeric transitions use opacity. Loading bars are indeterminate, never fabricated percentages. Startup renders before reading local preferences, includes a retry state and does not wait for a board connection. Reduce Motion disables movement.

## Verification

Widget tests cover small/landscape screens and 1.4 text scale, guided Wi-Fi, old/new QR validation, direct and remote camera capture, point editing, app startup animation and ETT RS485/heater protocol integration. Screen renders use loaded Thai and Phosphor fonts. Firmware compiles for ETT and ESP32-CAM. Native builds and CI must pass before release; physical hardware is not exercised by the UI test suite.

## Firmware lineage

Imported .ino/.h/.cpp from the user-provided AquaHatch-ETT-WROOM32UE-v0.19.0-ett32ue.5-FirstBoot.zip, SHA256 `892a7919c4ae02e528ff6a5868d4cf59144cbddec085ee9a8da71d9db02dae83`. Kept its GPIO and relay policy; added typed status/capabilities and new setup SSIDs. The source remains independently rebuildable, without private NVS keys or pairing cards.
