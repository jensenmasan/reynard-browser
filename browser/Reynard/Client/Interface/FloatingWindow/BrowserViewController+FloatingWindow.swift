//
//  BrowserViewController+FloatingWindow.swift
//  Reynard
//

import UIKit

extension BrowserViewController {
    /// Puts the current page into the floating window, or brings it back.
    func toggleFloatingWindow() {
        floatingWindowCoordinator.toggle()
    }
    
    func floatingWindowDidChangeState() {
        // The page menu reflects whether a page is currently floating.
        refreshAddressBar()
    }
}
