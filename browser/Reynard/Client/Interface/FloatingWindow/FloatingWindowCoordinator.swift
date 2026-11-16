//
//  FloatingWindowCoordinator.swift
//  Reynard
//
//  Owns the floating page window: which tab is floating, where the panel lives,
//  and how the page travels between the main content view and the panel.
//

import GeckoView
import UIKit

@MainActor
final class FloatingWindowCoordinator {
    private enum UX {
        static let animationDuration: TimeInterval = 0.24
    }
    
    private weak var browserViewController: BrowserViewController?
    private(set) var panel: FloatingWebWindow?
    private(set) var floatedTabID: UUID?
    
    var isFloating: Bool {
        return floatedTabID != nil
    }
    
    func attach(to browserViewController: BrowserViewController) {
        self.browserViewController = browserViewController
    }
    
    func toggle() {
        if isFloating {
            restore(selectingTab: true, animated: true)
        } else {
            floatSelectedTab()
        }
    }
    
    // MARK: - Floating
    
    private func floatSelectedTab() {
        guard panel == nil,
              let browserViewController,
              let tab = browserViewController.tabManager.selectedTab else {
            return
        }
        
        guard let urlString = tab.url,
              let url = URL(string: urlString),
              url.host != nil else {
            presentUnavailableAlert()
            return
        }
        
        guard tab.session.isOpen() else {
            presentUnavailableAlert()
            return
        }
        
        let mode: TabMode = tab.isPrivate ? .private : .regular
        let tabID = tab.id
        
        browserViewController.loadViewIfNeeded()
        
        // Hand the engine view over to the panel before the browser switches to
        // another tab, otherwise the two containers would fight over it.
        if browserViewController.contentView.isDisplaying(session: tab.session) {
            browserViewController.contentView.detachDisplayedSession()
        }
        
        let hostView = browserViewController.view ?? UIView()
        let window = FloatingWebWindow(frame: .zero)
        window.onExpand = { [weak self] in
            self?.restore(selectingTab: true, animated: true)
        }
        window.onClose = { [weak self] in
            self?.restore(selectingTab: false, animated: true)
        }
        window.updateTitle(tab.title)
        window.applyPreferredSize(in: hostView.bounds)
        window.attach(session: tab.session)
        window.alpha = 0
        hostView.addSubview(window)
        
        UIView.animate(withDuration: UX.animationDuration) {
            window.alpha = 1
        }
        
        panel = window
        floatedTabID = tabID
        
        showAnotherTab(mode: mode)
        browserViewController.floatingWindowDidChangeState()
    }
    
    /// Moves the browser away from the floating tab so the main area keeps working.
    private func showAnotherTab(mode: TabMode) {
        guard let browserViewController else {
            return
        }
        
        let tabManager = browserViewController.tabManager
        let tabs = mode == .private ? tabManager.privateTabs : tabManager.regularTabs
        guard tabs.count > 1 else {
            browserViewController.createNewTab(mode: mode)
            return
        }
        
        let currentIndex = tabManager.selectedTabIndex
        let remaining = tabs.indices.filter { $0 != currentIndex }
        guard let targetIndex = remaining.last else {
            browserViewController.createNewTab(mode: mode)
            return
        }
        
        tabManager.selectTab(at: targetIndex, mode: mode)
    }
    
    // MARK: - Restoring
    
    func restore(selectingTab: Bool, animated: Bool) {
        guard let panel else {
            reset()
            return
        }
        
        let tabID = floatedTabID
        panel.detachSession()
        
        let finish = { [weak self, weak panel] in
            panel?.removeFromSuperview()
            self?.reset()
            if selectingTab, let tabID {
                self?.selectTab(withID: tabID)
            }
        }
        
        if animated {
            UIView.animate(withDuration: UX.animationDuration) {
                panel.alpha = 0
                panel.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            } completion: { _ in
                finish()
            }
        } else {
            finish()
        }
    }
    
    private func selectTab(withID tabID: UUID) {
        guard let browserViewController else {
            return
        }
        
        let tabManager = browserViewController.tabManager
        let modesAndTabs: [(mode: TabMode, tabs: [Tab])] = [
            (mode: .regular, tabs: tabManager.regularTabs),
            (mode: .private, tabs: tabManager.privateTabs),
        ]
        for entry in modesAndTabs {
            guard let index = entry.tabs.firstIndex(where: { $0.id == tabID }) else {
                continue
            }
            
            if tabManager.selectedTabMode == entry.mode, tabManager.selectedTabIndex == index {
                browserViewController.contentView.reattachDisplayedSession()
            } else {
                tabManager.selectTab(at: index, mode: entry.mode)
            }
            browserViewController.floatingWindowDidChangeState()
            return
        }
    }
    
    private func reset() {
        panel = nil
        floatedTabID = nil
        browserViewController?.floatingWindowDidChangeState()
    }
    
    // MARK: - State Sync
    
    /// Keeps the panel honest when tabs are closed or replaced elsewhere.
    func handleTabsChanged() {
        guard let tabID = floatedTabID, let browserViewController else {
            return
        }
        
        let tabManager = browserViewController.tabManager
        let regularMatch = tabManager.regularTabs.first(where: { $0.id == tabID })
        let privateMatch = tabManager.privateTabs.first(where: { $0.id == tabID })
        
        guard let tab = regularMatch ?? privateMatch else {
            restore(selectingTab: false, animated: true)
            return
        }
        
        panel?.updateTitle(tab.title)
    }
    
    /// Called when the floating tab reports a new title or location.
    func updateTitleIfNeeded(for tab: Tab) {
        guard tab.id == floatedTabID else {
            return
        }
        panel?.updateTitle(tab.title)
    }
    
    func updateLayoutIfNeeded() {
        guard let panel, let hostView = panel.superview else {
            return
        }
        
        let bounds = hostView.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }
        
        var frame = panel.frame
        frame.size.width = min(frame.width, bounds.width - 20)
        frame.size.height = min(frame.height, bounds.height - 20)
        frame.origin.x = min(max(frame.origin.x, 10), max(10, bounds.width - frame.width - 10))
        frame.origin.y = min(max(frame.origin.y, 10), max(10, bounds.height - frame.height - 10))
        panel.frame = frame
    }
    
    private func presentUnavailableAlert() {
        guard let browserViewController else {
            return
        }
        
        let alert = UIAlertController(
            title: NSLocalizedString("Floating Window Unavailable", comment: ""),
            message: NSLocalizedString("Open a web page first, then try again.", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        browserViewController.present(alert, animated: true)
    }
}
