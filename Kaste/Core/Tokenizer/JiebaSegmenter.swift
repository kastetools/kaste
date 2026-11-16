import Foundation

/// Swift front-door to the Jieba C++ tokenizer. Holds a single lazy
/// instance — the first `cut(_:)` call loads ~10 MB of dictionaries off
/// disk (~100-500 ms); every call after that is pure CPU and fine on the
/// main thread for sentence-length input.
///
/// `tokenize(_:)` is the preferred entry point for the Word Picker: it
/// drops pure-whitespace / pure-punctuation tokens and re-anchors the
/// surviving words back to their original `String.Index` ranges so the
/// picker can reassemble selected spans with the original spacing.
enum JiebaSegmenter {

    private static let shared: JiebaBridge? = {
        let bundle = Bundle.main
        guard
            let dict      = bundle.path(forResource: "jieba.dict",  ofType: "utf8"),
            let hmm       = bundle.path(forResource: "hmm_model",   ofType: "utf8"),
            let userDict  = bundle.path(forResource: "user.dict",   ofType: "utf8"),
            let idf       = bundle.path(forResource: "idf",         ofType: "utf8"),
            let stopWords = bundle.path(forResource: "stop_words",  ofType: "utf8")
        else {
            NSLog("[Jieba] dict resources missing from app bundle")
            return nil
        }
        return JiebaBridge(
            dictPath:      dict,
            hmmPath:       hmm,
            userDict:      userDict,
            idfPath:       idf,
            stopWordsPath: stopWords
        )
    }()

    /// Raw cut output — mostly whitespace / punctuation tokens still
    /// mixed in. Callers that want ready-to-display chips should use
    /// `tokenize(_:)` instead.
    static func rawCut(_ text: String) -> [String] {
        shared?.cutText(text) ?? []
    }

    /// Available as a signal for feature-gating UI: true once the dict
    /// has been successfully loaded, false if the bundle was missing the
    /// resources at launch.
    static var isAvailable: Bool { shared != nil }

    /// Walk the raw cut tokens, filter whitespace/punctuation chips, and
    /// re-anchor each surviving token back to its range in `text`. The
    /// walk is linear and only moves the search cursor forward, so we
    /// never mis-match a later occurrence of a repeated word.
    static func tokenize(
        _ text: String
    ) -> [(text: String, range: Range<String.Index>)] {
        guard !text.isEmpty else { return [] }
        let words = rawCut(text)
        var out: [(String, Range<String.Index>)] = []
        var cursor = text.startIndex
        for word in words {
            guard !word.isEmpty else { continue }
            guard let found = text.range(of: word,
                                         options: .literal,
                                         range: cursor..<text.endIndex) else {
                continue
            }
            // Advance even if we filter this one out — otherwise a
            // repeated word later in the text would re-match this slot.
            cursor = found.upperBound
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0)
                                                 || CharacterSet.symbols.contains($0) }) {
                continue
            }
            out.append((word, found))
        }
        return out
    }
}
