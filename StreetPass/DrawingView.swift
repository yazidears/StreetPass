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

    // Store paths to be undone
    private var redoablePaths: [DrawablePath] = []

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
    }

    func undo() {
        guard !paths.isEmpty else { return }
        let lastPath = paths.removeLast()
        redoablePaths.append(lastPath)
        setNeedsDisplay()
    }

    func redo() {
        guard !redoablePaths.isEmpty else { return }
        let pathToRedo = redoablePaths.removeLast()
        paths.append(pathToRedo)
        setNeedsDisplay()
    }
    
    var canUndo: Bool { !paths.isEmpty }
    var canRedo: Bool { !redoablePaths.isEmpty }


    // Get the current drawing as a UIImage
    // Added parameters for output size and background color
    func getDrawingImage(targetSize: CGSize? = nil, backgroundColor: UIColor = .white) -> UIImage {
        let actualSize = targetSize ?? self.bounds.size
        if actualSize == .zero { return UIImage() } // Avoid crash if size is zero

        let renderer = UIGraphicsImageRenderer(size: actualSize)
        return renderer.image { context in
            // Fill background
            backgroundColor.setFill()
            context.fill(CGRect(origin: .zero, size: actualSize))

            // Scale and draw paths
            let originalBounds = self.bounds
            if originalBounds.size != .zero && actualSize != originalBounds.size {
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
    
    
    func setDrawing(from paths: [DrawablePath]) {
        self.paths = paths
        self.redoablePaths.removeAll()
        setNeedsDisplay()
    }


    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .white // Default canvas background
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.backgroundColor = .white
        setupView()
    }

    private func setupView() {
        isMultipleTouchEnabled = false
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
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentPath = nil
        setNeedsDisplay()
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
