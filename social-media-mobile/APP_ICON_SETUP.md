# App Icon Setup with logo.ico

## Overview
Replace the default Flutter app icon with your `logo.ico` across all platforms.

---

## Platform-Specific Instructions

### 1. **Android** 🤖
Replace icons in all mipmap folders:

- `android/app/src/main/res/mipmap-mdpi/ic_launcher.png` → use logo.ico
- `android/app/src/main/res/mipmap-hdpi/ic_launcher.png` → use logo.ico
- `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png` → use logo.ico
- `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png` → use logo.ico
- `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` → use logo.ico

**Steps:**
1. Convert logo.ico to PNG format (matching each resolution)
2. Replace each `ic_launcher.png` with the resized version
3. Run: `flutter clean && flutter pub get && flutter run`

**Icon Sizes Needed:**
- mdpi: 48x48
- hdpi: 72x72
- xhdpi: 96x96
- xxhdpi: 144x144
- xxxhdpi: 192x192

---

### 2. **iOS** 🍎
Replace icons in `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

**Current PNG files to replace:**
- Icon-App-20x20@1x.png
- Icon-App-20x20@2x.png
- Icon-App-20x20@3x.png
- Icon-App-29x29@1x.png
- Icon-App-29x29@2x.png
- Icon-App-29x29@3x.png
- Icon-App-40x40@1x.png
- Icon-App-40x40@2x.png
- Icon-App-40x40@3x.png
- Icon-App-60x60@2x.png
- Icon-App-60x60@3x.png
- Icon-App-76x76@1x.png
- Icon-App-76x76@2x.png
- Icon-App-83.5x83.5@2x.png
- Icon-App-1024x1024@1x.png

**Steps:**
1. Convert logo.ico to PNG at each required resolution
2. Replace all icon files in the folder
3. Run: `flutter clean && flutter pub get && flutter run -d ios`

---

### 3. **Web** 🌐
Replace favicon and PWA icons:

**Files to replace:**
- `web/favicon.png` → use logo.ico (convert to PNG)
- `web/icons/Icon-192.png` → use logo.ico resized to 192x192
- `web/icons/Icon-512.png` → use logo.ico resized to 512x512
- `web/icons/Icon-maskable-192.png` → use logo.ico resized to 192x192
- `web/icons/Icon-maskable-512.png` → use logo.ico resized to 512x512

**Steps:**
1. Convert logo.ico to PNG
2. Resize to required dimensions
3. Replace all icon files
4. Run: `flutter clean && flutter pub get && flutter run -d chrome`

---

### 4. **Windows** 🪟
Replace Windows app icon:

**File to replace:**
- `windows/runner/resources/app_icon.ico` → replace with logo.ico

**Steps:**
1. Replace `app_icon.ico` with your logo.ico
2. Run: `flutter clean && flutter pub get && flutter run -d windows`

---

### 5. **macOS** 🍎
Replace macOS app icon:

**File to replace:**
Replace icons in `macos/Runner/Assets.xcassets/AppIcon.appiconset/`

**Steps:**
1. Convert logo.ico to PNG and replace all icon files
2. Run: `flutter clean && flutter pub get && flutter run -d macos`

---

## Quick Conversion Guide

### Using Online Tools:
- **ICO to PNG Converter:** https://convertio.co/ico-png/
- **Image Resizer:** https://www.iloveimg.com/resize-image

### Using Command Line (ImageMagick):
```bash
convert logo.ico -resize 48x48 ic_launcher_mdpi.png
convert logo.ico -resize 72x72 ic_launcher_hdpi.png
convert logo.ico -resize 96x96 ic_launcher_xhdpi.png
convert logo.ico -resize 144x144 ic_launcher_xxhdpi.png
convert logo.ico -resize 192x192 ic_launcher_xxxhdpi.png
```

### Using FFmpeg:
```bash
ffmpeg -i logo.ico -vf scale=192:192 icon_192.png
ffmpeg -i logo.ico -vf scale=512:512 icon_512.png
```

---

## Summary Checklist

- [ ] Android: Replace all mipmap ic_launcher.png files
- [ ] iOS: Replace all icon files in AppIcon.appiconset
- [ ] Web: Replace favicon.png and icons folder files
- [ ] Windows: Replace app_icon.ico
- [ ] macOS: Replace AppIcon.appiconset icons
- [ ] Run `flutter clean && flutter pub get`
- [ ] Run `flutter run` on target platform
- [ ] Test app icon appears correctly on launcher

---

## Verification

After replacing icons, run:
```bash
flutter clean
flutter pub get
flutter run
```

The app icon should now display your logo across all platforms!
