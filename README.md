# Garmin Camera Remote

Garmin Forerunner 165 워치에서 안드로이드 폰의 카메라 셔터를 원격 제어하는 프로젝트입니다.

워치의 START 버튼 또는 화면 터치 한 번으로 폰 카메라를 촬영하고, 방금 찍힌 사진을 워치에서 흑백으로 확인할 수 있습니다(구도 확인용).

## Architecture

```
[Garmin FR165 Widget]                    [Android Companion App]
 ┌──────────────────┐                    ┌──────────────────────┐
 │ RemoteDelegate   │                    │ ConnectIQReceiver    │
 │  (START / Tap)   │──── transmit() ──>│  (Foreground Service)│
 │                  │                    │         │            │
 │ RemoteView       │                    │         ▼            │
 │  (셔터·사진 표시)│<── {status:ok} ───│ ShutterA11yService   │
 │                  │                    │  (셔터 버튼 탐색+클릭)│
 │ CommManager      │<── 사진 조각 ─────│ StillSender          │
 │ PhotoReceiver    │                    │  (새 사진 → 흑백 RLE) │
 └──────────────────┘                    └──────────────────────┘
        ↕ Garmin Connect 앱 경유 (BLE) ↕
```

워치와 폰은 Garmin Connect IQ Communications 모듈을 통해 통신하며, 안드로이드 앱은 AccessibilityService로 카메라 앱의 셔터 버튼을 찾아 클릭합니다. 셔터 뒤 카메라 앱이 저장한 사진을 찾아 약 83×111, 회색 16단계로 줄이고 행 단위 RLE로 압축해 여러 메시지로 나눠 보냅니다. 외부 서버를 거치지 않습니다.

## Requirements

- **워치**: Garmin Forerunner 165 (Connect IQ 지원)
- **폰**: Android 8.0+ (API 26+)
- **필수 앱**: Garmin Connect (워치-폰 간 BLE 브릿지 역할)

### Build Requirements

- Java 17+ (OpenJDK 권장)
- [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) 설치
- Android SDK (API 33)
- 개발자 서명 키 (`developer_key.der`, PKCS#8 DER 형식)

## Build

### Garmin Widget

```bash
# developer_key.der 생성 (최초 1회)
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
rm developer_key.pem

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

설치 후 **설정 > 접근성 > Camera Remote** 에서 접근성 서비스를 활성화합니다. 접근성 서비스는 화면 맨 앞 앱이 카메라 앱(카메라로 바로 열리도록 등록된 앱)일 때만 셔터를 누르고, 다른 앱에서는 아무것도 누르지 않습니다. 앱을 처음 열 때 사진 접근을 허용해야 워치에 사진이 뜹니다(거부하면 셔터만 동작).

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
| Sending | "Sending photo..." → 사진이 위에서부터 채워지고 진행 막대 | 셔터 후 사진 받는 중 |
| Photo | 방금 찍은 사진 | 탭·BACK으로 닫기, START로 다시 찍기 |
| Partial | 사진 + "Partial" | 조각이 8초 넘게 끊겨 일부만 받음 |
| Photo not received | 문구 | 셔터 후 15초 안에 사진이 오지 않음 |
| Photo access off | 문구 | 폰 앱에 사진 접근 권한이 없음 |
| Open camera on phone | 문구 | 폰 화면에 카메라 앱이 떠 있지 않아 아무것도 누르지 않음 |
| Shutter failed | 문구 | 카메라 앱에서 셔터 버튼을 찾지 못했거나 접근성 서비스가 꺼져 있음 |
| Not Connected | "No Phone" 표시 | 폰 연결 안 됨 |

사진은 셔터부터 약 10~19초 뒤에 다 뜹니다. 폰에서 카메라 앱이 켜져 있으면 전송이 느려집니다.

## 전송 실측

실시간 미리보기는 블루투스 전송이 너무 느려(가장 작은 프레임도 초당 1장 미만) 포기하고, 촬영 직후 사진 1장으로 범위를 줄였습니다.
측정 결과와 측정 앱(`garmin_bench/`) 사용법은 [docs/PREVIEW_BENCH.md](docs/PREVIEW_BENCH.md)를 보세요.

## Credit

This project was built with the help of [Claude Code](https://claude.ai/claude-code).

## License

[MIT](LICENSE)
