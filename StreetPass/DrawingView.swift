// DrawingView.swift
import UIKit

// Helper struct to store path, color, and line width
struct DrawablePath {
    var path: UIBezierPath
    var color: UIColor
    var lineWidth: CGFloat
}

class DrawingView: UIView {
    private var paths: [DrawablePath] = []
    private var currentPath: UIBezierPath?
    private var currentColor: UIColor = .black
    private var currentLineWidth: CGFloat = 5.0

    private var redoablePaths: [DrawablePath] = []

    var canUndo: Bool { !paths.isEmpty }
    var canRedo: Bool { !redoablePaths.isEmpty }
    
    // Public configuration
    func setDrawingColor(_ color: UIColor) {
        self.currentColor = color
    }

    func setLineWidth(_ width: CGFloat) {
        self.currentLineWidth = width
    }

    func clearDrawing() {
        paths.removeAll()
        redoablePaths.removeAll()
        currentPath = nil
        setNeedsDisplay()
        updateUndoRedoStates()
    }

    func undo() {
        guard !paths.isEmpty else { return }
        let lastPath = paths.removeLast()
        redoablePaths.append(lastPath)
        setNeedsDisplay()
        updateUndoRedoStates()
    }

    func redo() {
        guard !redoablePaths.isEmpty else { return }
        let pathToRedo = redoablePaths.removeLast()
        paths.append(pathToRedo)
        setNeedsDisplay()
        updateUndoRedoStates()
    }
    
    
    func updateUndoRedoStates() {
        // This function primarily exists to trigger KVO or some notification if this
        // class were an ObservableObject used directly. For UIViewRepresentable,
        // the bindings in the wrapper + .onChange in SwiftUI view handle this.
    }

    func getDrawingImage(targetSize: CGSize? = nil, backgroundColor: UIColor = .white) -> UIImage {
        let actualSize = targetSize ?? self.bounds.size
        guard actualSize != .zero, actualSize.width > 0, actualSize.height > 0 else {
            print("DrawingView Error: Attempted to get image with zero or negative size: \(actualSize). Returning empty UIImage.")
            return UIImage()
        }

        let renderer = UIGraphicsImageRenderer(size: actualSize)
        return renderer.image { context in
            backgroundColor.setFill()
            context.fill(CGRect(origin: .zero, size: actualSize))

            let originalBounds = self.bounds
            if originalBounds.size != .zero && actualSize != originalBounds.size && originalBounds.width > 0 && originalBounds.height > 0 {
                let scaleX = actualSize.width / originalBounds.width
                let scaleY = actualSize.height / originalBounds.height
                context.cgContext.scaleBy(x: scaleX, y: scaleY)
            }
            
            for drawablePath in paths {
                drawablePath.color.setStroke()
                drawablePath.path.lineWidth = drawablePath.lineWidth
                drawablePath.path.stroke()
            }
        }
    }
    
    func setDrawing(from newPaths: [DrawablePath]) { // Renamed parameter for clarity
        self.paths = newPaths
        self.redoablePaths.removeAll()
        setNeedsDisplay()
        updateUndoRedoStates()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear // Let parent control background, or canvas itself. Let's try clear for more flexibility.
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.backgroundColor = .clear
        setupView()
    }

    private func setupView() {
        isMultipleTouchEnabled = false
        // Set contentMode to redraw on bounds change, though manual setNeedsDisplay is often used.
        // self.contentMode = .redraw
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        currentPath = UIBezierPath()
        currentPath?.lineWidth = currentLineWidth
        currentPath?.lineCapStyle = .round
        currentPath?.lineJoinStyle = .round
        currentPath?.move(to: point)
        redoablePaths.removeAll() // Clear redo stack on new stroke
        // updateUndoRedoStates() // Not strictly needed here if not observing directly
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let path = currentPath else { return }
        let point = touch.location(in: self)
        path.addLine(to: point)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let path = currentPath else { return }
        paths.append(DrawablePath(path: path, color: currentColor, lineWidth: currentLineWidth))
        currentPath = nil
        setNeedsDisplay()
        updateUndoRedoStates()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentPath = nil
        setNeedsDisplay()
        // updateUndoRedoStates() // If a stroke was in progress
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)




        for drawablePath in paths {
            drawablePath.color.setStroke()
            drawablePath.path.lineWidth = drawablePath.lineWidth
            drawablePath.path.stroke()
        }

        if let currentDrawingPath = currentPath {
            currentColor.setStroke()
            currentDrawingPath.lineWidth = currentLineWidth
            currentDrawingPath.stroke()
        }
    }
}
