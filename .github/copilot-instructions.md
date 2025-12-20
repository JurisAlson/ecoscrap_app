# EcoScrap App - AI Coding Agent Instructions

## Architecture Overview
This is a Flutter mobile app for identifying recyclable materials via image detection and mapping collection points. The app uses Firebase for authentication and data storage, with Google Maps integration for geolocation features.

**Key Components:**
- **Authentication**: Firebase Auth with email/password (see `lib/login_page.dart`, `lib/create_account.dart`, `lib/forgot_password.dart`)
- **Dashboard**: Main hub with navigation to features (see `lib/dashboard.dart`)
- **Image Detection**: Camera-based material identification (see `lib/image_detection.dart`)
- **Geo Mapping**: Location-based scrap point mapping (see `lib/geomapping.dart`)

**Data Flow:**
1. App initializes Firebase in `lib/main.dart`
2. User authenticates via login/create account screens
3. Dashboard provides access to image detection (camera permission required) and geo mapping
4. Bottom navigation switches between ImageDetection, Dashboard, and GeoMapping pages

## Developer Workflows
- **Run app**: `flutter run` (requires Android/iOS emulator or device)
- **Build APK**: `flutter build apk --release`
- **Firebase config**: Update `firebase.json` and `lib/firebase_options.dart` for different environments
- **Permissions**: Camera access handled via `permission_handler` package in dashboard

## Project Conventions
- **Navigation**: Use `Navigator.pushReplacement` for bottom nav switches to avoid stack buildup (e.g., in `lib/image_detection.dart` and `lib/geomapping.dart`)
- **State Management**: Stateful widgets for pages with user interactions; use `setState` for UI updates
- **Permissions**: Check and request permissions before accessing features (e.g., camera in `lib/dashboard.dart`)
- **Firebase Integration**: Initialize in `main.dart`; use Firebase Auth for user sessions
- **Assets**: Store images in `assets/images/` and declare in `pubspec.yaml`

## Integration Points
- **Firebase**: Auth and Firestore for user data and material info
- **Google Maps**: Geolocator for user location, google_maps_flutter for map UI
- **Camera**: image_picker and camera packages for image capture
- **Permissions**: permission_handler for Android/iOS camera/location access

## Key Files
- `lib/main.dart`: App entry point and Firebase init
- `lib/dashboard.dart`: Central navigation and permission handling
- `pubspec.yaml`: Dependencies and asset declarations
- `firebase.json`: Firebase project configuration