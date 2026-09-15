# 에셋 — EasyRPG RTP 번들

이 문서는 `assets/` 아래 게임 에셋이 **어디서 왔고 어떻게 만들었으며 어떻게 쓰는지**를 정리합니다.
대상은 EasyRPG RTP(RPG Maker 2000/2003 RTP의 자유 라이선스 대체 리소스)입니다.

## 1. 폴더 구조

```text
assets/
  art/easyrtp/
    chipsets/      # 맵 타일 (8종, 480x256, 16px 격자 30x16)
    tilesets/      # 위 칩셋용 Godot TileSet (8종, 생성물)
    characters/    # 캐릭터 1명 단위 이미지 (136개, 72x128)
    facesets/      # 얼굴 (5)
    panoramas/     # 배경 (13)
    titles/        # 타이틀 (4)
    system/        # 시스템 그래픽 (5)
    system2/       # 게이지·커서 그래픽 (3)
    battle/        # 전투 애니메이션 프레임 (3)
    battle_weapons/# 전투 무기 (1)
    monsters/      # 몬스터 (1)
    pictures/      # 픽처 (1)
    gameover/      # 게임오버 (1)
  audio/easyrtp/
    sounds/        # 효과음 (96, WAV)
  easyrtp.manifest.json   # 생성물 대장 (파일별 출처·해시·변환 정보)
```

**`assets/` 아래는 전부 생성물입니다.** 손으로 고치지 말고 파이프라인을 고쳐 다시 생성합니다(4절).
직접 만드는 아트는 `assets/art/` 아래 별도 폴더를 쓰세요.

## 2. 왜 변환이 필요한가 — 컬러키

RPG Maker 2000/2003 이미지는 **알파 채널이 없습니다.** 투명은 "이 색은 없는 셈 친다"는
**컬러키** 방식이고, 그 색은 파일마다 다릅니다. Godot에는 컬러키 개념이 없으므로 그대로 쓰면
**분홍/청록 배경이 그대로 그려집니다.** 그래서 임포트 전에 키 색을 알파로 바꿉니다.

실측으로 확인한 키 색(추측이 아니라 픽셀 대조 결과):

| 자산 | 키 색 | 근거 |
|---|---|---|
| `ChipSet/Dungeon`, `Exterior`, `Interior`, `Ship`, `World`, `retro_Dungeon` | `#FF678B` | 이 저장소의 `third_party/gbm2k/.../tileset_dungeon.png`가 바로 이 파일의 변환본이며, 그 투명 픽셀 **15,347개가 100% `#FF678B`와 일치** |
| `ChipSet/retro_Exterior` | `#FE678A` | 동일 계열(1 차이) |
| `ChipSet/retro_World` | `#E067BF` | 실측 |
| `CharSet/*` (15종) | `#009392` | GBM2K의 `actor_man.png`(=`CharSet/Template.png` 0,0) 투명 픽셀 **6,708개가 100% `#009392`와 일치** |
| `CharSet/Object1` / `Object2` | `#FE678A` / `#FF678B` | 실측 |
| `Battle/*`, `BattleWeapon/Weapon` | `#187518`, `#85B0B6` | 94~98%가 단색 배경 + 네 모서리 동일 → 체커보드 시각 확인 |
| `System2/*` | `#FF9C00` | 69~75% 단색 배경 위에 커서·게이지·숫자 → 시각 확인 |
| `Monster/Hornet` | `#FF00FF` | 고전 마젠타 |
| `Picture/Cloud` | `#FF678B` | 칩셋과 동일 |

**변환하지 않는 것**: `FaceSet`, `Panorama`, `Title`, `System`, `GameOver` — 전체가 그림인 자산이라
키 색이 없습니다(가장 많은 색이 실제 아트). 여기에 변환을 적용하면 그림이 지워집니다.
`System/System.png`는 색상 팔레트·폰트 시트이므로 그대로 씁니다.

> 검증 방법: 변환 후 "키 색이 남아 있는 픽셀 수"를 세어 0인지 확인하고, 변환 전 파일과
> 알파를 무시하고 RGB를 비교해 차이가 ±1(팔레트 반올림)인지 대조했습니다.

## 3. 사용법

**맵 그리기 (칩셋)**

1. 씬에서 `TileMapLayer`를 만들고 `tile_set`에 `assets/art/easyrtp/tilesets/<칩셋>.tres`를 지정합니다.
2. 타일 크기는 16px로 이미 맞춰져 있고, **모든 타일의 `coll_type`이 `-1`(통행 가능)** 입니다.
3. 막을 타일은 에디터에서 해당 타일의 커스텀 데이터 `coll_type`을 `1`로 바꿉니다.

`coll_type` 값은 GBM2K의 `PawnGrid`가 그대로 읽습니다:

| 값 | 의미 | 이동 가능? |
|---|---|---|
| `-1` | EMPTY | 가능 |
| `0` | ACTOR | 불가 (폰이 있음) |
| `1` | OBSTACLE | 불가 |
| `2` | EVENT | 불가 (이벤트 트리거) |

