// StreetPassApp.swift
// aka the bouncer at the club door. decides who gets in.

import SwiftUI
import UIKit // for uiimage stuff, boring but necessary

// MARK: - Core Data Model: EncounterCard
// this whole EncounterCard thing is just the digital equivalent of a business card
// but like, for cool people.
struct EncounterCard: Identifiable, Codable, Equatable {
    var id: UUID
    let userID: String
    var displayName: String
    var statusMessage: String
    var avatarSymbolName: String
    var flairField1Title: String?
    var flairField1Value: String?
    var flairField2Title: String?
    var flairField2Value: String?
    var drawingData: Data?
    var lastUpdated: Date
    var cardSchemaVersion: Int = 1
    init(userID: String,
         displayName: String = "StreetPass User",
         statusMessage: String = "Ready for new encounters!",
         avatarSymbolName: String = "person.crop.circle.fill",
         drawingData: Data? = nil) {
        self.id = UUID()
        self.userID = userID
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.statusMessage = statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        self.avatarSymbolName = avatarSymbolName
        self.drawingData = drawingData
        self.lastUpdated = Date()
        self.cardSchemaVersion = 2
    }
    var drawingImage: UIImage? {
        guard let data = drawingData else { return nil }
        return UIImage(data: data)
    }
    static func == (lhs: EncounterCard, rhs: EncounterCard) -> Bool {
        return lhs.id == rhs.id &&
               lhs.userID == rhs.userID &&
               lhs.lastUpdated == rhs.lastUpdated &&
               lhs.drawingData == rhs.drawingData
    }
    func isContentDifferent(from other: EncounterCard) -> Bool {
         return self.displayName != other.displayName ||
                self.statusMessage != other.statusMessage ||
                self.avatarSymbolName != other.avatarSymbolName ||
                self.flairField1Title != other.flairField1Title ||
                self.flairField1Value != other.flairField1Value ||
                self.flairField2Title != other.flairField2Title ||
                self.flairField2Value != other.flairField2Value ||
                self.drawingData != other.drawingData ||
                self.cardSchemaVersion != other.cardSchemaVersion
    }
    static func placeholderCard(drawingIdentifier: String) -> EncounterCard {
        var card = EncounterCard(userID: UUID().uuidString, displayName: "---")
        card.avatarSymbolName = drawingIdentifier
        card.drawingData = nil
        return card
    }
    @ViewBuilder
    func getPlaceholderDrawingView(strokeColor: Color = .black, lineWidth: CGFloat = 3) -> some View {
        switch self.avatarSymbolName {
        case "s_squiggle":
            Path { path in
                path.move(to: CGPoint(x: 20, y: 80))
                path.addCurve(to: CGPoint(x: 80, y: 40), control1: CGPoint(x: 20, y: 30), control2: CGPoint(x: 80, y: 80))
                path.addCurve(to: CGPoint(x: 20, y: 120), control1: CGPoint(x: 80, y: -10), control2: CGPoint(x: 20, y: 70))
            }
            .stroke(strokeColor, lineWidth: lineWidth)
        case "lines_and_block":
            VStack(spacing: 8) {
                HStack(spacing: 15) {
                    RoundedRectangle(cornerRadius: 2).frame(width: lineWidth, height: 50)
                    RoundedRectangle(cornerRadius: 2).frame(width: lineWidth, height: 60)
                    RoundedRectangle(cornerRadius: 2).frame(width: lineWidth, height: 50)
                }
                Spacer().frame(height:5)
                RoundedRectangle(cornerRadius: 2).frame(height: lineWidth).padding(.horizontal, 5)
                Spacer().frame(height:5)
                HStack(spacing: 8){ RoundedRectangle(cornerRadius: 2).frame(height: lineWidth); RoundedRectangle(cornerRadius: 2).frame(height: lineWidth); RoundedRectangle(cornerRadius: 2).frame(height: lineWidth) }
            }
            .foregroundColor(strokeColor)
            .padding(15)
        case "flower_simple":
            Path { path in
                let center = CGPoint(x: 50, y: 75)
                let petalRadius: CGFloat = 25
                let controlOffset: CGFloat = 15
                for i in 0..<5 {
                    let angle = CGFloat(i) * (2 * .pi / 5) - (.pi / 2)
                    let petalTip = CGPoint(x: center.x + petalRadius * cos(angle), y: center.y + petalRadius * sin(angle))
                    let control1 = CGPoint(x: center.x + (petalRadius - controlOffset) * cos(angle - 0.3), y: center.y + (petalRadius - controlOffset) * sin(angle - 0.3))
                    let control2 = CGPoint(x: center.x + (petalRadius - controlOffset) * cos(angle + 0.3), y: center.y + (petalRadius - controlOffset) * sin(angle + 0.3))
                    path.move(to: center)
                    path.addQuadCurve(to: petalTip, control: control1)
                    path.addQuadCurve(to: center, control: control2)
                }
            }
            .stroke(strokeColor, lineWidth: lineWidth)
            .overlay(Circle().frame(width:15, height:15).foregroundColor(strokeColor).position(CGPoint(x:50, y:75)))
        case "smiley_face":
             ZStack {
                Path { path in path.addEllipse(in: CGRect(x:25, y:35, width:50, height:50)) }.stroke(strokeColor, lineWidth: lineWidth)
                HStack(spacing:15) { Circle().fill(strokeColor).frame(width:lineWidth+2, height:lineWidth+2); Circle().fill(strokeColor).frame(width:lineWidth+2, height:lineWidth+2) }.offset(y:-5)
                Path { path in path.move(to: CGPoint(x:40, y:70)); path.addQuadCurve(to: CGPoint(x:60, y:70), control: CGPoint(x:50,y:80)) }.stroke(strokeColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        default:
            Image(systemName: "questionmark.diamond")
                .resizable().scaledToFit().padding(30).foregroundColor(strokeColor)
        }
    }
}

// MARK: - Main Application Structure
@main
struct StreetPassApp: App {
    private static func getPersistentAppUserID() -> String {
        let userDefaults = UserDefaults.standard
        let userIDKey = "streetPass_PersistentUserID_v1"
        if let existingID = userDefaults.string(forKey: userIDKey) {
            print("StreetPassApp: Found existing UserID: \(existingID)")
            return existingID
        } else {
            let newID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            userDefaults.set(newID, forKey: userIDKey)
            print("StreetPassApp: Generated new UserID: \(newID)")
            return newID
        }
    }

    // The viewmodel's init is now safe and fast.
    @StateObject private var viewModel = StreetPassViewModel(userID: StreetPassApp.getPersistentAppUserID())
    
    // The switch that controls the UI.
    @State private var isAppReady = false

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<StreetPassViewModel, T>) -> Binding<T> {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { newValue in viewModel[keyPath: keyPath] = newValue }
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isAppReady {
                    // Show the real app
                    StreetPass_MainView()
                        .environmentObject(viewModel)
                        .fullScreenCover(isPresented: binding(\.isDrawingSheetPresented)) {
                            DrawingEditorSheetView(
                                isPresented: binding(\.isDrawingSheetPresented),
                                cardDrawingData: binding(\.cardForEditor.drawingData)
                            )
                            .interactiveDismissDisabled()
                        }
                } else {
                    // Use our new, safe LoadingView.
                    // We give it the viewmodel and we give it the "password" (the onFinished closure)
                    // so it can tell us when it's done setting up.
                    LoadingView(viewModel: viewModel) {
                        // this closure gets called when loadingview is done.
                        // now we can safely flip the switch.
                        print("streetpassapp: loadingview finished, gonna set isappready = true now, fingers crossed ✨") // <-- like, right here
                        self.isAppReady = true
                    }
                }
            }
        }
    }
}
