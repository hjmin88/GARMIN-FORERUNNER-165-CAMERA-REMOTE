# Garmin Camera Remote

Garmin Forerunner 165 워치에서 안드로이드 폰의 카메라 셔터를 원격 제어하는 프로젝트입니다.

워치의 START 버튼 또는 화면 터치 한 번으로 폰 카메라를 촬영할 수 있습니다.

## Architecture

```
[Garmin FR165 Widget]                    [Android Companion App]
 ┌──────────────────┐                    ┌──────────────────────┐
 │ RemoteDelegate   │                    │ ConnectIQReceiver    │
 │  (START / Tap)   │──── transmit() ──>│  (Foreground Service)│
 │                  │                    │         │            │
 │ RemoteView       │                    │         ▼            │
 │  (3-state UI)    │<── {status:ok} ───│ ShutterA11yService   │
 │                  │                    │  (셔터 버튼 탐색+클릭)│
 │ CommManager      │                    │                      │
 └──────────────────┘                    └──────────────────────┘
        ↕ Garmin Connect 앱 경유 (BLE) ↕
```

워치와 폰은 Garmin Connect IQ Communications 모듈을 통해 통신하며, 안드로이드 앱은 AccessibilityService로 카메라 앱의 셔터 버튼을 찾아 클릭합니다.

## Requirements

- **워치**: Garmin Forerunner 165 (Connect IQ 지원)
- **폰**: Android 8.0+ (API 26+)
- **필수 앱**: Garmin Connect (워치-폰 간 BLE 브릿지 역할)

### Build Requirements

- Java 17+ (OpenJDK 권장)
- [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) 설치
- Android SDK (API 33)
- 개발자 서명 키 (`developer_key.der`, PKCS#1 DER 형식)

## Build

### Garmin Widget

```bash
# developer_key.der 생성 (최초 1회)
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -outform DER -out developer_key.der

# 빌드
monkeyc -d fr165 -f garmin_app/monkey.jungle -o garmin_app/bin/CamRemote.prg -y developer_key.der
```

> `monkeyc`가 PATH에 없으면 Connect IQ SDK 설치 경로의 `bin/monkeyc`를 직접 지정하세요.

### Android Companion App

```bash
export JAVA_HOME="<your-java-home-path>"
export ANDROID_HOME="$HOME/Library/Android/sdk"

cd android_app
./gradlew assembleDebug
```

APK 출력 경로: `android_app/app/build/outputs/apk/debug/app-debug.apk`

## Installation

### Garmin Widget

빌드된 `CamRemote.prg` 파일을 워치의 `GARMIN/APPS/` 폴더에 복사합니다.

```bash
# USB로 워치 연결 후
cp garmin_app/bin/CamRemote.prg /Volumes/GARMIN/GARMIN/APPS/
```

### Android App

```bash
adb install android_app/app/build/outputs/apk/debug/app-debug.apk
```

설치 후 **설정 > 접근성 > Camera Remote** 에서 접근성 서비스를 활성화합니다.

## Usage

1. 폰에서 **Garmin Connect** 앱이 실행 중이고 워치와 연결된 상태 확인
2. 폰에서 **Camera Remote** 앱 실행 (백그라운드 서비스 시작)
3. 폰에서 **카메라 앱** 열기
4. 워치에서 **CamRemote** 위젯 실행
5. **START 버튼** 또는 **화면 터치** → 촬영!

### Watch UI States

| 상태 | 화면 | 의미 |
|------|------|------|
| Ready | 흰색 원형 셔터 버튼 | 촬영 준비 완료 |
| Sent | 초록색 체크마크 | 셔터 명령 전송됨 |
| Not Connected | "No Phone" 표시 | 폰 연결 안 됨 |

## 미리보기 전송 실측 (개발 중)

시계에서 폰 카메라 미리보기를 보는 기능을 검토 중입니다. 먼저 블루투스로 흑백 저해상도 프레임을
얼마나 빠르게 보낼 수 있는지 측정 전용 앱(`garmin_bench/`)으로 잽니다. 절차는
[docs/PREVIEW_BENCH.md](docs/PREVIEW_BENCH.md)를 보세요.

## Credit

This project was built with the help of [Claude Code](https://claude.ai/claude-code).

## License

[MIT](LICENSE)
