# tracken

Codex와 Anthropic의 토큰 사용량을 한곳에서 확인하는 macOS 메뉴 막대 앱입니다. 메인 대시보드와 메뉴 막대 팝오버에서 최근 14일 사용량과 공급자별 사용 현황을 확인할 수 있습니다.

> [!IMPORTANT]
> Codex 사용량은 로컬 Codex CLI에 로그인된 ChatGPT 계정에서 가져옵니다. Claude(Anthropic)의 실제 사용량 연동은 아직 지원하지 않습니다. 사용량과 비용은 `—`, 연결 상태는 `Not supported yet`으로 표시하며 합계에도 포함하지 않습니다. 이전 버전에 표시된 Claude 수치는 실제 사용량이 아닌 모의 데이터였습니다.
>
> Codex 비용은 실제 청구액이 아니라 로컬 세션의 모델별 토큰에 OpenAI 표준 API 단가를 적용한 참고용 예상치입니다. ChatGPT 구독료나 요금제 포함 사용량을 뜻하지 않습니다.

## 실행 화면

계정 정보를 노출하지 않도록 문서용 샘플 데이터를 사용했습니다.

### 메인 대시보드

![tracken 메인 대시보드](docs/images/dashboard.png)

### 메뉴 막대

<img src="docs/images/menu-bar.png" alt="tracken 메뉴 막대 화면" width="360">

## 주요 기능

- Codex(ChatGPT)와 Claude(Anthropic) 공급자 전환
- 최근 14일간의 일별 토큰 차트 및 상세 목록
- 일별 토큰과 예상 비용을 함께 표시
- Codex 로컬 세션을 기반으로 일자별·모델별 토큰과 API 환산 예상 비용 표시
- Codex 사용 한도·초기화 시각 표시 및 Claude 연동 미지원 상태 안내
- 메뉴 막대에서 공급자별 사용량 빠르게 확인
- 전체 또는 공급자별 사용량 새로고침
- Codex CLI의 기존 ChatGPT 로그인 재사용
- 이전 버전에서 macOS 키체인에 저장한 Anthropic API 키 제거
- 연결 해제 시 계정 세션 또는 저장된 키와 해당 공급자의 사용량 제거

## 요구 사항

- macOS 26.3 이상
- Swift 5
- 프로젝트를 빌드할 수 있는 Xcode
- Codex 사용량 연동 시 로컬 Codex CLI

배포 대상 버전은 Xcode 프로젝트의 `MACOSX_DEPLOYMENT_TARGET` 설정을 따릅니다.

## 시작하기

1. 저장소를 클론합니다.

   ```bash
   git clone https://github.com/jaynamm/tracken.git
   cd tracken
   ```

2. `tracken.xcodeproj`를 Xcode에서 엽니다.

   ```bash
   open tracken.xcodeproj
   ```

3. `tracken` 스킴과 실행할 Mac을 선택한 뒤 `⌘R`로 앱을 실행합니다.

앱은 메인 창과 메뉴 막대 항목을 함께 제공합니다. Dock에는 별도의 앱 아이콘을 유지하지 않습니다.

## 사용 방법

1. 메인 화면의 톱니바퀴 버튼을 누르거나 macOS 설정 단축키 `⌘,`로 설정을 엽니다.
2. Codex는 **Connect with ChatGPT**를 눌러 로컬 Codex CLI 계정을 연결합니다. Claude는 실제 사용량 연동이 구현될 때까지 미지원 상태로 표시됩니다.
3. 대시보드에서 공급자를 선택해 최근 14일 사용량을 확인합니다.
4. 새로고침 버튼으로 연결된 공급자의 데이터를 다시 불러옵니다.
5. 연결을 해제하려면 설정에서 Codex의 **Sign out** 또는 Anthropic의 **Remove saved API key**를 누릅니다.

Claude 설정에서는 새 API 키를 입력받지 않습니다. 이전 버전의 저장된 키는 **Remove saved API key**로 삭제할 수 있습니다. 조회 미지원 상태는 사용량이 0이라는 뜻이 아닙니다.

## 프로젝트 구조

