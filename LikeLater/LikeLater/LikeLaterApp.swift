//
//  LikeLaterApp.swift
//  LikeLater
//
//  Created by jihoon_macbook_air_13_m2 on 1/21/26.
//

import SwiftUI

@main
struct LikeLaterApp: App {
    @StateObject private var store = QueueStore()
    @StateObject private var spotify = SpotifyService()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, spotify: spotify)
                .onOpenURL { url in
                    let captureID = store.handle(url: url)
                    if let captureID {
                        Task {
                            await spotify.tryMatchCapture(id: captureID, store: store)
                        }
                    }
                }
        }
    }
}
