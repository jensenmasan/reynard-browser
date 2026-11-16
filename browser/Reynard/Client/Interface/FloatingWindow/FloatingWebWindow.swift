//
//  FloatingWebWindow.swift
//  Reynard
//
//  A draggable, resizable mini window that hosts a live Gecko session on top of
//  the browser UI. Used by “Floating Window” in the page menu so a page keeps
//  playing while you browse something else.
//

import GeckoView
import UIKit

final class FloatingWebWindow: UIView {
    private enum UX {
        static let cornerRadius: CGFloat = 18
        static let headerHeight: CGFloat = 34
        static let edgeInset: CGFloat = 10
        static let gripSize: CGFloat = 34
        static let minimumSize = CGSize(width: 170, height: 150)
        static let maximumSizeRatio: CGFloat = 0.85
        static let buttonSize: CGFloat = 26
        static let shadowOpacity: Float = 0.22
        static let shadowRadius: CGFloat = 18
    }
    
    private let contentContainer = UIView()
    private let headerBar = UIView()
    private let titleLabel = UILabel()
    private let expandButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let gripView = UIView()
    let geckoView = GeckoView()
    
    private var dragStartCenter: CGPoint = .zero
    private var resizeStartFrame: CGRect = .zero
    
    var onExpand: (() -> Void)?
    var onClose: (() -> Void)?
    
    // MARK: - Lifecycle
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        configureHierarchy()
        configureGestures()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Configuration
    
    private func configureAppearance() {
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = []
        backgroundColor = .clear
        
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = UX.shadowOpacity
        layer.shadowRadius = UX.shadowRadius
        layer.shadowOffset = CGSize(width: 0, height: 8)
        
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.backgroundColor = .secondarySystemBackground
        contentContainer.layer.cornerRadius = UX.cornerRadius
        contentContainer.layer.cornerCurve = .continuous
        contentContainer.clipsToBounds = true
        
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerBar.backgroundColor = .tertiarySystemBackground
        headerBar.isUserInteractionEnabled = true
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = NSLocalizedString("Floating Window", comment: "")
        
        geckoView.translatesAutoresizingMaskIntoConstraints = false
        geckoView.backgroundColor = .systemBackground
        geckoView.clipsToBounds = true
        
        configureButtons()
    }
    
    private func configureButtons() {
        for button in [expandButton, closeButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tintColor = .secondaryLabel
            button.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(pointSize: 11, weight: .bold),
                forImageIn: .normal
            )
        }
        
        expandButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        expandButton.accessibilityLabel = NSLocalizedString("Open in Full Screen", comment: "")
        expandButton.addTarget(self, action: #selector(handleExpand), for: .touchUpInside)
        
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.accessibilityLabel = NSLocalizedString("Close Floating Window", comment: "")
        closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
    }
    
    private func configureHierarchy() {
        addSubview(contentContainer)
        contentContainer.addSubview(headerBar)
        headerBar.addSubview(titleLabel)
        headerBar.addSubview(closeButton)
        headerBar.addSubview(expandButton)
        contentContainer.addSubview(geckoView)
        
        gripView.translatesAutoresizingMaskIntoConstraints = false
        gripView.backgroundColor = .clear
        gripView.isUserInteractionEnabled = true
        addSubview(gripView)
        
        let gripImage = UIImageView(image: UIImage(systemName: "arrow.down.right"))
        gripImage.translatesAutoresizingMaskIntoConstraints = false
        gripImage.tintColor = .secondaryLabel.withAlphaComponent(0.6)
        gripImage.contentMode = .scaleAspectFit
        gripImage.isUserInteractionEnabled = false
        gripView.addSubview(gripImage)
        
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            headerBar.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: UX.headerHeight),
            
