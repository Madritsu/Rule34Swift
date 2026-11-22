//
//  R34DataParser.m
//  Rule34Swift Optimizer
//
//  Fast tag parsing, HTML entity decoding, and JSON extraction.
//

#import "../Headers/R34Optimizations.h"

@implementation R34DataParser

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)parseTags:(NSString *)rawTags {
    if (!rawTags || rawTags.length == 0) return @{};

    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    NSArray *tags = [rawTags componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    for (NSString *tag in tags) {
        NSString *trimmed = [tag stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0) continue;

        NSString *category = @"general";
        NSString *tagName = trimmed;

        // Check for category prefix
        NSString *lower = [trimmed lowercaseString];
        if ([lower hasPrefix:@"general:"]) {
            category = @"general";
            tagName = [trimmed substringFromIndex:8];
        } else if ([lower hasPrefix:@"artist:"]) {
            category = @"artist";
            tagName = [trimmed substringFromIndex:7];
        } else if ([lower hasPrefix:@"copyright:"]) {
            category = @"copyright";
            tagName = [trimmed substringFromIndex:10];
        } else if ([lower hasPrefix:@"character:"]) {
            category = @"character";
            tagName = [trimmed substringFromIndex:10];
        } else if ([lower hasPrefix:@"species:"]) {
            category = @"species";
            tagName = [trimmed substringFromIndex:8];
        } else if ([lower hasPrefix:@"meta:"]) {
            category = @"meta";
            tagName = [trimmed substringFromIndex:5];
        } else if ([lower hasPrefix:@"lore:"]) {
            category = @"lore";
            tagName = [trimmed substringFromIndex:5];
        }

        if (tagName.length == 0) continue;

        NSMutableArray *existing = result[category];
        if (!existing) {
            existing = [NSMutableArray array];
            result[category] = existing;
        }
        [existing addObject:tagName];
    }

    return [result copy];
}

+ (NSString *)decodeHTMLEntities:(NSString *)string {
    if (!string || string.length == 0) return string;

    NSMutableString *result = [NSMutableString stringWithString:string];

    NSDictionary *entities = @{
        @"&amp;": @"&",
        @"&lt;": @"<",
        @"&gt;": @">",
        @"&quot;": @"\"",
        @"&#39;": @"'",
        @"&apos;": @"'",
        @"&#x27;": @"'",
        @"&#x2F;": @"/",
        @"&nbsp;": @" ",
    };

    for (NSString *entityKey in entities) {
        [result replaceOccurrencesOfString:entityKey
                               withString:entities[entityKey]
                                  options:NSLiteralSearch
                                    range:NSMakeRange(0, result.length)];
    }

    // Decode numeric hex entities: &#x1A;
    NSError *hexError = nil;
    NSRegularExpression *numEntityRegex = [NSRegularExpression regularExpressionWithPattern:@"&#x([0-9a-fA-F]+);"
                                                                                   options:0
                                                                                     error:&hexError];
    if (numEntityRegex) {
        NSArray *hexMatches = [numEntityRegex matchesInString:result options:0 range:NSMakeRange(0, result.length)];
        for (NSTextCheckingResult *match in [hexMatches reverseObjectEnumerator]) {
            NSString *hex = [result substringWithRange:[match rangeAtIndex:1]];
            unsigned int codepoint = 0;
            NSScanner *scanner = [NSScanner scannerWithString:hex];
            [scanner scanHexInt:&codepoint];
            NSString *replacement;
            if (codepoint < 128) {
                replacement = [NSString stringWithFormat:@"%c", (char)codepoint];
            } else {
                unichar ch = (unichar)codepoint;
                replacement = [NSString stringWithCharacters:&ch length:1];
            }
            [result replaceCharactersInRange:match.range withString:replacement];
        }
    }

    // Decode numeric decimal entities: &#123;
    NSError *decError = nil;
    NSRegularExpression *decEntityRegex = [NSRegularExpression regularExpressionWithPattern:@"&#(\\d+);"
                                                                                   options:0
                                                                                     error:&decError];
    if (decEntityRegex) {
        NSArray *decMatches = [decEntityRegex matchesInString:result options:0 range:NSMakeRange(0, result.length)];
        for (NSTextCheckingResult *match in [decMatches reverseObjectEnumerator]) {
            NSString *dec = [result substringWithRange:[match rangeAtIndex:1]];
            unsigned int codepoint = [dec intValue];
            NSString *replacement;
            if (codepoint < 128) {
                replacement = [NSString stringWithFormat:@"%c", (char)codepoint];
            } else {
                unichar ch = (unichar)codepoint;
                replacement = [NSString stringWithCharacters:&ch length:1];
            }
            [result replaceCharactersInRange:match.range withString:replacement];
        }
    }

    return [result copy];
}

+ (NSArray<NSString *> *)extractPostIDsFromJSON:(NSData *)jsonData {
    if (!jsonData || jsonData.length == 0) return @[];

    NSError *error = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (error || !parsed) return @[];

    NSMutableArray *ids = [NSMutableArray array];

    if ([parsed isKindOfClass:[NSArray class]]) {
        for (id item in parsed) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                id idValue = item[@"id"];
                if ([idValue isKindOfClass:[NSString class]] && [idValue length] > 0) {
                    [ids addObject:idValue];
                } else if ([idValue isKindOfClass:[NSNumber class]]) {
                    [ids addObject:[idValue stringValue]];
                }
            }
        }
    }

    return [ids copy];
}

@end
