# Flutter Out of Memory Fix

## Error
```
Out of memory during Dart compilation
Error in zone.cc / allocation.cc
```

## Solution

### 1. Increase Gradle Memory (✅ Already Done)
**File**: `android/gradle.properties`
```
org.gradle.jvmargs=-Xmx12G -XX:MaxMetaspaceSize=6G -XX:ReservedCodeCacheSize=1024m
```
(Increased from 8G → 12G)

### 2. Try These Steps On Your Machine:

**Step 1: Kill all Java/Gradle processes**
- Open Task Manager (Ctrl+Shift+Esc)
- Find and kill all:
  - `java.exe`
  - `gradle.exe`
  - `dart.exe`
  - Android Studio

**Step 2: Clear build cache**
```bash
cd mobile
flutter clean
del -r build/ .dart_tool/ android/build/
flutter pub get
```

**Step 3: Run in release mode (uses less memory)**
```bash
flutter run -d V2510 --release
```

**Step 4: If still failing, use web debug**
```bash
flutter run -d chrome
```

### 3. Alternative: Reduce Dependency Size
Remove unused dependencies from `pubspec.yaml`:
- `lottie` (animations) — if not used everywhere
- `cached_network_image` — if using dio's cache
- `shimmer` — reduce UI polish

### 4. Check System Resources
```bash
flutter doctor -v
```

Look for:
- ✓ RAM available: Need 8GB+ free
- ✓ Android SDK tools updated
- ✓ Java version compatible

## Why This Happens

Your project has many dependencies (bloc, dio, socket.io, razorpay, etc.) that compile into large DEX files. Gradle + Dart JIT compilation together exceed available heap.

**Solution priority**:
1. Kill Java processes + retry ← Fastest
2. Run `--release` mode ← Works 80% of the time  
3. Increase gradle.properties memory ← Already done
4. Split dependencies ← Last resort

## Expected Result

After fixes, `flutter run -d V2510` should:
- Compile without OOM
- Show app on device after ~2-3 minutes
- Display coin balance sync correctly
