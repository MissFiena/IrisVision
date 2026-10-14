# IRISVISION

**AI-Powered Mobile Assistant with Object Detection and Text Recognition for Visually Impaired Students in Malaysia**

IRISVISION is a Flutter Android app that helps visually impaired students at secondary and higher education levels in Malaysia understand their surroundings. It detects objects through the phone camera, reads printed text aloud, and speaks results in Bahasa Malaysia and English. Everything runs on the device, so it works offline.

> Final Year Project (DER3982), Bachelor of Software Engineering (Education Software), Universiti Pendidikan Sultan Idris (UPSI).

---

## Features

| Feature | Description | Status |
|---|---|---|
| Object detection | Real-time detection using YOLOv8n (TFLite, 80 COCO classes) with bounding boxes | 🟡 In progress |
| Text recognition (OCR) | Voice-triggered snapshot scan using Google ML Kit, fully on-device | 🔜 Planned |
| Text-to-speech | Bilingual audio output (Bahasa Malaysia + English) via Flutter TTS | 🔜 Planned |
| Voice commands | Hands-free control of the app | 🔜 Planned |
| Accessibility UI | Shake-to-repeat, auto voice announcements, screen reader support | 🔜 Planned |

---

## Tech Stack

- **Framework:** Flutter (Dart)
- **Object detection:** YOLOv8n → TensorFlow Lite (`tflite_flutter`)
- **OCR:** Google ML Kit Text Recognition
- **Text-to-speech:** `flutter_tts`
- **Camera:** `camera` plugin
- **Tools:** VS Code, Android Studio
- **Platform:** Android (minSdk 24)

---

## Getting Started

### Requirements

- Flutter SDK (stable)
- Android Studio + Android SDK
- An Android phone with camera (Android 7.0 / API 24 or above)

### Installation

```bash
git clone https://github.com/missfiena/irisvision.git
cd irisvision
flutter pub get
flutter run
```

### Model

The YOLOv8n model is converted to TFLite using `convert_yolo.py`:

```bash
pip install ultralytics
python convert_yolo.py
```

Place the generated `.tflite` file in `assets/models/` and make sure it is listed in `pubspec.yaml`.

---

## Project Structure

```
lib/
├── main.dart                     # App entry point
├── services/
│   └── tflite_service.dart       # Model loading, inference, NMS
└── views/
    └── live_detection_view.dart  # Camera preview + detection overlay
assets/
├── models/                       # yolov8n.tflite
└── labels/                       # Class labels
convert_yolo.py                   # YOLOv8 → TFLite export script
```

---

## Development Roadmap

The project follows an **Incremental** development model.

1. **Increment 1:** Object detection (YOLOv8 + TFLite)
2. **Increment 2:** Text recognition (Google ML Kit OCR)
3. **Increment 3:** Voice assistant, bilingual TTS and data storage

---

## Permissions

| Permission | Purpose |
|---|---|
| `CAMERA` | Object detection and text scanning |
| `RECORD_AUDIO` | Voice commands |

---

## Supporting SDGs

- **SDG 4:** Quality Education
- **SDG 10:** Reduced Inequalities

---

## Author

**Shafiena binti Usri**
Software Engineering student, UPSI
GitHub: [@missfiena](https://github.com/missfiena)

**Supervisor:** Dr. Ahmad Wiraputra bin Selamat

---

## License

This project is developed for academic purposes as part of a Final Year Project at UPSI.