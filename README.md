# tracken

Codex와 Anthropic의 토큰 사용량을 한곳에서 확인하는 macOS 메뉴 막대 앱입니다. 메인 대시보드와 메뉴 막대 팝오버에서 최근 14일 사용량과 공급자별 사용 현황을 확인할 수 있습니다.

> [!IMPORTANT]
> Codex 사용량은 로컬 Codex CLI에 로그인된 ChatGPT 계정에서 가져옵니다. Claude는 이 Mac에 저장된 Claude Code 세션의 실제 토큰 기록을 API 키 없이 읽습니다. 최근 14일·30일·전체 로컬 기록을 선택할 수 있습니다. Claude 웹과 다른 기기의 기록은 포함하지 않습니다. 이전 버전의 모의 집계는 제거되었습니다.
>
> 비용은 실제 청구액이 아니라 로컬 세션의 모델별 토큰에 현재 공급자 표준 API 단가를 적용한 참고용 예상치입니다. ChatGPT·Claude 구독료나 과거 청구서를 뜻하지 않습니다.

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
- Codex 사용 한도·초기화 시각 및 Claude Code의 과거 일별·모델별 사용량 표시
- 메뉴 막대에서 공급자별 사용량 빠르게 확인
- 전체 또는 공급자별 사용량 새로고침
- Codex CLI의 기존 ChatGPT 로그인 재사용
- 이전 버전에서 macOS 키체인에 저장한 Anthropic API 키 제거
- 저장된 과거 기록이 없는 날짜는 0으로 표시하고, 기록 경로가 없거나 읽지 못하면 상태 안내

## 요구 사항

- macOS 26.3 이상
- Swift 5
- 프로젝트를 빌드할 수 있는 Xcode
- Codex 사용량 연동 시 로컬 Codex CLI
- Claude 과거 사용량 조회 시 로컬 Claude Code 세션 기록

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
2. Codex는 **Connect with ChatGPT**를 눌러 로컬 Codex CLI 계정을 연결합니다. Claude Code의 로컬 기록은 API 키 입력 없이 자동으로 불러옵니다.
3. 대시보드에서 공급자를 선택합니다. Claude는 최근 14일·30일·전체 로컬 기록 중 조회 기간을 선택할 수 있습니다.
4. 새로고침 버튼으로 연결된 공급자의 데이터를 다시 불러옵니다.
5. Codex 연결 해제는 **Sign out**, Claude 기록 재조회는 **Reload history**를 누릅니다. 이전 Anthropic API 키는 **Remove old API key**로 삭제할 수 있습니다.

Claude의 과거 기록은 그대로 보존됩니다. API 키 삭제는 로컬 사용 기록을 지우거나 조회를 끄지 않습니다. 메뉴 막대의 공급자별 사용량과 합계는 대시보드에서 선택한 기간과 관계없이 최근 14일 기준입니다.

## 프로젝트 구조

```text
├── Configuration/               # Info.plist 등 빌드 구성
└── tracken/
    ├── App/                     # 앱 진입점과 단일 인스턴스 관리
    ├── Features/
    │   ├── Dashboard/           # 화면, 사용량 카드, 일별 차트
    │   ├── MenuBar/             # 메뉴 막대 팝오버
    │   └── Settings/            # Codex 연결 및 Claude 기록 설정
    ├── Models/                  # UI와 독립적인 도메인 모델
    ├── Services/                # App Server, 사용량, 키체인 접근
    ├── Stores/                  # 앱 상태 및 새로고침 조정
    ├── Utilities/               # 표시 형식과 UI 표현 속성
    └── Resources/               # 앱 색상과 아이콘 에셋
```

## 기술 구성

- SwiftUI: 메인 창, 설정 창, 메뉴 막대 UI
- Swift Charts: 선택한 기간의 일별 토큰 사용량 시각화
- Observation: 공유 사용량 및 연결 상태 관리
- Security/Keychain Services: 이전 버전의 저장된 API 키 제거
- Swift Concurrency: 공급자별 비동기 새로고침

## 공급자 연동 상태