            titleLabel.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -6),
            
            expandButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -2),
            expandButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            expandButton.widthAnchor.constraint(equalToConstant: UX.buttonSize),
            expandButton.heightAnchor.constraint(equalToConstant: UX.buttonSize),
            
            closeButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: UX.buttonSize),
            closeButton.heightAnchor.constraint(equalToConstant: UX.buttonSize),
            
            geckoView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            geckoView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            geckoView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            geckoView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            
            gripView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 6),
            gripView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 6),
            gripView.widthAnchor.constraint(equalToConstant: UX.gripSize),
            gripView.heightAnchor.constraint(equalToConstant: UX.gripSize),
            
            gripImage.centerXAnchor.constraint(equalTo: gripView.centerXAnchor, constant: -4),
            gripImage.centerYAnchor.constraint(equalTo: gripView.centerYAnchor, constant: -4),
            gripImage.widthAnchor.constraint(equalToConstant: 14),
            gripImage.heightAnchor.constraint(equalToConstant: 14),
        ])
    }
    
    private func configureGestures() {
        let movePan = UIPanGestureRecognizer(target: self, action: #selector(handleMovePan(_:)))
        headerBar.addGestureRecognizer(movePan)
        
        let resizePan = UIPanGestureRecognizer(target: self, action: #selector(handleResizePan(_:)))
        gripView.addGestureRecognizer(resizePan)
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleExpand))
        doubleTap.numberOfTapsRequired = 2
        headerBar.addGestureRecognizer(doubleTap)
    }
    
    // MARK: - Session
    
    func attach(session: GeckoSession) {
        geckoView.session = session
    }
    
    /// Releases the engine view so another `GeckoView` can adopt it again.
    func detachSession() {
        geckoView.session = nil
    }
    
    func updateTitle(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        titleLabel.text = trimmed.isEmpty
        ? NSLocalizedString("Floating Window", comment: "")
        : trimmed
    }
    
    func applyPreferredSize(in bounds: CGRect) {
        let maxWidth = bounds.width * UX.maximumSizeRatio
        let width = min(max(220, bounds.width * 0.56), maxWidth)
        let height = min(max(width * 1.25, UX.minimumSize.height), bounds.height * 0.6)
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        center = CGPoint(
            x: bounds.maxX - width / 2 - UX.edgeInset * 2,
            y: bounds.maxY - height / 2 - UX.edgeInset * 4
        )
    }
    
    // MARK: - Gestures
    
    @objc private func handleMovePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview else {
            return
        }
        
        let translation = gesture.translation(in: superview)
        switch gesture.state {
        case .began:
            dragStartCenter = center
        case .changed, .ended:
            var target = CGPoint(
                x: dragStartCenter.x + translation.x,
                y: dragStartCenter.y + translation.y
            )
            let insets = superview.safeAreaInsets
            let minX = bounds.width / 2 + UX.edgeInset + insets.left
            let maxX = superview.bounds.width - bounds.width / 2 - UX.edgeInset - insets.right
            let minY = bounds.height / 2 + UX.edgeInset + insets.top
            let maxY = superview.bounds.height - bounds.height / 2 - UX.edgeInset - insets.bottom
            target.x = min(max(target.x, minX), max(minX, maxX))
            target.y = min(max(target.y, minY), max(minY, maxY))
            center = target
        default:
            break
        }
    }
    
    @objc private func handleResizePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview else {
            return
        }
        
        let translation = gesture.translation(in: superview)
        switch gesture.state {
        case .began:
            resizeStartFrame = frame
        case .changed, .ended:
            let maximumWidth = superview.bounds.width - frame.minX - UX.edgeInset
            let maximumHeight = superview.bounds.height - frame.minY - UX.edgeInset
            let width = min(max(resizeStartFrame.width + translation.x, UX.minimumSize.width), max(UX.minimumSize.width, maximumWidth))
            let height = min(max(resizeStartFrame.height + translation.y, UX.minimumSize.height), max(UX.minimumSize.height, maximumHeight))
            frame = CGRect(x: resizeStartFrame.minX, y: resizeStartFrame.minY, width: width, height: height)
        default:
            break
        }
    }
    
    @objc private func handleExpand() {
        onExpand?()
    }
    
    @objc private func handleClose() {
        onClose?()
    }
}
