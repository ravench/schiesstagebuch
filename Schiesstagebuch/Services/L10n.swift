import Foundation

// Localization: German is the source language; en, fr and it live in Localizable.xcstrings.
// Literals in Text/Button/Label/... are looked up automatically. Strings built at
// runtime (enum titles, helper parameters, ternaries) go through `.loc` or String(localized:).
extension String {
    /// Looks up this string as a key in Localizable.xcstrings.
    var loc: String { String(localized: String.LocalizationValue(self)) }
}
