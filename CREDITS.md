> (픽셀 대조로 확인: 알파를 무시한 RGB 차이가 ±2 이내, 투명 픽셀은 각각 100% 동일 색상과 대응)

## 2. RPG Maker 원본 RTP는 사용하지 않습니다

RPG Maker 제품에 포함된 RTP/동봉 소재는 **RPG Maker 제품 안에서만** 사용이 허가됩니다.
Godot은 아래 조항들이 말하는 "제3자가 제공한 게임 제작 도구"에 해당하므로, 원본 소재를 이
프로젝트에 넣으면 라이선스 위반입니다. (공식 EULA 원문에서 직접 인용)

**RPG Maker MV EULA**
> ...the User cannot record or use, etc. **Company Materials** in the original games they create
> using creation tools, etc. they created or **provided by third parties** without obtaining the
> Company's advance written consent.

**RPG Maker MZ EULA, Article 5 (User License)**
> ...the User may not load, use, or otherwise utilize **Company Assets** into original games created
> with personally-created programs or **game creation tools, etc. provided by a third party** without
> the advance written consent of the Company.

**RPG Maker MZ — Terms of Game Distribution, Article 2**
> 1. **Company Materials shall be used solely for User Games created with the Software.**
> 3. ...they **may not be combined with programs, etc. other than the User Game.**

**RPG Maker VX Ace RTP EULA**
> ...a non-exclusive, non-assignable, fee-free license to use the RTP SOFTWARE **only for the purpose
> to play the game created and distributed by RPG MAKER VX Ace users**.

같은 문서의 부속 조항이 허용 범위를 명확히 합니다 — **RPG Maker 제품군 내부**까지입니다:
> **Note for using VX Ace RTP with other RPG MAKER products** — The materials included in RPG MAKER
> VX Ace RTP can be used with **other RPG MAKER products** from LICENSOR as long as you own both...

출처: <https://www.rpgmakerweb.com/eula> (MV/MZ/VX Ace 탭), Steam 공식 EULA(앱 1096900)에서 동일 문구 확인.

**라서**: RPG Maker 설치 폴더의 RTP/그래픽을 이 저장소나 빌드에 복사하지 마세요.
EasyRPG RTP(1절)는 이 제약을 피하려고 만든 대체 리소스입니다.

## 3. 그 밖의 외부 코드

| 대상 | 라이선스 | 문서 |
|---|---|---|
| `addons/dialogue_manager` 외 애드온 4종 | MIT | [`third_party/README.md`](third_party/README.md) 1절 |
| `third_party/gbm2k` (프레임워크 코드) | MIT | 같은 문서 2절 |
| `addons/godot_ai` (개발 도구, 런타임 아님) | 플러그인 라이선스 | `addons/godot_ai/README.md` |

> 이 문서는 법률 자문이 아닙니다. 상용 배포 전에는 각 라이선스 원문을 직접 확인하세요.