#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin ObjC wrapper around `cppjieba::Jieba`. Construction loads ~10 MB
/// of dictionaries off disk, so keep a single long-lived instance (see
/// `JiebaSegmenter` on the Swift side). `cutText:` is thread-safe and
/// cheap enough to call on the main thread for sentence-length inputs.
@interface JiebaBridge : NSObject

/// Build a Jieba instance from on-disk dictionaries. All five files are
/// required — pass the paths obtained from `Bundle.main.path(forResource:
/// ofType:)` against the `jieba-dict/*.utf8` resources we ship.
- (instancetype)initWithDictPath:(NSString *)dict
                         hmmPath:(NSString *)hmm
                        userDict:(NSString *)userDict
                         idfPath:(NSString *)idf
                   stopWordsPath:(NSString *)stopWords;

/// Segment `text` into words using Jieba's MixSegment (precision-mode +
/// HMM for OOV discovery). Returns substrings in reading order; whitespace
/// characters pass through as their own tokens — the Swift side filters
/// them. Empty input returns an empty array.
- (NSArray<NSString *> *)cutText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
