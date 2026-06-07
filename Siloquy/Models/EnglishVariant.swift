import Foundation

/// The English spelling convention to apply during AI enhancement.
enum EnglishVariant: String, CaseIterable {
    case american  = "en-US"
    case australian = "en-AU"
    case british   = "en-GB"
    case canadian  = "en-CA"

    var displayName: String {
        switch self {
        case .american:   return "American English"
        case .australian: return "Australian English"
        case .british:    return "British English"
        case .canadian:   return "Canadian English"
        }
    }

    /// Instruction appended to the system message. Nil for American (the LLM default).
    var promptInstruction: String? {
        switch self {
        case .american:
            return nil
        case .australian:
            return "Use Australian English spelling and conventions throughout " +
                   "(e.g. 'colour' not 'color', 'organise' not 'organize', " +
                   "'realise' not 'realize', 'favour' not 'favor')."
        case .british:
            return "Use British English spelling and conventions throughout " +
                   "(e.g. 'colour' not 'color', 'organise' not 'organize', " +
                   "'realise' not 'realize', 'centre' not 'center')."
        case .canadian:
            return "Use Canadian English spelling and conventions throughout " +
                   "(e.g. 'colour' not 'color', but 'organize' not 'organise', " +
                   "'recognize' not 'recognise')."
        }
    }
}
