// DrawingCanvasView.swift
import SwiftUI
import UIKit

struct DrawingCanvasView: UIViewRepresentable {
    @Binding var drawingViewInstance: DrawingView
    
    @Binding var selectedColor: Color
    @Binding var selectedLineWidth: CGFloat
    
    @Binding var canUndoDrawing: Bool
    @Binding var canRedoDrawing: Bool


    func makeUIView(context: Context) -> DrawingView {
        let view = DrawingView()
        view.setDrawingColor(UIColor(selectedColor))
        view.setLineWidth(selectedLineWidth)
        
        // Set initial undo/redo state
        DispatchQueue.main.async {
            self.canUndoDrawing = view.canUndo
            self.canRedoDrawing = view.canRedo
            self.drawingViewInstance = view
        }
        
      
        context.coordinator.drawingView = view // Give coordinator access
        return view
    }

    func updateUIView(_ uiView: DrawingView, context: Context) {
        uiView.setDrawingColor(UIColor(selectedColor))
        uiView.setLineWidth(selectedLineWidth)

        DispatchQueue.main.async {
            if self.canUndoDrawing != uiView.canUndo { self.canUndoDrawing = uiView.canUndo }
            if self.canRedoDrawing != uiView.canRedo { self.canRedoDrawing = uiView.canRedo }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: DrawingCanvasView
        weak var drawingView: DrawingView? // Keep a weak reference to the UIKit view

        init(_ parent: DrawingCanvasView) {
            self.parent = parent
        }


        @objc func drawingDidChange() {
            // this func seems unused now, direct updates handle it
            // //tf??? why was this even here if not called?
            if let view = drawingView {
                parent.canUndoDrawing = view.canUndo
                parent.canRedoDrawing = view.canRedo
            }
        }
    }
}

struct DrawingEditorSheetView: View {
    @Binding var isPresented: Bool
    @Binding var cardDrawingData: Data?

    @State private var uiKitDrawingView = DrawingView() // Actual UIKit view instance
    @State private var selectedColor: Color = .black
    @State private var selectedLineWidth: CGFloat = 5.0
    
    @State private var canUndo: Bool = false // Local state driven by DrawingCanvasView
    @State private var canRedo: Bool = false // Local state driven by DrawingCanvasView

    let colors: [Color] = [.black, .red, .blue, .green, .yellow, .orange, .purple, .gray, AppTheme.primaryColor, Color(UIColor.white) /* Eraser */]
    let lineWidths: [CGFloat] = [2.0, 5.0, 10.0, 20.0]
    
    private let drawingCanvasFixedSize = CGSize(width: 300, height: 225) // Adjusted slightly
    private let outputImageCompressionQuality: CGFloat = 0.5 // High compression for BLE

    var body: some View {
        NavigationView {
            VStack(spacing: 8) { // Reduced global spacing
                DrawingCanvasView(
                    drawingViewInstance: $uiKitDrawingView,
                    selectedColor: $selectedColor,
                    selectedLineWidth: $selectedLineWidth,
                    canUndoDrawing: $canUndo, // Bind to local state
                    canRedoDrawing: $canRedo  // Bind to local state
                )
                .frame(width: drawingCanvasFixedSize.width, height: drawingCanvasFixedSize.height)
                .background(Color.white) // Canvas drawing area background
                .border(Color.gray.opacity(0.5), width: 1)
                .padding(.horizontal) // Give IT some side padding
                .padding(.top)


                VStack(spacing: 10) {
                    Text("Color").font(.caption).foregroundColor(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(colors, id: \.self) { color in
                                Button { selectedColor = color } label: {
                                    Circle().fill(color)
                                        .frame(width: 28, height: 28)
                                        .overlay(Circle().stroke(selectedColor == color ? AppTheme.primaryColor : Color.gray.opacity(0.5), lineWidth: 2))
                                        .padding(2)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 35)

                    Text("Line Width").font(.caption).foregroundColor(.secondary)
                    Picker("Line Width", selection: $selectedLineWidth) {
                        ForEach(lineWidths, id: \.self) { width in Text("\(Int(width))px").tag(width) }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)

                    HStack(spacing: 15) {
                        Button { uiKitDrawingView.undo(); updateUndoRedoFromView() } label: { Label("Undo", systemImage: "arrow.uturn.backward.circle") }
                            .disabled(!canUndo)
                        Button { uiKitDrawingView.redo(); updateUndoRedoFromView() } label: { Label("Redo", systemImage: "arrow.uturn.forward.circle") }
                            .disabled(!canRedo)
                        Spacer()
                        Button { uiKitDrawingView.clearDrawing(); updateUndoRedoFromView() } label: { Label("Clear", systemImage: "trash") }
                            .foregroundColor(AppTheme.destructiveColor) // Make clear more distinct
                    }
                    .padding([.horizontal, .top])
                    .buttonStyle(.bordered)
                }
                .padding(.bottom)
                
                Spacer() // Pushes controls up if space available
            }
            .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.bottom))
            .navigationTitle("Draw Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        let image = uiKitDrawingView.getDrawingImage(targetSize: drawingCanvasFixedSize, backgroundColor: .white)
                        
                        if let jpegData = image.jpegData(compressionQuality: outputImageCompressionQuality) {
                            self.cardDrawingData = jpegData
                            print("Drawing saved as JPEG, data size: \(jpegData.count) bytes")
                        } else if let pngData = image.pngData() {
                            self.cardDrawingData = pngData
                             print("Drawing saved as PNG (JPEG failed), data size: \(pngData.count) bytes")
                        } else {
                            print("Failed to get drawing data.")
                            // this aint good lol
                            // self.cardDrawingData = nil // Or display error
                        }
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .onAppear {
                // lol, why here?
                updateUndoRedoFromView()
            }
        }
    }
    
    // Helper to sync SwiftUI's @State with the UIKit view's state
    private func updateUndoRedoFromView() {
        canUndo = uiKitDrawingView.canUndo
        canRedo = uiKitDrawingView.canRedo
    }
}