Codex는 `CodexAppServerTransport.swift`가 `codex app-server` JSONL 통신을 담당하고, `CodexAppServerClient.swift`가 응답을 앱 모델로 변환합니다. 로컬 CLI의 로그인 계정, 일별 사용량, 사용 한도를 읽으며 ChatGPT 인증 정보는 앱에서 직접 취급하지 않습니다.

Codex 계정 요약은 모델별 사용량과 비용을 제공하지 않으므로 `CodexSessionCostEstimator.swift`가 최근 14일의 로컬 세션에서 날짜, 모델명, 입출력·캐시 토큰 메타데이터만 추출합니다. 일별 총 토큰은 계정 요약 값을 우선하고, 모델별 예상 비용은 [OpenAI 표준 API 단가](https://developers.openai.com/api/docs/pricing)의 입력·캐시 입력·캐시 쓰기·출력 요율을 별도로 적용합니다. 단가를 알 수 없는 모델은 임의로 계산하지 않고 `Rate unavailable`로 표시합니다.

Codex의 누적 토큰 증가분은 오늘 사용량으로 임의 배분하지 않습니다. 서버가 해당 날짜의 합계를 제공하면 그 값을 사용하고, 날짜가 없는 경우에만 로컬 기록을 사용합니다. 계정 응답의 최신 `rateLimitsByLimitId.codex`를 우선합니다. 로컬 모델별 비용은 이 Mac의 기록에 한정되며, 다른 기기의 사용량까지 포함하는 계정 전체 비용이 아닙니다.

로컬 기록은 대화 생성 날짜와 관계없이 조회 기간 안의 토큰 이벤트를 집계합니다. 중복 응답 ID와 누적값이 같은 구형 알림은 한 번만 계산합니다. 알려진 GPT-5.6 모델의 272K 초과 입력에는 긴 컨텍스트 단가를 적용하며, 단가를 모르는 모델이 포함된 합계는 `—`로 표시합니다. 개별 모델의 단가 미지원 상태를 구독에 포함된 비용으로 표시하지 않습니다.

Claude는 `ClaudeSessionUsageService.swift`가 [Claude Code 로컬 세션](https://code.claude.com/docs/en/sessions)의 `~/.claude/projects/**/*.jsonl`에서 타임스탬프, 응답 ID, 모델명, 사용량 메타데이터를 읽습니다. `CLAUDE_CONFIG_DIR` 환경 변수가 설정된 경우 해당 디렉터리 아래의 `projects`를 사용합니다. 기록 읽기는 모델 호출을 발생시키지 않습니다.

같은 응답의 여러 콘텐츠 블록이나 복사된 세션은 메시지 ID와 요청 ID로 중복을 제거하고, 스트리밍 중 늘어난 출력 토큰은 최종값을 한 번만 반영합니다. Claude의 입력 합계는 일반 입력·캐시 읽기·캐시 생성 토큰을 합한 값입니다. 캐시 생성 비용에는 5분·1시간 TTL을 구분합니다. [현재 Anthropic 단가](https://platform.claude.com/docs/en/about-claude/pricing)를 확인한 Sonnet 5, Opus 5, Opus 4.8, Fable 5의 표준 모드를 계산하며, 미등록 모델이나 가격 모드는 토큰을 표시하되 비용은 `—`로 남깁니다.

전체 로컬 기록은 현재 Mac에 남아 있는 파일 범위입니다. 삭제된 기록, Claude 웹 채팅, 다른 기기에서만 사용한 내역을 계정 API로 복구하는 기능은 제공하지 않습니다. 기록이 있는 과거 날짜는 보존하고 사용하지 않은 오늘에 과거 사용량을 배분하지 않습니다.

## 보안 참고 사항

Codex의 OAuth 인증 정보는 로컬 Codex CLI가 관리하며 앱으로 전달되지 않습니다. Codex와 Claude의 사용량 계산기는 로컬 세션에서 필요한 메타데이터만 디코딩하고 외부로 전송하거나 별도로 저장하지 않습니다. 이전 버전의 Anthropic API 키는 서비스 식별자 `com.tracken.apikeys`로 macOS 키체인에 저장되어 있으며 설정에서 삭제할 수 있습니다. 현재 Anthropic 구현은 저장된 키를 조회하거나 외부로 전송하지 않고, 새 키도 저장하지 않습니다.

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
