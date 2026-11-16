//
//  BookmarkRowActions.swift
//  Reynard
//
//  Long-press menu for rows in the Bookmarks list.
//

import UIKit

struct BookmarkRowActions {
    private static func copyAction(url: URL) -> UIAction {
        return UIAction(title: NSLocalizedString("Copy Link", comment: ""), image: UIImage(named: "reynard.document.on.document")) { _ in
            UIPasteboard.general.string = url.absoluteString
        }
    }
    
    private static func openActions(
        openInNewTab: @escaping () -> Void,
        openInNewPrivateTab: @escaping () -> Void
    ) -> UIMenu {
        return UIMenu(title: "", options: .displayInline, children: [
            UIAction(title: NSLocalizedString("Open in New Tab", comment: ""), image: UIImage(named: "reynard.plus.square.on.square")) { _ in
                openInNewTab()
            },
            UIAction(title: NSLocalizedString("Open in New Private Tab", comment: ""), image: UIImage(named: "reynard.plus.square.fill.on.square.fill")) { _ in
                openInNewPrivateTab()
            },
        ])
    }
    
    static func configuration(
        for bookmark: BookmarkSnapshot,
        openInNewTab: @escaping () -> Void,
        openInNewPrivateTab: @escaping () -> Void,
        shareLink: @escaping (URL) -> Void,
        editBookmark: @escaping () -> Void,
        deleteBookmark: @escaping () -> Void
    ) -> UIContextMenuConfiguration {
        return UIContextMenuConfiguration(identifier: bookmark.guid as NSString, previewProvider: nil) { _ in
            UIMenu(title: "", children: [
                openActions(
                    openInNewTab: openInNewTab,
                    openInNewPrivateTab: openInNewPrivateTab
                ),
                UIMenu(title: "", options: .displayInline, children: [
                    copyAction(url: bookmark.url),
                    UIAction(title: NSLocalizedString("Share Link", comment: ""), image: UIImage(named: "reynard.square.and.arrow.up")) { _ in
                        shareLink(bookmark.url)
                    },
                ]),
                UIMenu(title: "", options: .displayInline, children: [
                    UIAction(title: NSLocalizedString("Edit Bookmark", comment: ""), image: UIImage(named: "reynard.pencil")) { _ in
                        editBookmark()
                    },
                    UIAction(
                        title: NSLocalizedString("Delete Bookmark", comment: ""),
                        image: UIImage(named: "reynard.trash"),
                        attributes: .destructive
                    ) { _ in
                        deleteBookmark()
                    },
                ]),
            ])
        }
    }
    
    static func configuration(
        for folder: BookmarkFolderSnapshot,
        openFolder: @escaping () -> Void,
        deleteFolder: @escaping () -> Void
    ) -> UIContextMenuConfiguration {
        return UIContextMenuConfiguration(identifier: folder.guid as NSString, previewProvider: nil) { _ in
            var children: [UIMenuElement] = [
                UIAction(title: NSLocalizedString("Open Folder", comment: ""), image: UIImage(named: "reynard.folder")) { _ in
                    openFolder()
                }
            ]
            
            if !folder.isProtected {
                children.append(
                    UIMenu(title: "", options: .displayInline, children: [
                        UIAction(
                            title: NSLocalizedString("Delete Folder", comment: ""),
                            image: UIImage(named: "reynard.trash"),
                            attributes: .destructive
                        ) { _ in
                            deleteFolder()
                        },
                    ])
                )
            }
            
            return UIMenu(title: "", children: children)
        }
    }
}
