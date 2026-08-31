import Foundation

/// What a prompt asks for when it comes to clipboard and window context (#55).
///
/// Three states rather than two because the global switches in AI Enhancement still
/// exist: a prompt that has no opinion should keep following them, so that changing the
/// global keeps meaning something. `Bool?` is the stored form — `nil` is `.inherit`.
enum ContextChoice: String, CaseIterable, Hashable {
    case inherit
    case on
    case off

    init(_ stored: Bool?) {
        switch stored {
        case .some(true): self = .on
        case .some(false): self = .off
        case .none: self = .inherit
        }
    }

    var value: Bool? {
        switch self {
        case .inherit: nil
        case .on: true
        case .off: false
        }
    }

    var label: String {
        switch self {
        case .inherit: "Default"
        case .on: "On"
        case .off: "Off"
        }
    }
}
