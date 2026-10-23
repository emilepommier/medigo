#!/bin/bash
set -e

# Ensure dialog is installed
if ! command -v dialog &> /dev/null; then
  echo "Dialog not found. Please install it first (e.g., sudo apt install dialog)."
  exit 1
fi

PROJECT_DIR="$(pwd)"
APP_DIR="$PROJECT_DIR/medigo"
ZIP_FILE="$PROJECT_DIR/medigo.zip"
KEYSTORE_FILE="$PROJECT_DIR/medigo.jks"
KEY_PROPERTIES_FILE="$PROJECT_DIR/key.properties"
KEYSTORE_DIR="$APP_DIR/android/keystore"
ANDROID_DIR="$APP_DIR/android"
IOS_DIR="$APP_DIR/ios"
APK_OUTPUT="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
IPA_OUTPUT="$APP_DIR/build/ios/ipa/medigo.ipa"
BUILD_NUMBER_FILE="$PROJECT_DIR/.build_number"
VERSION_FILE="$PROJECT_DIR/.app_version"
# Add timestamp to log filename for better organization
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$PROJECT_DIR/build_log_${TIMESTAMP}.txt"
LATEST_LOG_LINK="$PROJECT_DIR/build_log_latest.txt"

# Firebase App IDs
FIREBASE_ANDROID_APP_ID="1:200614907934:android:31cc5e295a901d3e9a1e0f"
FIREBASE_IOS_APP_ID="1:200614907934:ios:b9622170aeecb2119a1e0f"

# Create or clear log file
: > "$LOG_FILE"

# Create/update symlink to latest log
ln -sf "$(basename "$LOG_FILE")" "$LATEST_LOG_LINK"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

show_log() {
  dialog --title "📜 Build Log" --textbox "$LOG_FILE" 30 100
}

show_final_summary() {
  local status="$1"
  local version="$2"
  local build="$3"
  
  if [ "$status" == "success" ]; then
    dialog --title "🎉 Build Complete" --msgbox "Build successful!\n\nVersion: $version\nBuild: $build\n\n📄 Full log saved to:\n$LOG_FILE\n\nYou can also access it via:\n$LATEST_LOG_LINK" 14 70
  else
    dialog --title "❌ Build Failed" --msgbox "Build failed!\n\n📄 Error log saved to:\n$LOG_FILE\n\nYou can also access it via:\n$LATEST_LOG_LINK\n\nPlease review the log file for details." 12 70
  fi
}

# Trap errors to save log even on failure and clean up ZIP
trap 'log "❌ Script failed with exit code $?"; show_final_summary "failure" "$APP_VERSION" "$BUILD_NUMBER"; clear; echo "❌ Build failed. Check log at: $LOG_FILE"; exit 1' ERR

# --- MAIN MENU ---
MAIN_OPTION=$(dialog --title "🚀 Medigo Build Tool" --menu "What would you like to do?" 15 60 3 \
  1 "🔨 Start build process" \
  2 "📲 Install existing build on device" \
  3 "🛠 Run debug build (flutter run)" 3>&1 1>&2 2>&3)

EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  clear
  echo "🚪 Exiting..."
  exit 0
fi

# --- OPTION 2: Install existing build ---
if [ "$MAIN_OPTION" == "2" ]; then
  # Ask which platform
  PLATFORM=$(dialog --title "📱 Platform" --menu "Which platform?" 12 50 2 \
    1 "Android (APK)" \
    2 "iOS (IPA)" 3>&1 1>&2 2>&3)
  
  if [ "$PLATFORM" == "1" ]; then
    if [ ! -f "$APK_OUTPUT" ]; then
      dialog --msgbox "❌ APK not found at:\n$APK_OUTPUT\n\nPlease build the app first." 10 60
      clear
      exit 1
    fi

    if ! command -v adb &> /dev/null; then
      dialog --msgbox "❌ ADB not found. Please install Android platform-tools." 10 50
      clear
      exit 1
    fi

    {
      log "📲 Installing existing APK via ADB..."
      adb install -r "$APK_OUTPUT" >> "$LOG_FILE" 2>&1
      log "✅ APK installed successfully."
    } | dialog --title "📲 Installing" --progressbox "Installing APK..." 20 80

    show_log
    dialog --msgbox "✅ APK installed successfully!\n\n📄 Log saved to:\n$LOG_FILE" 10 70
    clear
    echo "✅ APK installed! Log: $LOG_FILE"
    exit 0
  elif [ "$PLATFORM" == "2" ]; then
    dialog --msgbox "ℹ️ iOS IPA installation requires Xcode or third-party tools.\n\nIPA location:\n$IPA_OUTPUT\n\nYou can use tools like:\n- ios-deploy\n- Xcode Devices window\n- Apple Configurator" 14 70
    clear
    exit 0
  fi
