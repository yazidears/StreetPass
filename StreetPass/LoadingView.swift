
// LoadingView.swift
// this is our bouncer. its only job is to stand at the door,
// wait for the app to be ready, and then let us into the club.

import SwiftUI

struct LoadingView: View {
    // it gets the viewmodel and a secret password (the onFinished closure)
    @ObservedObject var viewModel: StreetPassViewModel
    var onFinished: () -> Void

    var body: some View {
        ProgressView("Starting StreetPass…")
            .task {
                // .task is smart. it runs this async block when the view appears.
                // this is where we tell the viewmodel: "ok, go do your bluetooth shit now."
                await viewModel.setup()
                
                // once setup() is 100% done, we call the secret password closure
                // to tell the main app view it's time to switch.
                onFinished()
            }
    }
}
