//
//  TranslateController.swift
//  Reynard
//
//  Thin bridge to the bundled “immersive translate” add-on. The add-on does all
//  the work in JavaScript; native code only makes sure the built-in extension is
//  installed and triggers its browser action when the page menu asks for it.
//

import Foundation
import GeckoView

@MainActor
final class TranslateController {
    static let shared = TranslateController()
    
    static let extensionID = "malaoshi-translate@malaoshi"
    static let extensionLocation = "resource://app/extensions/malaoshi_translate/"
    
    private var isReady = false
    private var isPreparing = false
    private var pendingToggle = false
    
    private init() {}
    
    // MARK: - Lifecycle
    
    func start() {
        prepareIfNeeded()
    }
    
    /// Toggles the immersive translation overlay on the page shown by `tab`.
    func toggleTranslation(for tab: Tab) {
        guard let urlString = tab.url,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return
        }
        
        guard isReady else {
            pendingToggle = true
            prepareIfNeeded()
            return
        }
        
        clickBrowserAction()
    }
    
    // MARK: - Installation
    
    private func prepareIfNeeded() {
        guard !isReady, !isPreparing else {
            return
        }
        isPreparing = true
        
        Task { @MainActor [weak self] in
            defer { self?.isPreparing = false }
            guard let self else {
                return
            }
            
            do {
                _ = try await AddonRuntime.shared.ensureBuiltIn(
                    location: Self.extensionLocation,
                    id: Self.extensionID
                )
                isReady = true
                if pendingToggle {
                    pendingToggle = false
                    clickBrowserAction()
                }
            } catch {
                NSLog("Failed to install the translate add-on: %@", "\(error)")
            }
        }
    }
    
    // MARK: - Action
    
    private func clickBrowserAction() {
        Task { @MainActor in
            guard let addon = try? await AddonRuntime.shared.addon(byID: Self.extensionID) else {
                return
            }
            _ = try? await AddonRuntime.shared.clickAction(kind: .browser, addon: addon)
        }
    }
}