fi

# --- OPTION 3: Run debug build ---
if [ "$MAIN_OPTION" == "3" ]; then
  if [ ! -d "$APP_DIR" ]; then
    dialog --msgbox "❌ Project directory not found at:\n$APP_DIR\n\nPlease build the app first." 10 60
    clear
    exit 1
  fi

  # Ask which platform
  PLATFORM=$(dialog --title "📱 Platform" --menu "Which platform?" 12 50 2 \
    1 "Android" \
    2 "iOS" 3>&1 1>&2 2>&3)

  if [ "$PLATFORM" == "1" ]; then
    if ! command -v adb &> /dev/null; then
      dialog --msgbox "❌ ADB not found. Please install Android platform-tools." 10 50
      clear
      exit 1
    fi

    # Check if device is connected
    DEVICE_COUNT=$(adb devices | grep -w "device" | wc -l)
    if [ "$DEVICE_COUNT" -eq 0 ]; then
      dialog --msgbox "❌ No device connected.\n\nPlease connect a device via ADB and try again." 10 50
      clear
      exit 1
    fi

    dialog --msgbox "🛠 Starting Flutter debug build for Android...\n\nThe app will launch on your connected device.\nPress OK to continue." 10 50
    clear
    
    cd "$APP_DIR"
    log "🛠 Starting flutter run for Android..."
    echo "🛠 Running flutter run..."
    flutter run 2>&1 | tee -a "$LOG_FILE"
    exit 0
  elif [ "$PLATFORM" == "2" ]; then
    dialog --msgbox "🛠 Starting Flutter debug build for iOS...\n\nThe app will launch on your connected device.\nPress OK to continue." 10 50
    clear
    
    cd "$APP_DIR"
    log "🛠 Starting flutter run for iOS..."
    echo "🛠 Running flutter run..."
    flutter run 2>&1 | tee -a "$LOG_FILE"
    exit 0
  fi
fi

# --- OPTION 1: Continue with full build process ---

# --- Pre-flight checks ---
log "🔍 Running pre-flight checks..."

if [ ! -f "$ZIP_FILE" ]; then
  dialog --msgbox "❌ ZIP file not found at:\n$ZIP_FILE\n\nPlease ensure the medigo.zip file exists in the project directory." 10 70
  clear
  echo "❌ Error: $ZIP_FILE not found"
  exit 1
fi

if [ ! -f "$KEYSTORE_FILE" ]; then
  dialog --msgbox "❌ Keystore file not found at:\n$KEYSTORE_FILE\n\nPlease ensure the medigo.jks file exists in the project directory." 10 70
  clear
  echo "❌ Error: $KEYSTORE_FILE not found"
  exit 1
fi

if [ ! -f "$KEY_PROPERTIES_FILE" ]; then
  dialog --msgbox "❌ Key properties file not found at:\n$KEY_PROPERTIES_FILE\n\nPlease ensure the key.properties file exists in the project directory." 10 70
  clear
  echo "❌ Error: $KEY_PROPERTIES_FILE not found"
  exit 1
fi

log "✅ Pre-flight checks passed"

# --- Step 0: Handle app version & build number ---
if [ ! -f "$VERSION_FILE" ]; then echo "1.0.0" > "$VERSION_FILE"; fi
if [ ! -f "$BUILD_NUMBER_FILE" ]; then echo "1" > "$BUILD_NUMBER_FILE"; fi

APP_VERSION=$(cat "$VERSION_FILE")
BUILD_NUMBER=$(cat "$BUILD_NUMBER_FILE")

# Use "set +e" temporarily so dialog's exit code doesn't kill the script
set +e
if dialog --title "📦 Version Info" \
  --yesno "Current version: $APP_VERSION (build $BUILD_NUMBER)\n\nDo you want to change the app version?" 10 50; then
  CHANGE_VERSION=0
