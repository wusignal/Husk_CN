// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Looks a runtime string up in Localizable.strings.
///
/// SwiftUI translates a `Text("literal")` by itself: the literal is a
/// LocalizedStringKey and the table is consulted for it. A string built at
/// runtime is a plain `String` instead -- a status line, an error from a model,
/// a title picked by a switch -- and SwiftUI draws that verbatim. `Text(L(x))`
/// resolves it the same way the literal would be resolved, and a string with no
/// entry falls back to the English it was given, so a translation that is not
/// there yet cannot blank a screen out.
func L(_ text: String) -> String {
    NSLocalizedString(text, tableName: nil, bundle: .main, value: text, comment: "")
}

/// The same lookup for a format string with %@ or %lld slots, filled in here
/// rather than by SwiftUI: interpolation done before the lookup has already
/// eaten the placeholders, so the translated entry could never match.
func L(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(format, tableName: nil, bundle: .main,
                                     value: format, comment: ""),
           arguments: arguments)
}
