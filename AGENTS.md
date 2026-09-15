# AGENTS.md — MyGame (Godot 4.7 / .NET 빌드)

이 저장소에서 작업하는 **모든 사람과 모든 AI 에이전트**가 따르는 규칙입니다.
Cline(`AGENTS.md` + `.clinerules/`), Cursor, Codex, Claude Code 등이 공통으로 읽습니다.
(`AGENTS.md`는 도구 중립 표준이라 팀원이 어떤 에이전트를 쓰든 동일하게 적용됩니다.)

## 1. 엔진 / 툴체인 고정

| 항목 | 값 |
|---|---|
| Godot | **4.7.x stable (mono / .NET 빌드)** — `4.7.2` 기준 |
| 렌더러 | Forward+ (`project.godot` → `config/features`) |
| 주 언어 | GDScript (C# 도입은 팀 합의 후) |
| MCP 플러그인 | `addons/godot_ai` = **Godot AI 4.1.0** (버전 고정, 손으로 수정 금지) |
| 테스트 | `res://tests/test_*.gd` (`McpTestSuite`), MCP `test_run`으로 실행 |
| 에셋 생성(선택) | `assets/**` 재생성 시에만 Python 3 + Pillow 필요 (`docs/assets.md`) |

- 엔진 버전 업그레이드는 **단독 PR**로만 합니다. 업그레이드하면 `.tscn`/`.tres`/`.uid`가 전부 재저장되어 수천 줄 diff가 나므로 다른 변경과 섞으면 리뷰가 불가능합니다.
- 팀원 전원이 같은 4.7.x를 씁니다. 다른 4.7.x로 열어 저장하면 씬 포맷이 흔들립니다.

## 2. 디렉터리 규칙

```text
res://
  scenes/     # .tscn — 기능 단위로 잘게 분할 (한 씬 = 한 오너)
  scripts/    # .gd — 파일명 snake_case, class_name은 PascalCase
  assets/
	art/      # 이미지/텍스처 (LFS) — easyrtp/ 는 생성물
	audio/    # 사운드/음악 (LFS) — easyrtp/ 는 생성물
	fonts/    # 폰트 (LFS)
	models/   # 3D 모델 (LFS)
  tests/      # test_*.gd — 하위 폴더는 스캔되지 않음
  addons/     # Godot 에디터 플러그인 (수정 금지, 버전 고정 커밋)
  third_party/ # 플러그인 형태가 아닌 외부 코드/프레임워크 (수정 금지)
  tools/      # 팀 공용 스크립트 (PowerShell) — easyrtp_prepare.py 는 예외적으로 Python
  docs/       # 문서
```

새 최상위 폴더를 추가하기 전에 팀에 공유합니다.
- **`addons/`·`third_party/`는 손으로 고치지 않습니다.** 갱신은 원본을 통째로 교체하고 `third_party/README.md`의 핀 표를 갱신하는 방식으로만 합니다.
- **`assets/art/easyrtp/**`·`assets/audio/easyrtp/**`·`assets/easyrtp.manifest.json`은 생성물입니다.** 손으로 고치지 않고 `powershell -File tools/prepare-easyrtp.ps1`로 재생성합니다(파이프라인 설명: `docs/assets.md`). 커밋된 자산이 매니페스트와 일치하는지는 `-Check`로 확인합니다.
- `third_party/gbm2k`는 원본 절대 경로(`res://Scripts/` 등)를 `res://third_party/gbm2k/...`로 재작성해 둔 상태입니다. 다시 받을 때도 같은 재작성이 필요합니다(`third_party/README.md` 4절).
- 부득이하게 내부를 고쳐야 한다면 "우리가 포크했다"는 뜻이므로 PR 본문에 사유를 적습니다.


## 3. 코드 스타일 (Godot 공식 GDScript 스타일 가이드)

- 들여쓰기는 **탭**(공백 금지). 씬과 스크립트가 섞이면 diff가 망가집니다.
- 파일명 `snake_case.gd`, 노드명 `PascalCase`, 상수 `SCREAMING_SNAKE_CASE`.
- 정적 타이핑 우선: `var speed: float = 300.0`, `func _ready() -> void:`.
- `class_name` 남용 금지(전역 네임스페이스 오염).
- 디버그 출력은 커밋 전에 제거. `push_error`/`push_warning`이 남지 않는지 확인합니다.

## 4. 씬(.tscn) 충돌 정책 — 가장 중요

씬은 텍스트라 git이 병합을 시도하지만, **의미 충돌은 조용히 깨집니다.**

- 한 씬을 두 사람이 동시에 수정하지 않습니다. 큰 씬은 SubScene으로 쪼개 서로 다른 파일을 건드립니다.
- `.tscn`/`.tres` 충돌 시 자동 병합을 믿지 말고, 한쪽을 기준으로 에디터에서 열어 **다시 저장**해 해결합니다.
- `project.godot`는 공용 파일(오토로드/입력맵/플러그인)입니다. 수정하면 PR 본문에 반드시 적습니다.
- 씬 저장은 **에디터에서만**. 손으로 `.tscn`을 작성하거나 정규식으로 편집하지 않습니다(포맷/UID 깨짐).

## 5. 테스트

- 위치: `res://tests/test_*.gd`, `extends McpTestSuite`, `func suite_name()`, 동기 `func test_*()`만.
- 실행: 에디터에 연결된 MCP의 `test_run` (단일 실행 300초 예산, 테스트당 ~20초 이내 권장).
- 로직 변경 PR은 테스트를 동반합니다. 최소 "씬이 인스턴스화된다 / 핵심 수치가 유지된다"를 검증합니다.
- 현재 스위트: `project`(프로젝트 설정·플러그인·메인 씬), `assets`(EasyRTP 자산과 GBM2K `coll_type` 계약).

## 6. AI 에이전트(MCP) 사용 규칙

- 파일 도구 op는 `read_text`, `write_text`, `reimport`, `scan`, `search` 입니다 (`read_file`/`write_file` 아님).
- `script_create`/`script_attach`/`script_patch`는 **GDScript 전용**입니다. C#은 일반 파일 편집으로 다룹니다.
- **에디터 1개 = MCP 클라이언트 1개**를 권장합니다. 브리지를 여러 개 동시에 띄우면 capability가 회전해 플러그인이 재탐색 루프에 들어갈 수 있습니다.
- 테스트 실행 중 다른 클라이언트의 명령은 `EDITOR_NOT_READY (EDITOR_TEST_RUNNING)`로 거절될 수 있습니다(정상 — 재시도).
- 한국어 Windows 로케일에서는 서버에 `PYTHONUTF8=1`이 필요합니다(설치 스크립트가 자동 설정).
- `--allow-host`로 에디터 포트를 LAN에 열지 않습니다. capability 토큰은 `%LOCALAPPDATA%\godot-ai\capabilities`에 있으며 저장소에 들어오면 안 됩니다.
- 에이전트는 커밋 전 `test_run`을 실행하고, 실패하면 고친 뒤 결과와 함께 보고합니다.

## 7. 커밋 / PR

- 접두어: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `test:` + 명령형 한 줄 요약.
- 한 커밋 = 한 논리 변경. 대량 씬 재저장은 별도 커밋으로 분리합니다.
- 새 바이너리 확장자를 추가하면 `.gitattributes`의 LFS 패턴도 함께 수정합니다.
- 금지: `.godot/`, `export_credentials.cfg`, 빌드 산출물, `addons/godot_ai` 수동 수정 커밋.

## 8. 하지 말 것

- `.godot/` 커밋 또는 `git add -f`로 강제 추가
- `addons/godot_ai/**` 손으로 패치 (플러그인 갱신은 릴리스 교체로만)
- `*.uid` 삭제 또는 ignore 목록 추가
- **대소문자만 다른 파일명** 추가 — Windows는 구분하지 못해 다른 팀원/Linux에서 깨집니다 (`Player.gd` ↔ `player.gd`)
- 엔진 업그레이드와 기능 변경을 한 PR에 혼합
