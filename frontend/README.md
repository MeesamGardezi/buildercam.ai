# BuilderCam Transcription App

Flutter frontend for SOW transcription and project tracking.

## Run Locally

1. Start the backend API in `backend_module` (default: port `3001`).
2. In this folder, install dependencies:

```bash
flutter pub get
```

## Android Device (Wireless) - SM S908E

Use your machine LAN IP for backend access and target the wireless ADB device:

```bash
flutter run -d adb-R5CT51VGVWX-ho9T8o._adb-tls-connect._tcp --dart-define=BUILDERCAM_SOW_PROXY_BASE_URL=http://192.168.100.4:3001
```

## Android Emulator

For emulator runs, no override is required because the app defaults to:

`http://10.0.2.2:3001`
