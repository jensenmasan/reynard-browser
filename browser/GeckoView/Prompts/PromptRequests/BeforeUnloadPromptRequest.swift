//
//  BeforeUnloadPromptRequest.swift
//  Reynard
//
//  The page is asking for confirmation before it unloads, usually because a
//  form contains unsaved changes. Gecko only delivers this prompt when
//  `dom.disable_beforeunload` is false.
//

import Foundation

public struct BeforeUnloadPromptRequest {
    public let id: String
    public let title: String
    public let message: String

    public init(id: String, title: String, message: String) {
        self.id = id
        self.title = title
        self.message = message
    }
}
