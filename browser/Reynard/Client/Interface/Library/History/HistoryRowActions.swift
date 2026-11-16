//
//  HistoryRowActions.swift
//  Reynard
//
//  Long-press menu for rows in the History list.
//

import UIKit

struct HistoryRowActions {
    static func configuration(
        for item: HistorySiteSnapshot,
        openInNewTab: @escaping () -> Void,
        openInNewPrivateTab: @escaping () -> Void,
        shareLink: @escaping (URL) -> Void,
        deleteEntry: @escaping () -> Void
    ) -> UIContextMenuConfiguration {
        return UIContextMenuConfiguration(identifier: "\(item.id)" as NSString, previewProvider: nil) { _ in
            UIMenu(title: "", children: [
                UIMenu(title: "", options: .displayInline, children: [
                    UIAction(title: NSLocalizedString("Open in New Tab", comment: ""), image: UIImage(named: "reynard.plus.square.on.square")) { _ in
                        openInNewTab()
                    },
                    UIAction(title: NSLocalizedString("Open in New Private Tab", comment: ""), image: UIImage(named: "reynard.plus.square.fill.on.square.fill")) { _ in
                        openInNewPrivateTab()
                    },
                ]),
                UIMenu(title: "", options: .displayInline, children: [
                    UIAction(title: NSLocalizedString("Copy Link", comment: ""), image: UIImage(named: "reynard.document.on.document")) { _ in
                        UIPasteboard.general.string = item.url.absoluteString
                    },
                    UIAction(title: NSLocalizedString("Share Link", comment: ""), image: UIImage(named: "reynard.square.and.arrow.up")) { _ in
                        shareLink(item.url)
                    },
                ]),
                UIMenu(title: "", options: .displayInline, children: [
                    UIAction(
                        title: NSLocalizedString("Delete from History", comment: ""),
                        image: UIImage(named: "reynard.trash"),
                        attributes: .destructive
                    ) { _ in
                        deleteEntry()
                    },
                ]),
            ])
        }
    }
}
