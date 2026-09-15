# 공동 개발 가이드 — MyGame

저장소를 처음 받은 팀원이 이 문서만 따라 하면 개발 · 테스트 · AI 도구까지 **동일한 환경**이 됩니다.
작업 규칙(코드/씬/커밋)은 `AGENTS.md`가 원본이고, 이 문서는 "환경 세팅 + 워크플로 + 문제 해결"을 다룹니다.

## 0. 준비물

| 항목 | 버전 | 비고 |
|---|---|---|
| Godot | **4.7.2 stable mono(.NET)** | 표준(비-mono) 빌드로는 C# 사용 불가 |
| git + git-lfs | git 2.40+, lfs 3.x | `git lfs install` 1회 필수 |
| uv | 0.5+ | MCP 서버 실행(`uvx`)용 |
| MCP 클라이언트 | Cline CLI 3.x / Cline VS Code 확장 / Claude Code 등 | **1인 1클라이언트** 권장 |
| .NET SDK | 8.0+ | C# 스크립트를 쓸 때만 |

## 1. 저장소 받기 (최초 1회)

```powershell
git clone <REMOTE_URL> MyGame
cd MyGame
git lfs install     # 훅 + 필터 등록 (필수)
git lfs pull        # LFS 자산 실제 파일로 내려받기
```

> LFS 없이 clone하면 이미지/사운드가 130바이트 포인터 파일로 받아집니다.
> 이미 그렇게 받았다면 `git lfs install` 후 `git lfs pull`.

## 2. 프로젝트 열기

1. Godot 4.7.2 mono 실행 → **Import** → 이 저장소의 `project.godot` 선택
2. 프로젝트 → 프로젝트 설정 → 플러그인 → **Godot AI** 가 켜져 있는지 확인 (저장소에 `enabled`로 기록돼 있어 보통 자동 활성)
3. 오른쪽 **Godot AI** 독에서 서버 연결 상태(`connected`) 확인 — 에디터가 MCP 서버를 자동 시작합니다

## 3. MCP 클라이언트 연결 (최초 1회)

### Cline CLI (이 저장소의 기본 경로)

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\setup-cline-mcp.ps1
# Cline 재시작 후: "현재 씬 계층 보여줘"
```

이 스크립트가 하는 일:

- `%USERPROFILE%\.cline\data\settings\cline_mcp_settings.json` 에 `godot-ai` 항목을 **병합**(다른 서버 설정 보존, `.bak` 백업 생성)
- `addons/godot_ai/plugin.cfg` 의 버전을 읽어 `--from godot-ai==<버전>` 으로 **정확히 고정**
- `PYTHONUTF8=1` 주입 (한국어 Windows 콘솔 인코딩 크래시 방지)

### Cline VS Code 확장 / Claude Code / Codex / Cursor / Zed 등

Godot AI 독에서 해당 클라이언트 옆 **Configure** 를 누르거나, 행의 **Run this manually** 명령을 복사해 클라이언트 설정에 붙입니다.

> **중요 — Cline CLI는 예외입니다.**
> 독의 `Configure`는 플러그인에 등록된 경로(예: VS Code 확장용 `%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json`)에만 씁니다.
> **Cline CLI는 설정 파일이 다릅니다**(`~/.cline/data/settings/cline_mcp_settings.json`). CLI 사용자는 반드시 위 설치 스크립트를 쓰세요.
> 또한 Cline CLI는 **프로젝트 폴더 안의 `.cline/mcp.json`을 읽지 않습니다**(실측 확인) → MCP 등록은 저장소로 공유할 수 없고, 팀원 각자가 스크립트를 1회 실행해야 합니다.

## 4. 일상 워크플로

```powershell
git switch main
git pull --ff-only
git switch -c feat/player-controller

# ... 작업 (에디터 + Cline, 필요하면 test_run) ...