else
  CHANGE_VERSION=$?
fi
set -e

if [ $CHANGE_VERSION -eq 0 ]; then
  # User chose "Yes"
  NEW_VERSION=$(dialog --inputbox "Enter new version (e.g. 1.0.2):" 10 40 "$APP_VERSION" 3>&1 1>&2 2>&3)
  APP_VERSION="$NEW_VERSION"
  echo "$APP_VERSION" > "$VERSION_FILE"
  log "✅ Version updated to $APP_VERSION"
elif [ $CHANGE_VERSION -eq 1 ]; then
  # User chose "No" → keep version
  log "ℹ️ Keeping version $APP_VERSION"
else
  # User pressed ESC → confirm exit
  dialog --yesno "You pressed ESC. Do you want to exit?" 10 50
  if [ $? -eq 0 ]; then
    clear
    echo "🚪 Exiting..."
    exit 0
  else
    log "ℹ️ Continuing with version $APP_VERSION"
  fi
fi

# Always increment build number
BUILD_NUMBER=$((BUILD_NUMBER + 1))
echo "$BUILD_NUMBER" > "$BUILD_NUMBER_FILE"
log "🔢 Using build number: $BUILD_NUMBER"

# --- Step 0.5: Choose platform(s) ---
set +e
PLATFORM_CHOICE=$(dialog --title "📱 Platform Selection" --menu "Select platform to build:" 15 60 3 \
  1 "Android only" \
  2 "iOS only" \
  3 "Both (Android + iOS)" 3>&1 1>&2 2>&3)
set -e

EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  clear
  echo "🚪 Exiting..."
  exit 0
fi

BUILD_ANDROID=false
BUILD_IOS=false

case "$PLATFORM_CHOICE" in
  1)
    BUILD_ANDROID=true
    log "📱 Building for: Android only"
    ;;
  2)
    BUILD_IOS=true
    log "📱 Building for: iOS only"
    ;;
  3)
    BUILD_ANDROID=true
    BUILD_IOS=true
    log "📱 Building for: Both Android and iOS"
    ;;
  *)
    dialog --msgbox "❌ No platform selected. Exiting." 8 50
    clear
    exit 0
    ;;
esac

# --- Step 1: Ask if rebuild is needed ---
set +e
if dialog --title "🧱 Project Setup" \
  --yesno "Do you want to RESET the project from the ZIP file?\n\n(YES = Wipe changes & Unzip)\n(NO = Keep current files & Build)" 12 60; then
  REBUILD=0
else
  REBUILD=$?
fi
set -e

if [ $REBUILD -eq 0 ]; then
  # ✅ User chose "Yes" – reset from ZIP
  (
    echo "10" ; log "🧹 Deleting old medigo folder..." ; sleep 0.5
    rm -rf "$APP_DIR"

    echo "50" ; log "📂 Unzipping project..." ; sleep 0.5
    mkdir -p "$APP_DIR"
    unzip -q "$ZIP_FILE" -d "$APP_DIR"
    
    echo "100" ; log "✅ Project reset complete" ; sleep 0.5
  ) | dialog --title "🔄 Resetting Project" --gauge "Resetting from ZIP..." 10 100 0
elif [ $REBUILD -eq 1 ]; then
  # ❌ User chose "No" – keep existing files
  log "ℹ️ Keeping existing project files..."
else
  # 🚪 User pressed ESC – confirm exit
  dialog --yesno "You pressed ESC. Do you want to exit?" 10 50
  if [ $? -eq 0 ]; then
    clear
    echo "🚪 Exiting..."
    exit 0
  else
    log "ℹ️ Continuing with existing files..."
  fi
fi