```text
├── Configuration/               # Info.plist 등 빌드 구성
└── tracken/
    ├── App/                     # 앱 진입점과 단일 인스턴스 관리
    ├── Features/
    │   ├── Dashboard/           # 화면, 사용량 카드, 일별 차트
    │   ├── MenuBar/             # 메뉴 막대 팝오버
    │   └── Settings/            # Codex/API 키 연결 화면
    ├── Models/                  # UI와 독립적인 도메인 모델
    ├── Services/                # App Server, 사용량, 키체인 접근
    ├── Stores/                  # 앱 상태 및 새로고침 조정
    ├── Utilities/               # 표시 형식과 UI 표현 속성
    └── Resources/               # 앱 색상과 아이콘 에셋
```

## 기술 구성

- SwiftUI: 메인 창, 설정 창, 메뉴 막대 UI
- Swift Charts: 최근 14일 토큰 사용량 시각화
- Observation: 공유 사용량 및 연결 상태 관리
- Security/Keychain Services: 공급자 API 키 저장
- Swift Concurrency: 공급자별 비동기 새로고침

## 공급자 연동 상태

Codex는 `CodexAppServerTransport.swift`가 `codex app-server` JSONL 통신을 담당하고, `CodexAppServerClient.swift`가 응답을 앱 모델로 변환합니다. 로컬 CLI의 로그인 계정, 일별 사용량, 사용 한도를 읽으며 ChatGPT 인증 정보는 앱에서 직접 취급하지 않습니다.

Codex 계정 요약은 모델별 사용량과 비용을 제공하지 않으므로 `CodexSessionCostEstimator.swift`가 최근 14일의 로컬 세션에서 날짜, 모델명, 입출력·캐시 토큰 메타데이터만 추출합니다. 일별 총 토큰은 계정 요약 값을 우선하고, 모델별 예상 비용은 [OpenAI 표준 API 단가](https://developers.openai.com/api/docs/pricing)의 입력·캐시 입력·캐시 쓰기·출력 요율을 별도로 적용합니다. 단가를 알 수 없는 모델은 임의로 계산하지 않고 `Rate unavailable`로 표시합니다.

Codex의 누적 토큰 증가분은 오늘 사용량으로 임의 배분하지 않습니다. 서버가 해당 날짜의 합계를 제공하면 그 값을 사용하고, 날짜가 없는 경우에만 로컬 기록을 사용합니다. 계정 응답의 최신 `rateLimitsByLimitId.codex`를 우선합니다. 로컬 모델별 비용은 이 Mac의 기록에 한정되며, 다른 기기의 사용량까지 포함하는 계정 전체 비용이 아닙니다.

로컬 기록은 대화 생성 날짜와 관계없이 조회 기간 안의 토큰 이벤트를 집계합니다. 중복 응답 ID와 누적값이 같은 구형 알림은 한 번만 계산합니다. 알려진 GPT-5.6 모델의 272K 초과 입력에는 긴 컨텍스트 단가를 적용하며, 단가를 모르는 모델이 포함된 합계는 `—`로 표시합니다. 개별 모델의 단가 미지원 상태를 구독에 포함된 비용으로 표시하지 않습니다.

Anthropic은 `tracken/Services/UsageService.swift`의 `UnavailableAnthropicUsageService`를 사용합니다. 실제 API 요청이나 모의 데이터 생성 없이 미지원 상태를 반환합니다. 저장된 API 키가 있어도 연결 성공으로 처리하지 않으며 토큰·비용을 생성하지 않습니다.

향후 실제 연동을 추가할 때는 `AnthropicUsageProviding` 구현을 교체하고 인증 방식, 조회 기간, 페이지네이션, 공급자 응답 집계와 오류 처리를 구현해야 합니다.

## 보안 참고 사항

Codex의 OAuth 인증 정보는 로컬 Codex CLI가 관리하며 앱으로 전달되지 않습니다. 비용 계산기는 로컬 세션에서 필요한 메타데이터만 디코딩하고 외부로 전송하거나 별도로 저장하지 않습니다. 이전 버전의 Anthropic API 키는 서비스 식별자 `com.tracken.apikeys`로 macOS 키체인에 저장되어 있으며 설정에서 삭제할 수 있습니다. 현재 Anthropic 구현은 저장된 키를 조회하거나 외부로 전송하지 않고, 새 키도 저장하지 않습니다.

## 집계 검증 및 빌드

실제 계정이나 API 키를 사용하지 않는 회귀 테스트:

```bash
./Scripts/test-usage.sh
```

Release 빌드:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project tracken.xcodeproj -scheme tracken -configuration Release -derivedDataPath DerivedData CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
```

빌드 결과는 `DerivedData/Build/Products/Release/tracken.app`에 생성됩니다.
