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

## 시간별 갱신과 Claude 한도

앱 시작 시 한 번 불러온 뒤 Codex·Claude 사용량과 Claude 한도 캐시를 1시간마다 확인합니다. 파일 변경이나 대시보드·메뉴 팝오버 열기는 새로고침을 발생시키지 않습니다. 즉시 확인하려면 대시보드나 메뉴의 새로고침 버튼, 설정의 Reload history를 사용합니다. 창을 닫아도 시간별 갱신은 유지되며 앱 자체를 Quit하면 중지됩니다. 가격표는 시간별 확인 중 24시간이 지난 경우에만 다운로드하며, 가격 변경이 있어도 사용량은 해당 주기에 한 번만 읽습니다.

Claude의 5시간·7일 구독 한도는 토큰 수로 추정하지 않고 [공식 상태줄 데이터](https://code.claude.com/docs/en/statusline#rate-limit-usage)에서 받습니다. Claude Code 2.1.251 이상과 Pro/Max 세션의 실제 응답이 필요합니다. 한도값이 아직 없으면 대기 상태를 표시하며, 한도가 초기화될 시각이 지났더라도 0%로 임의 변경하지 않습니다.

한도 수신을 설정하려면 Python 3이 설치된 환경에서 다음을 실행합니다.

```bash
python3 Scripts/install-claude-statusline.py
```

설치 도구는 Claude 설정을 백업하고 기존 상태줄 명령과 출력, 다른 설정을 보존합니다. 브리지는 `~/Library/Application Support/tracken/Claude`에 설치되며, 사용 중인 Claude가 상태줄 데이터를 전달할 때 한도 사용률·초기화 시각·수신 및 값 변경 시각만 로컬 파일에 기록합니다. 대화 내용, 작업 경로, 세션 ID, 인증 정보는 저장하지 않으며 별도 API 요청도 하지 않습니다. 전체 상태줄 입력은 기존 상태줄 명령이 있을 경우 그 명령에 그대로 전달됩니다.

브리지가 기록한 한도 파일도 tracken에서는 시간별 또는 수동 갱신 때만 읽습니다. 화면에는 마지막 수신 시각을 표시합니다. 같은 값이 다시 전달되어도 값 변경 시각은 갱신하지 않으며, 5분 이상 값이 같거나 수신이 없으면 오래된 값일 수 있다고 표시합니다. 이는 서버의 마지막 측정 시각을 보장하는 정보가 아닙니다. 데이터가 없는 창은 `—`, 초기화 시각이 지난 창은 재수신 대기로 표시합니다.

기존 상태줄로 되돌리려면:

```bash
python3 Scripts/install-claude-statusline.py --uninstall
```

설치 후 사용자가 상태줄을 별도로 변경했다면 제거 도구는 그 설정을 덮어쓰지 않습니다. `CLAUDE_CONFIG_DIR`를 사용 중이면 설치 도구와 tracken에도 동일한 설정 경로를 적용해야 합니다.

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
- Swift Charts: 선택한 기간의 일별 예상 비용·토큰 사용량 시각화
- Observation: 공유 사용량 및 연결 상태 관리
- Security/Keychain Services: 이전 버전의 저장된 API 키 제거
- Swift Concurrency: 공급자별 비동기 새로고침

## 공급자 연동 상태

Codex는 `CodexAppServerTransport.swift`가 `codex app-server` JSONL 통신을 담당하고, `CodexAppServerClient.swift`가 응답을 앱 모델로 변환합니다. 로컬 CLI의 로그인 계정, 일별 사용량, 사용 한도를 읽으며 ChatGPT 인증 정보는 앱에서 직접 취급하지 않습니다.

Codex 계정 요약은 모델별 사용량과 비용을 제공하지 않으므로 `CodexSessionCostEstimator.swift`가 최근 14일의 로컬 세션에서 날짜, 모델명, 입출력·캐시 토큰 메타데이터만 추출합니다. 일별 총 토큰은 계정 요약 값을 우선하고, 모델별 예상 비용은 [OpenAI 표준 API 단가](https://developers.openai.com/api/docs/pricing)의 입력·캐시 입력·캐시 쓰기·출력 요율을 별도로 적용합니다. 단가를 알 수 없는 모델은 임의로 계산하지 않고 `Rate unavailable`로 표시합니다.

Codex의 누적 토큰 증가분은 오늘 사용량으로 임의 배분하지 않습니다. 서버가 해당 날짜의 합계를 제공하면 그 값을 사용하고, 날짜가 없는 경우에만 로컬 기록을 사용합니다. 계정 응답의 최신 `rateLimitsByLimitId.codex`를 우선합니다. 로컬 모델별 비용은 이 Mac의 기록에 한정되며, 다른 기기의 사용량까지 포함하는 계정 전체 비용이 아닙니다.

로컬 기록은 대화 생성 날짜와 관계없이 조회 기간 안의 토큰 이벤트를 집계합니다. 중복 응답 ID와 누적값이 같은 구형 알림은 한 번만 계산합니다. 공식 표에 긴 컨텍스트 요금이 있는 모델은 272K 초과 입력에 해당 단가를 적용하며, 단가를 모르는 모델이 포함된 합계는 `—`로 표시합니다. 개별 모델의 단가 미지원 상태를 구독에 포함된 비용으로 표시하지 않습니다.

일부 과거 Codex 기록에는 총 토큰 수만 있고 모델명이나 입력·출력 구분이 없습니다. 이 경우 총 토큰은 보존하고 `Details unavailable`로 표시합니다. 세부 정보가 없어 계산할 수 없는 비용이 포함되면 일별·기간 비용 합계도 `—`로 유지합니다.

Claude는 `ClaudeSessionUsageService.swift`가 [Claude Code 로컬 세션](https://code.claude.com/docs/en/sessions)의 `~/.claude/projects/**/*.jsonl`에서 타임스탬프, 응답 ID, 모델명, 사용량 메타데이터를 읽습니다. `CLAUDE_CONFIG_DIR` 환경 변수가 설정된 경우 해당 디렉터리 아래의 `projects`를 사용합니다. 기록 읽기는 모델 호출을 발생시키지 않습니다.

같은 응답의 여러 콘텐츠 블록이나 복사된 세션은 메시지 ID와 요청 ID로 중복을 제거하고, 스트리밍 중 늘어난 출력 토큰은 최종값을 한 번만 반영합니다. Claude의 입력 합계는 일반 입력·캐시 읽기·캐시 생성 토큰을 합한 값입니다. 캐시 생성 비용에는 5분·1시간 TTL을 구분합니다. [현재 Anthropic 단가](https://platform.claude.com/docs/en/about-claude/pricing)의 모델별 입력·출력·캐시 요금을 적용합니다. 미등록 모델이나 가격 모드, 지원하지 않는 구형 모델의 긴 컨텍스트 요청은 토큰을 표시하되 비용은 `—`로 남깁니다.

전체 로컬 기록은 현재 Mac에 남아 있는 파일 범위입니다. 삭제된 기록, Claude 웹 채팅, 다른 기기에서만 사용한 내역을 계정 API로 복구하는 기능은 제공하지 않습니다. 기록이 있는 과거 날짜는 보존하고 사용하지 않은 오늘에 과거 사용량을 배분하지 않습니다.

## 일별 예상 비용과 가격표 갱신

대시보드 상단에 오늘의 토큰과 예상 비용(USD)을 표시하고, 일별 그래프에서 예상 비용과 토큰을 전환할 수 있습니다. 일별 비용 목록은 모델별 합계보다 먼저 표시됩니다. 사용 기록이 없는 날짜는 $0, 사용량이 있지만 가격을 계산할 수 없는 날짜는 `—`로 표시하며, 일부 날짜나 모델의 비용을 모르면 기간 합계도 부분 합계를 전체 비용처럼 표시하지 않습니다. 1센트 미만의 양수 비용은 `< $0.01`로 구분합니다.

가격표는 공식 OpenAI 가격 문서의 Markdown 표와 Anthropic 가격 문서의 `Accept: text/markdown` 응답에서 읽습니다. 표준 텍스트 토큰 표만 검증해 입력·출력·캐시 읽기·캐시 쓰기와 긴 컨텍스트 단가를 추출합니다. 키나 모델 호출은 필요하지 않습니다. 새로운 모델이 동일한 표 형식으로 추가되면 가격표에 반영됩니다. 날짜 스냅샷 접미사만 기본 모델과 연결하고, 모르는 모델 접미사에 다른 모델의 가격을 적용하지 않습니다.

- 앱 실행 중 공급자별로 24시간마다 확인합니다. ETag/Last-Modified가 있으면 조건부 요청을 사용합니다.
- 로컬 캐시: `~/Library/Application Support/tracken/Pricing/codex.json`, `anthropic.json`.
- 앱을 켜면 저장된 가격으로 먼저 표시하고 갱신합니다. 캐시가 없거나 손상되면 앱에 포함된 2026-09-07 확인 가격표로 시작합니다.
- 다운로드·표 검증·저장 실패 시 기존 가격과 확인 시각을 유지하고 오류를 표시합니다. 자동 재시도는 최소 1시간 간격입니다.
- 설정의 **API price tables**에서 모델별 가격, 출처, 마지막 확인 시각을 확인하고 **Update prices now**로 즉시 갱신할 수 있습니다.

표시 금액은 현재 저장된 API 단가로 사용 기록을 환산한 추정치입니다. 과거 날짜도 가격표 갱신 시 다시 계산되므로 당시 청구서, 구독료, 하루가 끝났을 때의 예측 금액과는 다릅니다. 도구 비용·세금·별도 계약 요금은 포함하지 않습니다. Codex는 표준 API 요금으로 환산하며 Fast/Batch 요금은 적용하지 않습니다.

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
