#import "JiebaBridge.h"
#include "cppjieba/Jieba.hpp"
#include <string>
#include <vector>
#include <memory>

@implementation JiebaBridge {
    std::unique_ptr<cppjieba::Jieba> _jieba;
}

- (instancetype)initWithDictPath:(NSString *)dict
                         hmmPath:(NSString *)hmm
                        userDict:(NSString *)userDict
                         idfPath:(NSString *)idf
                   stopWordsPath:(NSString *)stopWords {
    if ((self = [super init])) {
        try {
            _jieba.reset(new cppjieba::Jieba(
                std::string(dict.UTF8String),
                std::string(hmm.UTF8String),
                std::string(userDict.UTF8String),
                std::string(idf.UTF8String),
                std::string(stopWords.UTF8String)
            ));
        } catch (const std::exception &e) {
            NSLog(@"[Jieba] init failed: %s", e.what());
            return nil;
        } catch (...) {
            NSLog(@"[Jieba] init failed: unknown exception");
            return nil;
        }
    }
    return self;
}

- (NSArray<NSString *> *)cutText:(NSString *)text {
    if (text.length == 0 || _jieba == nullptr) {
        return @[];
    }
    std::string input(text.UTF8String ?: "");
    std::vector<std::string> words;
    try {
        _jieba->Cut(input, words, true /* HMM */);
    } catch (...) {
        return @[];
    }
    NSMutableArray<NSString *> *out = [NSMutableArray arrayWithCapacity:words.size()];
    for (const auto &w : words) {
        NSString *s = [NSString stringWithUTF8String:w.c_str()];
        if (s != nil) {
            [out addObject:s];
        }
    }
    return out;
}

@end
