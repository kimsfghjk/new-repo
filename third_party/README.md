# third_party — 외부 코드 (vendored)

이 폴더는 **외부 프로젝트를 그대로 복사해 온 코드**입니다. `addons/`(Godot 에디터 플러그인)와 달리
플러그인 형태가 아니거나, 이 저장소 규약에 맞추기 위해 경로를 수정한 코드가 들어 있습니다.
**손으로 고치지 말고**, 갱신이 필요하면 아래 "갱신 절차"대로 원본을 다시 받아 교체합니다.

## 1. 설치된 애드온 (핀 고정)

`addons/` 아래에 다음 버전을 커밋해 두었습니다. 팀 전원이 동일 버전을 쓰기 위한 핀입니다.

| addon | 원본 | 핀(태그/커밋) | 라이선스 | 오토로드 |
|---|---|---|---|---|
| `addons/dialogue_manager` | [nathanhoad/godot_dialogue_manager](https://github.com/nathanhoad/godot_dialogue_manager) | `v4.1.0` (a719088aea) | MIT | `DialogueManager` |
| `addons/gloot` | [peter-kish/gloot](https://github.com/peter-kish/gloot) | `v3.0.2` (ce88b7adc7) | MIT | (없음) |
| `addons/quest_system` | [shomykohai/quest-system](https://github.com/shomykohai/quest-system) | `2.0.2.4_4` (d1d933c7b1) | MIT | `QuestSystem` |
| `addons/save_system` | [AdamKormos/SaveMadeEasy](https://github.com/AdamKormos/SaveMadeEasy) | `0cd7aae70f` (릴리스 없음) | MIT | `SaveSystem` |

`project.godot`에 오토로드를 **명시적으로** 기록해 둔 이유: 각 플러그인도 활성화 시 자체 등록하지만,
`add_autoload_singleton`은 에디터가 저장할 때만 디스크에 반영되므로 CI/신규 클론에서 순서가 흔들릴 수 있습니다.
SaveMadeEasy README 지침에 따라 `SaveSystem`을 가장 먼저 부팅하도록 배치했습니다.

제외한 것: quest-system 저장소의 `addons/gdUnit4`(테스트 프레임워크, 약 90MB) — 런타임에 필요하지 않아 설치하지 않았습니다.

## 2. 벤더링한 프레임워크

| 경로 | 원본 | 핀 | 라이선스 |
|---|---|---|---|
| `third_party/gbm2k/` | [Oplexitie/GBM2K-Framework](https://github.com/Oplexitie/GBM2K-Framework) | `3cf0fe974bbc10b3f906806552db606930057b52` (릴리스 없음) | MIT |

**GBM2K**(Grid Based Movement 2K)는 Godot **프로젝트** 형태라 `addons/`에 넣을 수 없고, 폴더명이
`Scripts/`, `Scenes/`, `Resources/`, `Graphics/`(대문자)라 이 저장소의 `scripts/`와 **Windows에서 이름 충돌**합니다.
그래서 `third_party/gbm2k/`로 옮기고 내부의 절대 경로 참조를 재작성했습니다.

재작성 내용(총 10개 파일: `.tscn` 5, `.tres` 2, `.import` 3):

```
res://Scripts/    -> res://third_party/gbm2k/Scripts/
res://Scenes/     -> res://third_party/gbm2k/Scenes/
res://Resources/  -> res://third_party/gbm2k/Resources/
res://Graphics/   -> res://third_party/gbm2k/Graphics/
```

`.uid` 파일을 그대로 보존했기 때문에 `uid://` 기반 참조는 영향받지 않습니다.
원본 README는 `UPSTREAM_README.md`로 함께 보관했습니다.

> ⚠️ **에셋 라이선스 주의**: GBM2K 저장소는 MIT지만 `Graphics/`의 스프라이트는 원작자 표기에 따르면
> **OpenRTP**(RPG Maker 2000/2003 RTP 무료 대체 리소스, Jason Perry)입니다. 프레임워크 코드는 자유롭게
> 쓸 수 있지만 **아트를 상용 배포에 그대로 쓰기 전에 OpenRTP 라이선스를 직접 확인**하고, 가능하면 자체/구매
> 아트로 교체하세요. RPG Maker RTP 원본 리소스는 RPG Maker 제품 외 사용이 허가되지 않으므로 절대 쓰지 마세요.

## 3. 사용 예 (씬에서 가져다 쓰기)

- 그리드 이동/이벤트: `third_party/gbm2k/Scenes/Maps/world.tscn`(예제 맵), `Scenes/Pawns/*.tscn`을 열어 구조를 보고
  우리 씬에 복사해 씁니다. 스크립트는 `Scripts/Grid/grid_manager.gd`, `Scripts/Pawns/pawn.gd` 등입니다.
- 대화: `DialogueManager.show_example_dialogue_balloon(...)` 또는 `DialogueResource`를 로드해 사용합니다.
- 인벤토리: gloot의 `Inventory`/`InventoryItem` 리소스와 `UI Controls`를 사용합니다.
- 퀘스트: `QuestSystem` 싱글턴에 `QuestResource`를 등록/완료 처리합니다.
- 저장: `SaveSystem.set_var(...)` / `SaveSystem.save()` (README 참조).

## 4. 갱신 절차

1. 원본 저장소에서 새 태그/커밋 SHA를 확인합니다.
2. `addons/<name>` 폴더를 통째로 교체합니다(부분 패치 금지).
3. GBM2K은 위 4개 경로 재작성을 다시 수행합니다.
4. 이 파일의 표(핀 값)를 갱신하고, 커밋 메시지에 `chore(vendor): bump <addon> to <version>` 형식으로 남깁니다.
5. `powershell -ExecutionPolicy Bypass -File .\tools\check-project.ps1` 로 프로젝트가 정상 로드되는지 확인합니다.
