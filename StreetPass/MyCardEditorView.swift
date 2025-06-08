// MyCardEditorView.swift
import SwiftUI

struct MyCardEditorView: View {
    @EnvironmentObject var viewModel: StreetPassViewModel
    @Environment(\.dismiss) var dismiss

    // Local state for all editable fields
    @State private var editorDisplayName: String = ""
    @State private var editorStatusMessage: String = ""
    @State private var editorAvatarSymbolName: String = "person.crop.circle.fill"
    @State private var editorFlairField1Title: String = "" // Non-optional State
    @State private var editorFlairField1Value: String = "" // Non-optional State
    @State private var editorFlairField2Title: String = "" // Non-optional State
    @State private var editorFlairField2Value: String = "" // Non-optional State

    // This will hold the drawing data from the view model for the preview
    // and will be updated if the drawing editor changes it.
    @State private var currentDrawingData: Data?

    let avatarSymbols: [String] = [
        "person.fill", "person.circle.fill", "face.smiling.fill", "heart.fill",
        "star.fill", "bolt.fill", "gamecontroller.fill", "music.mic", "paintbrush.fill"
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("Card Preview") {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: editorAvatarSymbolName)
                                .font(.title)
                            Text(editorDisplayName.isEmpty ? "Display Name" : editorDisplayName)
                                .font(.headline)
                        }
                        Text(editorStatusMessage.isEmpty ? "Status message..." : editorStatusMessage)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        // Preview for Flair Field 1
                        if !editorFlairField1Title.isEmpty || !editorFlairField1Value.isEmpty {
                            HStack {
                                Text(editorFlairField1Title.isEmpty ? "Flair 1 Title" : editorFlairField1Title)
                                    .font(.caption.bold())
                                Text(editorFlairField1Value)
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        }
                        // Preview for Flair Field 2
                        if !editorFlairField2Title.isEmpty || !editorFlairField2Value.isEmpty {
                             HStack {
                                Text(editorFlairField2Title.isEmpty ? "Flair 2 Title" : editorFlairField2Title)
                                    .font(.caption.bold())
                                Text(editorFlairField2Value)
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        }

                        if let drawingData = currentDrawingData, // Use @State currentDrawingData
                           let uiImage = UIImage(data: drawingData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 100)
                                .cornerRadius(8)
                                .padding(.top, 5)
                        }
                    }
                }

                Section("Edit Info") {
                    TextField("Display Name", text: $editorDisplayName)
                    TextField("Status Message (max 150 chars)", text: $editorStatusMessage)
                    
                    Picker("Avatar Symbol", selection: $editorAvatarSymbolName) {
                        ForEach(avatarSymbols, id: \.self) { symbolName in
                            HStack {
                                Image(systemName: symbolName)
                                Text(symbolName.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " ").capitalized)
                            }.tag(symbolName)
                        }
                    }
                }
                
                Section("Flair Fields (Optional)") {
                    TextField("Flair Title 1", text: $editorFlairField1Title)
                    TextField("Flair Value 1", text: $editorFlairField1Value)
                    TextField("Flair Title 2", text: $editorFlairField2Title)
                    TextField("Flair Value 2", text: $editorFlairField2Value)
                }


                Section("Drawing") {
                    if currentDrawingData != nil { // Use @State currentDrawingData
                        HStack {
                            Text("Card has a drawing.")
                            Spacer()
                            Button("Remove Drawing") {
                                self.currentDrawingData = nil // Update local state
                                viewModel.cardForEditor.drawingData = nil // also update viewModel's copy
                            }
                            .foregroundColor(.red)
                        }
                    }
                    Button(currentDrawingData == nil ? "Add Drawing" : "Edit Drawing") {
                        viewModel.openDrawingEditor()
                    }
                }
            }
            .navigationTitle("Edit My Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // No need to reset viewModel.cardForEditor if we used local @State
                        // just dismiss. The onAppear will reload fresh data next time.
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Sync local @State back to viewModel.cardForEditor before saving
                        viewModel.cardForEditor.displayName = editorDisplayName
                        viewModel.cardForEditor.statusMessage = editorStatusMessage
                        viewModel.cardForEditor.avatarSymbolName = editorAvatarSymbolName
                        
                        viewModel.cardForEditor.flairField1Title = editorFlairField1Title.isEmpty ? nil : editorFlairField1Title
                        viewModel.cardForEditor.flairField1Value = editorFlairField1Value.isEmpty ? nil : editorFlairField1Value
                        viewModel.cardForEditor.flairField2Title = editorFlairField2Title.isEmpty ? nil : editorFlairField2Title
                        viewModel.cardForEditor.flairField2Value = editorFlairField2Value.isEmpty ? nil : editorFlairField2Value
                        
                        // drawingData is already up-to-date in viewModel.cardForEditor
                        // because DrawingEditorSheetView binds directly to it.
                        // We just need to ensure our local preview state `currentDrawingData` is also in sync
                        // (though `onAppear` and `onChange` handle this for the preview).

                        viewModel.saveMyEditedCard()
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Initialize local @State vars from viewModel.cardForEditor
                self.editorDisplayName = viewModel.cardForEditor.displayName
                self.editorStatusMessage = viewModel.cardForEditor.statusMessage
                self.editorAvatarSymbolName = viewModel.cardForEditor.avatarSymbolName
                self.editorFlairField1Title = viewModel.cardForEditor.flairField1Title ?? ""
                self.editorFlairField1Value = viewModel.cardForEditor.flairField1Value ?? ""
                self.editorFlairField2Title = viewModel.cardForEditor.flairField2Title ?? ""
                self.editorFlairField2Value = viewModel.cardForEditor.flairField2Value ?? ""
                self.currentDrawingData = viewModel.cardForEditor.drawingData // Sync drawing data for preview
                print("MyCardEditorView onAppear, editorDisplayName: \(editorDisplayName)")
            }
            // This reacts if the drawing data changes from the DrawingEditorSheetView
            .onChange(of: viewModel.cardForEditor.drawingData) { _, newDrawingData in
                self.currentDrawingData = newDrawingData
            }
        }
    }
}