# --- Step 2: Build Process (Always runs) ---
(
    echo "5" ; log "🚀 Starting build process..." ; sleep 0.5

    cd "$APP_DIR"

    echo "10" ; log "🧹 Running flutter clean..." ; sleep 0.5
    flutter clean 2>&1 | while IFS= read -r line; do
      log "$line"
    done

    echo "15" ; log "📦 Running flutter pub get..." ; sleep 0.5
    flutter pub get 2>&1 | while IFS= read -r line; do
      log "$line"
    done

    echo "20" ; log "🖼️ Building app icons..." ; sleep 0.5
    dart run flutter_launcher_icons -f pubspec.yaml 2>&1 | while IFS= read -r line; do
      log "$line"
    done

    # === ANDROID BUILD ===
    if [ "$BUILD_ANDROID" = true ]; then
      echo "25" ; log "🤖 Starting Android build..." ; sleep 0.5

      echo "30" ; log "🔑 Copying keystore..." ; sleep 0.5
      
      # Check if keystore file exists
      if [ ! -f "$KEYSTORE_FILE" ]; then
        log "❌ ERROR: Keystore file not found at: $KEYSTORE_FILE"
        exit 1
      fi
      
      mkdir -p "$KEYSTORE_DIR"
      log "📁 Created keystore directory: $KEYSTORE_DIR"
      
      cp "$KEYSTORE_FILE" "$KEYSTORE_DIR/" 2>&1 | while IFS= read -r line; do
        log "$line"
      done
      
      log "✅ Keystore copied successfully"

      if [ -f "$KEYSTORE_DIR/key" ]; then
        log "🗑️ Removing old key file..."
        rm "$KEYSTORE_DIR/key"
      fi

      echo "35" ; log "📝 Copying and fixing key.properties..." ; sleep 0.5
      
      # Check if key.properties file exists
      if [ ! -f "$KEY_PROPERTIES_FILE" ]; then
        log "❌ ERROR: Key properties file not found at: $KEY_PROPERTIES_FILE"
        exit 1
      fi
      
      # Copy and fix the storeFile path to be relative to android/app directory
      sed -E 's|storeFile=(.*/)?([^/]+\.jks)$|storeFile=keystore/\2|g' "$KEY_PROPERTIES_FILE" > "$ANDROID_DIR/key.properties"
      
      log "✅ Key properties copied and path fixed for Gradle"
      cat "$ANDROID_DIR/key.properties" | grep "storeFile" | while IFS= read -r line; do
        log "ℹ️ $line"
      done

      echo "38" ; log "🔍 Verifying signing configuration..." ; sleep 0.5
      
      # Verify key.properties format
      if ! grep -q "storeFile" "$ANDROID_DIR/key.properties"; then
        log "⚠️ WARNING: key.properties missing 'storeFile' property"
      fi
      if ! grep -q "storePassword" "$ANDROID_DIR/key.properties"; then
        log "⚠️ WARNING: key.properties missing 'storePassword' property"
      fi
      if ! grep -q "keyAlias" "$ANDROID_DIR/key.properties"; then
        log "⚠️ WARNING: key.properties missing 'keyAlias' property"
      fi
      if ! grep -q "keyPassword" "$ANDROID_DIR/key.properties"; then
        log "⚠️ WARNING: key.properties missing 'keyPassword' property"
      fi
      
      # Extract storeFile path from key.properties
      STORE_FILE_PATH=$(grep "storeFile=" "$ANDROID_DIR/key.properties" | cut -d'=' -f2 | sed 's|^\.\./||')
      KEY_ALIAS=$(grep "keyAlias=" "$ANDROID_DIR/key.properties" | cut -d'=' -f2)
      STORE_PASSWORD=$(grep "storePassword=" "$ANDROID_DIR/key.properties" | cut -d'=' -f2)
      KEY_PASSWORD=$(grep "keyPassword=" "$ANDROID_DIR/key.properties" | cut -d'=' -f2)
      
      if [ -n "$STORE_FILE_PATH" ]; then
        # Check if keystore exists at the specified path (relative to android directory)
        FULL_KEYSTORE_PATH="$ANDROID_DIR/$STORE_FILE_PATH"
        if [ -f "$FULL_KEYSTORE_PATH" ]; then
          log "✅ Keystore file found at: $STORE_FILE_PATH"
          
          # Verify keystore can be opened with provided credentials
          log "🔍 Verifying keystore credentials..."
          if keytool -list -keystore "$FULL_KEYSTORE_PATH" -storepass "$STORE_PASSWORD" -alias "$KEY_ALIAS" &>/dev/null; then
            log "✅ Keystore credentials verified successfully"
          else
            log "❌ ERROR: Cannot open keystore with provided credentials!"
            log "❌ Please check:"
            log "   - storePassword matches the keystore password"
            log "   - keyPassword matches the key password"
            log "   - keyAlias '$KEY_ALIAS' exists in the keystore"
            log ""
            log "💡 To list aliases in keystore, run:"
            log "   keytool -list -keystore '$FULL_KEYSTORE_PATH' -storepass <your-store-password>"
            exit 1
          fi
        else
          log "❌ ERROR: Keystore file NOT found at: $FULL_KEYSTORE_PATH"
          log "❌ Build will fail or use debug keystore!"
          exit 1
        fi
      fi
      
      # Verify app/build.gradle has signingConfigs
      if [ -f "$ANDROID_DIR/app/build.gradle" ]; then
        if ! grep -q "signingConfigs" "$ANDROID_DIR/app/build.gradle"; then
          log "⚠️ WARNING: android/app/build.gradle may be missing signingConfigs block"
          log "⚠️ App might build with debug keystore instead of release keystore"
        else
          log "✅ Signing configuration detected in app/build.gradle"
        fi
      fi

      echo "40" ; log "⚙️ Building Android APK with version $APP_VERSION and build number $BUILD_NUMBER..."
      flutter build apk --build-name="$APP_VERSION" --build-number="$BUILD_NUMBER" 2>&1 | while IFS= read -r line; do
        log "$line"
        echo "XXX"
        echo "50"
        echo "Building Android APK...\n\n$line"
        echo "XXX"
      done

      log "✅ Android APK build complete!"
    fi

    # === iOS BUILD ===
    if [ "$BUILD_IOS" = true ]; then
      echo "55" ; log "🍎 Starting iOS build..." ; sleep 0.5

      # Check if on macOS
      if [[ "$OSTYPE" != "darwin"* ]]; then
        log "⚠️ WARNING: iOS builds require macOS. Skipping iOS build."
        echo "90"
      else
        echo "60" ; log "📦 Running pod install..." ; sleep 0.5
        cd "$IOS_DIR"
        pod install 2>&1 | while IFS= read -r line; do
          log "$line"
        done
        cd "$APP_DIR"

        echo "70" ; log "⚙️ Building iOS IPA with version $APP_VERSION and build number $BUILD_NUMBER..."
        flutter build ipa --release --export-method development --build-name="$APP_VERSION" --build-number="$BUILD_NUMBER" 2>&1 | while IFS= read -r line; do
          log "$line"
          echo "XXX"
          echo "85"
          echo "Building iOS IPA...\n\n$line"
          echo "XXX"
        done

        log "✅ iOS IPA build complete!"
      fi
    fi

    echo "100" ; log "✅ Build complete!" ; sleep 1
  ) | dialog --title "⚙️ Building App" --gauge "Building..." 10 100 0

  # Show full build log after completion
  dialog --title "📜 Build Log" --msgbox "Build completed! Press OK to view full log." 8 50
  show_log


