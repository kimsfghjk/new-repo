# MyGame

Godot **4.7.2 stable (mono / .NET)** 게임 프로젝트. 팀 공동 개발용 저장소입니다.

## 처음 받았다면

1. **[docs/collaboration.md](docs/collaboration.md)** 를 순서대로 따라 하세요 — git-lfs 설치, 엔진 버전, 프로젝트 열기, MCP 연결.
2. AI 에이전트(Cline 등)로 작업한다면 `tools/setup-cline-mcp.ps1`  **1회** 실행하세요.
3. 작업 규칙 원본은 **[AGENTS.md](AGENTS.md)** 입니다 (`.clinerules/` 는 그 요약본).

## 자주 쓰는 명령

| 목적 | 명령 |
|---|---|
| 사전 검사 (헤드리스 임포트 + 스크립트 파싱) | `powershell -ExecutionPolicy Bypass -File .\tools\check-project.ps1` |
| Cline MCP 등록 / 갱신 | `powershell -ExecutionPolicy Bypass -File .\tools\setup-cline-mcp.ps1` |
| 테스트 실행 | 에디터 연결 후 MCP 도구 `test_run` (스위트: `res://tests/`) |

## 구조

```text
scenes/                 .tscn — 기능 단위로 분할 (한 씬 = 한 오너)
scripts/                .gd  — snake_case 파일명
assets/{art,audio,fonts,models}/   Git LFS 자산
tests/                  test_*.gd — McpTestSuite 상속
addons/godot_ai/        Godot AI 4.1.0 (고정 — 손으로 수정 금지)
tools/                  팀 공용 스크립트
docs/                   협업/운영 문서
```

## 절대 하지 말 것

- `.godot/`, `export_credentials.cfg`, 빌드 산출물 커밋
- `addons/godot_ai/**` 수동 수정 (갱신은 리스 교체 + 버전 커밋으로만)
- `*.uid` 삭제 / 대소문자만 다른 파일명 생성
- 엔진 버전 업그레이드와 기능 변경을 한 PR에 섞기