> 왜 전부 `-1`로 박아 두었나: 커스텀 데이터를 **비워 두면 0으로 읽히고**, 0은 ACTOR라서
> 새로 칠한 타일이 전부 이동을 막습니다. 조용히 게임이 안 움직이는 함정이라 생성 단계에서 고정했습니다.

**캐릭터 쓰기**

`characters/<시트>_<1~8>.png`는 **캐릭터 한 명** 단위(72x128)입니다. GBM2K의 `player.tscn`과 같은 구조로
`Sprite2D`(`hframes = 3`, `vframes = 4`)에 텍스처만 바꿔 넣으면 됩니다.

시트 안 번호는 좌상단부터 1~8이고, 한 칸은 `3프레임 x 4방향`(24x32)입니다.
출처 시트는 매니페스트의 `charset_cell`에 남아 있으므로, 누구 작품인지 추적할 수 있습니다.

**아직 안 되어 있는 것**

- **terrain(오토타일) 미설정** — 칩셋마다 어떤 타일이 오토타일인지 지정하지 않았습니다.
  에디터에서 TileSet을 열어 terrain을 직접 지정하세요(칩셋마다 배치가 달라 자동 생성이 위험합니다).
- **`z_index` 미설정** — GBM2K의 원본 타일셋은 나무 상단 같은 타일에 `z_index = 1`을 씁니다.
  필요하면 에디터에서 지정합니다.
- **애니메이션 타일 미설정** — 물·폭포의 프레임 애니메이션은 넣지 않았습니다.

## 4. 다시 생성하기 / 검증하기

생성물은 **커밋되어 있으므로 팀원은 이 스크립트를 돌 필요가 없습니다.** 업스트림 핀을 올리거나
변환 정책을 바꿀 때만 실행합니다.

```powershell
# 준비물: Python 3 + Pillow
python -m pip install pillow

# assets/ 전체 재생성 (업스트림에서 내려받아 변환)
powershell -ExecutionPolicy Bypass -File .\tools\prepare-easyrtp.ps1

# 커밋된 자산이 매니페스트와 일치하는지 검사 (드리프트 감지)
powershell -ExecutionPolicy Bypass -File .\tools\prepare-easyrtp.ps1 -Check
```

파이프라인이 하는 일(`tools/easyrtp_prepare.py`):

1. `EasyRPG/RTP`의 **핀 고정 커밋**(파일 상단 `UPSTREAM_COMMIT`)을 내려받아 캐시합니다.
2. 정책 표(`CONVERT`)에 따라 키 색을 알파로 바꿉니다. **키가 하나도 매칭되지 않으면 중단**합니다
   (업스트림 아트가 바뀌었는데 조용히 통과하는 것을 막습니다).
3. 캐릭터 시트를 72x128 8칸으로 자릅니다.
4. 칩셋마다 TileSet을 생성합니다(비어 있지 않은 16x16 셀만 등록, 전부 `coll_type = -1`).
5. `assets/easyrtp.manifest.json`에 파일별 출처·해시·키·타일 수를 기록합니다.

업스트림을 갱신할 때는 `UPSTREAM_COMMIT`을 새 SHA로 바꾸고 재생성한 뒤, `-Check` 통과와 매니페스트
diff를 확인합니다. **임의로 최신 master를 따라가지 않습니다** (에셋이 조용히 바뀌면 이미 그린 맵이 깨집니다).

## 5. 라이선스

- 번들 전체: **CC-BY 4.0** (bundle license)
- 파일별 저자·라이선스의 원본은 업스트림 `AUTHORS.md` → 요약은 루트 [`CREDITS.md`](../CREDITS.md)
- 특히 이 프로젝트가 쓰는 **칩셋과 캐릭터 Template은 CC0**(표기 의무 없음)입니다. 반면 `retro_*` 셋
  일부는 **CC-BY**(표기 필요)입니다.
- **RPG Maker 원본 RTP 리소스는 절대 쓰지 마세요.** RPG Maker 제품 외 사용이 허가되지 않습니다
  (근거: MV/MZ EULA의 "game creation tools provided by a third party" 조항, VX Ace RTP EULA의
  "only for the purpose to play the game created and distributed by RPG MAKER VX Ace users").
  조항 원문 인용은 `CREDITS.md` 2절에 있습니다.

## 6. 빠진 것 / 의도적으로 제외한 것

| 항목 | 이유 |
|---|---|
| `Music/*.mid` (30곡) | **MIDI라서 Godot이 재생하지 못합니다.** 매니페스트 `skipped`에 기록돼 있습니다. 쓰려면 OGG/WAV로 변환해 `assets/audio/easyrtp/music/`에 넣으세요 |
| 32px / 48px 계열 아트 | EasyRTP는 **RPG Maker 2000/2003 스타일(16px)** 전용입니다. VX Ace(32px)·MV/MZ(48px) 스타일이 필요하면 다른 소스를 구해야 합니다 |

## 7. 참고 — 하지 말 것

- `assets/art/easyrtp/**` 수동 편집 → `-Check`가 실패하고 다음 재생성에서 사라집니다
- `.gitattributes`의 LFS 규칙을 빼고 PNG/WAV 커밋 → 저장소가 급격히 무거워집니다
- `.import` 파일 수동 편집 → 임포트 설정이 아니라 생성 결과입니다