# --- Step 3: Handle distribution ---
BUILT_ARTIFACTS=()
if [ "$BUILD_ANDROID" = true ] && [ -f "$APK_OUTPUT" ]; then
  BUILT_ARTIFACTS+=("Android APK")
fi
if [ "$BUILD_IOS" = true ] && [ -f "$IPA_OUTPUT" ]; then
  BUILT_ARTIFACTS+=("iOS IPA")
fi

if [ ${#BUILT_ARTIFACTS[@]} -eq 0 ]; then
  dialog --msgbox "❌ No build artifacts found!\n\nExpected locations:\nAndroid: $APK_OUTPUT\niOS: $IPA_OUTPUT" 12 70
  exit 1
fi

# Build menu items dynamically
MENU_ITEMS=()
MENU_INDEX=1

if [ "$BUILD_ANDROID" = true ] && [ -f "$APK_OUTPUT" ]; then
  MENU_ITEMS+=("$MENU_INDEX" "Install Android APK on device (ADB)")
  ((MENU_INDEX++))
  MENU_ITEMS+=("$MENU_INDEX" "Upload Android APK to Firebase")
  ((MENU_INDEX++))
fi

if [ "$BUILD_IOS" = true ] && [ -f "$IPA_OUTPUT" ]; then
  MENU_ITEMS+=("$MENU_INDEX" "Upload iOS IPA to Firebase")
  ((MENU_INDEX++))
fi

MENU_ITEMS+=("$MENU_INDEX" "Just finish (builds ready)")

OPTION=$(dialog --title "📦 Distribution" --menu "Choose how to distribute:" 18 60 $((MENU_INDEX)) \
  "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3)

# Parse selection
CURRENT_INDEX=1

# Android ADB install
if [ "$BUILD_ANDROID" = true ] && [ -f "$APK_OUTPUT" ]; then
  if [ "$OPTION" == "$CURRENT_INDEX" ]; then
    if ! command -v adb &> /dev/null; then
      dialog --msgbox "❌ ADB not found. Please install Android platform-tools." 10 50
      exit 1
    fi

    {
      log "📲 Installing APK via ADB..."
      adb install -r "$APK_OUTPUT" >> "$LOG_FILE" 2>&1
      log "✅ APK installed successfully."
    } | dialog --title "📲 Installing" --progressbox "Installing APK..." 20 80
  fi
  ((CURRENT_INDEX++))
  
  # Android Firebase upload
  if [ "$OPTION" == "$CURRENT_INDEX" ]; then
    if ! command -v firebase &> /dev/null; then
      dialog --msgbox "❌ Firebase CLI not found. Please install it with:\n\nnpm install -g firebase-tools" 10 60
      exit 1
    fi
    if ! firebase projects:list &> /dev/null; then
      dialog --msgbox "❌ Not logged into Firebase.\nPlease run: firebase login" 10 50
      exit 1
    fi

    {
      log "📤 Uploading Android APK to Firebase App Distribution..."
      firebase appdistribution:distribute "$APK_OUTPUT" \
        --app "$FIREBASE_ANDROID_APP_ID" \
        --groups "testers" \
        --release-notes "Version $APP_VERSION (Build $BUILD_NUMBER)" >> "$LOG_FILE" 2>&1

      log "✅ Android APK successfully uploaded to Firebase!"
    } | dialog --title "📤 Uploading" --progressbox "Uploading Android APK to Firebase..." 20 80
  fi
  ((CURRENT_INDEX++))
fi

# iOS Firebase upload
if [ "$BUILD_IOS" = true ] && [ -f "$IPA_OUTPUT" ]; then
  if [ "$OPTION" == "$CURRENT_INDEX" ]; then
    if ! command -v firebase &> /dev/null; then
      dialog --msgbox "❌ Firebase CLI not found. Please install it with:\n\nnpm install -g firebase-tools" 10 60
      exit 1
    fi
    if ! firebase projects:list &> /dev/null; then
      dialog --msgbox "❌ Not logged into Firebase.\nPlease run: firebase login" 10 50
      exit 1
    fi

    {
      log "📤 Uploading iOS IPA to Firebase App Distribution..."
      firebase appdistribution:distribute "$IPA_OUTPUT" \
        --app "$FIREBASE_IOS_APP_ID" \
        --groups "testers" \
        --release-notes "Version $APP_VERSION (Build $BUILD_NUMBER)" >> "$LOG_FILE" 2>&1

      log "✅ iOS IPA successfully uploaded to Firebase!"
    } | dialog --title "📤 Uploading" --progressbox "Uploading iOS IPA to Firebase..." 20 80
  fi
  ((CURRENT_INDEX++))
fi

# Just finish option
if [ "$OPTION" == "$CURRENT_INDEX" ]; then
  log "✅ Builds are ready:"
  [ "$BUILD_ANDROID" = true ] && [ -f "$APK_OUTPUT" ] && log "   Android APK: $APK_OUTPUT"
  [ "$BUILD_IOS" = true ] && [ -f "$IPA_OUTPUT" ] && log "   iOS IPA: $IPA_OUTPUT"
fi

# --- Final ---
show_log
show_final_summary "success" "$APP_VERSION" "$BUILD_NUMBER"
clear
echo "🎉 Done! Version $APP_VERSION (build $BUILD_NUMBER) processed."
[ "$BUILD_ANDROID" = true ] && [ -f "$APK_OUTPUT" ] && echo "   📦 Android APK: $APK_OUTPUT"
[ "$BUILD_IOS" = true ] && [ -f "$IPA_OUTPUT" ] && echo "   📦 iOS IPA: $IPA_OUTPUT"
echo "📄 Full log available at: $LOG_FILE"
echo "📄 Or access via: $LATEST_LOG_LINK"