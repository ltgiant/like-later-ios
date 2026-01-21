# Swift/SwiftUI 디테일 노트

이 문서는 LikeLater 프로젝트를 이해하기 위한 **Swift/SwiftUI 핵심 문법과 패턴**을 간단히 정리합니다.

## SwiftUI 기본 구조
```swift
struct ContentView: View {
    var body: some View {
        Text("Hello")
    }
}
```
- `View` 프로토콜을 채택한 구조체가 화면입니다.
- `body`는 화면의 레이아웃을 반환합니다.

## 상태 관리
- `@StateObject`: 뷰가 **소유**하는 객체(수명: 뷰와 동일)
- `@ObservedObject`: 외부에서 **주입**받는 객체(수명: 외부)

예:
```swift
@StateObject private var store = QueueStore()
ContentView(store: store)
```

## ObservableObject & Published
```swift
final class QueueStore: ObservableObject {
    @Published var items: [QueueItem] = []
}
```
- `@Published`가 붙은 값이 바뀌면 UI가 갱신됩니다.
- `ObservableObject`는 `Combine`에 정의되어 있어 `import Combine` 필요합니다.

## 비동기 처리 (async/await)
```swift
Task {
    await spotify.fetchRecentlyPlayed(into: store)
}
```
- `Task`는 SwiftUI 이벤트(버튼/딥링크)에서 비동기 함수 호출 시 사용합니다.

## 딥링크 수신
```swift
.onOpenURL { url in
    store.handle(url: url)
}
```
- `likelater://capture?...` 같은 URL을 앱에서 받아 처리합니다.

## Codable (JSON 저장)
```swift
struct QueueItem: Codable { ... }
```
- `JSONEncoder/JSONDecoder`로 `queue.json` 저장/로드를 합니다.
- 날짜는 `ISO8601` 포맷으로 인코딩합니다.

## PKCE (OAuth)
- `code_verifier` → `code_challenge` 생성 후 로그인 요청
- 리다이렉트 URL로 돌아온 `code`를 `token` 엔드포인트에 교환

## 현재 재생 매칭 로직(요약)
1) 캡처 즉시 큐에 저장
2) 현재 재생 호출
3) 성공 시 `matched` 업데이트, 204면 큐에서 제거
4) 실패 시 `pending` 유지

## 자주 쓰는 Swift 문법
- 옵셔널 언래핑:
```swift
if let value = optionalValue { ... }
```
- 클로저:
```swift
items.map { $0.name }
```
- 열거형:
```swift
enum Status { case pending, matched, failed }
```

## 프로젝트 내 관련 파일
- `LikeLater/LikeLater/ContentView.swift`: 큐 UI/저장/매칭
- `LikeLater/LikeLater/SpotifyService.swift`: OAuth + API 호출
- `LikeLater/LikeLater/LikeLaterApp.swift`: 앱 엔트리