git add -A
git commit -m "feat: add player controller"
git push -u origin feat/player-controller
# PR 생성 → 리뷰 → 머지
```

- 브랜치는 **1~2일 안에 머지**합니다. 오래 살수록 `.tscn` 충돌 확률이 급격히 올라갑니다.
- 머지 후 각자 `git pull` → 에디터에서 다시 열기(또는 MCP `editor_reload_plugin`).
- 커밋 전 `.\tools\check-project.ps1` 을 돌리면 스크립트 파싱 오류를 로컬에서 잡습니다.

## 5. 충돌 대응

### 씬/리소스 (`.tscn`, `.tres`)

1. `git status` 로 충돌 파일 확인
2. **자동 병합을 믿지 않습니다.** 한쪽을 기준으로 선택 → `git checkout --ours <file>` 또는 `--theirs <file>`
3. Godot에서 그 씬을 열어 상대방 변경을 수동 재적용 → **에디터에서 저장**
4. `git add <file>` → `test_run` 으로 검증 → 커밋

### `project.godot`

섹션이 다르면 양쪽 변경을 수동으로 합칩니다(오토로드/입력맵/플러그인 항목 누락에 특히 주의).

### `.uid`

삭제하지 말고 한쪽을 유지합니다. `.uid`가 사라지면 다른 팀원의 씬/스크립트 참조가 깨집니다.

### LFS 자산

같은 파일을 두 사람이 커밋하면 LFS 충돌이 납니다. 아트/사운드는 **오너 1명**만 커밋합니다.
GitLab을 쓰면 `git lfs lock <file>` 을 쓸 수 있습니다(GitHub LFS는 파일 잠금 미지원).
필요 시 `.gitattributes` 에서 해당 패턴에 `lockable` 을 추가하고 `git config lfs.locksverify true`.

## 6. 사전 검증 / CI

```powershell
.\tools\check-project.ps1
```

`Godot --headless --path . --editor --quit` 로 프로젝트를 열어 임포트/스크립트 파싱 오류를 찾습니다.
**플러그인은 헤드리스 실행에서 MCP 서버를 자동 비활성화**하므로(`MCP | plugin disabled in headless mode`, 포트 충돌 없음) 에디터를 켜 둔 상태에서도 CI에서도 그대로 쓸 수 있습니다.
헤드리스에서도 서버를 띄우고 싶다면 환경변수 `GODOT_AI_ALLOW_HEADLESS=1` 을 설정합니다.

GitHub Actions 워크플로도 포함돼 있습니다: **`.github/workflows/ci.yml`**
- push(main) / PR 마다 실행, Godot 4.7.2 mono를 내려받아 위와 같은 헤드리스 검사를 수행
- 추가로 `.godot/` 나 `export_credentials.cfg` 가 인덱스에 들어왔는지 검사(방어선)
- GDScript 테스트 스위트(`test_run`)는 에디터 + MCP 연결이 필요하므로 CI에서는 생략하고, PR 전 로컬에서 돌리는 것을 권장합니다


## 7. 알려진 함정과 대처

| 증상 | 원인 / 해결 |
|---|---|
| MCP 도구가 안 보임 | 클라이언트 재시작. `cline config mcp --json` 으로 등록 확인 |
| `PLUGIN_DISCONNECTED` | 에디터가 닫혔거나 프로젝트가 안 열림. 에디터를 열고 재시도(클라이언트 재시작 불필요) |
| 플러그인이 서버 재탐색 루프 | `attach` 브리지를 동시에 여러 개 띄운 경우. **하나만** 쓰고, 꼬이면 에디터 재시작 |
| `EDITOR_NOT_READY (EDITOR_TEST_RUNNING)` | 다른 클라이언트가 `test_run` 중. 끝난 뒤 재시도 |
| `UnicodeEncodeError: 'cp949'` | `PYTHONUTF8=1` 필요 (설치 스크립트가 자동 설정) |
| 남의 씬이 깨져 보임 | 엔진 버전 불일치(4.7.2 아님) 가능성. 버전 확인 후 재현 |
| LFS 파일이 포인터로 보임 | `git lfs install` / `git lfs pull` |
| 에이전트가 파일을 못 씀 | 파일 op 이름은 `read_text`/`write_text` (`read_file`/`write_file` 아님) |

## 부록 A. Cline CLI 등록 항목(전체)

`%USERPROFILE%\.cline\data\settings\cline_mcp_settings.json`:

```json
{
  "mcpServers": {
    "godot-ai": {
      "type": "stdio",
      "command": "uvx",
      "args": [
        "--isolated", "--no-config", "--no-env-file", "--no-sources", "--no-build",
        "--index-strategy", "first-index", "--keyring-provider", "disabled",
        "--index", "https://pypi.org/simple",
        "--default-index", "https://pypi.org/simple",
        "--find-links", "https://pypi.org/simple/godot-ai/",
        "--link-mode", "copy",
        "--from", "godot-ai==4.1.0",
        "godot-ai", "attach",
        "--port", "8000",
        "--ws-port", "9500"
      ],
      "env": { "PYTHONUTF8": "1" },
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

- 버전 핀은 **플러그인의 메이저 버전과 일치**해야 합니다(4.x 플러그인 ↔ 4.x 서버).
- `autoApprove` 에 `editor_state`, `scene_get_hierarchy`, `logs_read` 같은 읽기 도구를 넣으면 승인 프롬프트를 줄일 수 있습니다.
- 텔레메트리를 끄려면 `attach` 뒤에 `"--disable-telemetry"` 를 추가합니다.

## 부록 B. `addons/godot_ai` 를 왜 커밋하나

- 팀 전원이 **동일한 플러그인/서버 버전**을 쓰게 되어 "내 환경에서는 되는데" 문제가 사라집니다.
- MIT 라이선스라 재배포 문제가 없습니다(원본 `LICENSE` 동봉).
- 갱신은 릴리스 zip 교체 + 버전 고정 커밋(`chore: bump godot-ai to 4.x.y`)으로만 합니다. **손으로 수정하지 않습니다.**
- 대안: `.gitignore` 에 넣고 각자 설치 → 버전 드리프트 위험이 큽니다.
