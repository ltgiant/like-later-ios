# Repository Guidelines

LikeLater는 잠금 상태에서도 “좋아요 의도”를 놓치지 않기 위해, Back Tap → Shortcuts → 딥링크로 캡처 이벤트를 기록하는 iOS 앱입니다.  
현재는 **의도 캡처 + 큐 저장(MVP)**까지 구현되어 있습니다.

## 프로젝트 구조
- `LikeLater/LikeLater.xcodeproj`: Xcode 프로젝트
- `LikeLater/LikeLater/ContentView.swift`: 큐 UI + 저장/매칭 로직
- `LikeLater/LikeLater/LikeLaterApp.swift`: 앱 엔트리 + 딥링크 수신
- `LikeLater/LikeLater/SpotifyService.swift`: Spotify OAuth(PKCE) + API 호출 스켈레톤

## 빌드/실행
1) Xcode에서 `LikeLater.xcodeproj` 열기  
2) Run Destination을 **iPhone 실기기**로 선택  
3) ▶️ Run  
4) iPhone에서 **개발자 신뢰** 및 **개발자 모드** 활성화

## 딥링크 설정
Target → Info → URL Types에서 다음을 추가:
- URL Schemes: `likelater`
- Identifier: `likelater` (선택)

테스트:
```
likelater://capture?source=manual&app=spotify
```

## MVP 동작 흐름
1) 딥링크 수신 → 큐에 즉시 저장 (`queue.json`)  
2) 비동기로 **현재 재생 API** 호출  
   - 현재 재생 있음 → 해당 항목 `matched` 업데이트  
   - 현재 재생 없음(204) → **큐에서 제거**  
   - 실패/응답 없음 → **큐에 남김(pending)**  
3) 필요 시 **최근 재생 목록**으로 추가 매칭 가능

## Back Tap + Shortcuts 테스트 (실기기만 가능)
1) Shortcuts 앱에서 “URL 열기” 액션 생성  
2) URL: `likelater://capture?source=backtap&app=spotify`  
3) 설정 → 손쉬운 사용 → 터치 → 뒷면 탭 → 단축어 연결  
4) 잠금 상태에서 Back Tap으로 앱 실행/큐 추가 확인

## Spotify 연동 (로컬 앱만으로 가능)
서버 없이 **OAuth PKCE**로 연동합니다.
1) Spotify Developer Dashboard에서 앱 생성  
2) Client ID 확인  
3) Redirect URI 등록: `likelater://spotify-auth`  
4) `SpotifyService.swift`에서 `clientID` 교체

필요 스코프:
- `user-read-currently-playing`
- `user-read-recently-played`

## 저장 위치
- `Application Support/LikeLater/queue.json`

## 상태 표기 규칙
- `matchStatus = processing` : 현재 재생 조회 중  
- `matchStatus = matched` : 현재 재생 매칭 성공  
- `matchStatus = pending` : 응답 실패/재생 없음

## 참고
Swift/UI 문법과 구현 디테일은 `detail.md`에 정리되어 있습니다.
