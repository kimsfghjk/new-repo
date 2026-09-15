# MyGame (Godot 4.7 mono) — Cline 작업 규칙

**작업 시작 전에 항상 `AGENTS.md`를 읽고 따릅니다.** 아래는 자주 틀리는 항목만 요약한 것입니다.

## 프로젝트

- Godot **4.7.x stable (mono/.NET)** 기준. 엔진 버전 업그레이드는 단독 PR로만.
- `addons/godot_ai` = Godot AI 4.1.0 고정. **절대 수정하지 않습니다.**
- 렌더러 Forward+, 주 언어 GDScript.

## 코드

- 들여쓰기 **탭**, 파일명 `snake_case.gd`, 노드명 `PascalCase`, 상수 `SCREAMING_SNAKE_CASE`.
- 정적 타이핑 우선. `class_name` 남용 금지. 디버그 `print()`는 커밋 전 제거.

## 씬

- `.tscn`/`.tres`는 **에디터에서 저장**. 손 편집·정규식 편집 금지(UID/포맷 깨짐).
- 한 씬을 동시에 여러 사람이 수정하지 않음. 큰 씬은 SubScene으로 분할.
- `project.godot` 수정 시 PR 본문에 명시.

## MCP 도구

- 파일 op: `read_text`, `write_text`, `reimport`, `scan`, `search` (`read_file`/`write_file` 아님).
- `script_*` 도구는 GDScript 전용. C#은 일반 파일 편집으로.
- 에디터 1개 = MCP 클라이언트 1개. 브리지를 여러 개 동시에 띄우지 않음.

## 검증

- 테스트는 `res://tests/test_*.gd` (`extends McpTestSuite`), `test_run`으로 실행.
- 로직 변경 시 테스트 추가. **커밋 전 `test_run` 실행**, 실패하면 수정 후 결과와 함께 보고.

## 금지

- `.godot/`, `export_credentials.cfg`, 빌드 산출물 커밋
- `addons/godot_ai` 수정, `*.uid` 삭제
- 대소문자만 다른 파일명 생성 (Windows/Linux 간 깨짐)
- 새 바이너리 확장자 추가 시 `.gitattributes`(LFS) 수정 누락
