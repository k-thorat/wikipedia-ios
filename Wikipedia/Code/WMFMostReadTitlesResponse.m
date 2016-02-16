//
//  WMFMostReadTitlesResponse.m
//  Wikipedia
//
//  Created by Brian Gerstle on 2/11/16.
//  Copyright © 2016 Wikimedia Foundation. All rights reserved.
//

#import "WMFMostReadTitlesResponse.h"
#import "NSDictionary+WMFRequiredValueForKey.h"
#import "Wikipedia-Swift.h"
#import "WMFAssetsFile.h"

#import <Tweaks/FBTweakInline.h>

typedef NS_ENUM (NSUInteger, WMFMostReadTitlesResponseError) {
    WMFMostReadTitlesResponseErrorEmptyItems
};

@implementation WMFMostReadTitlesResponseItemArticle

+ (NSDictionary*)JSONKeyPathsByPropertyKey {
    #define WMFMostReadTitlesResponseItemArticleProperty(k) WMF_SAFE_KEYPATH(WMFMostReadTitlesResponseItemArticle.new, k)
    return @{WMFMostReadTitlesResponseItemArticleProperty(titleText): @"article",
             WMFMostReadTitlesResponseItemArticleProperty(rank): @"rank",
             WMFMostReadTitlesResponseItemArticleProperty(views): @"views"};
}

@end

@implementation WMFMostReadTitlesResponseItem

- (instancetype)initWithDictionary:(NSDictionary*)dictionaryValue error:(NSError* __autoreleasing*)error {
    self = [super initWithDictionary:dictionaryValue error:error];
    if (self) {
        [self sanitizeArticles];
    }
    return self;
}

/**
 *  Remove any articles whose title is a main page or one of the blacklisted titles.
 *
 *  @note This must be called after @c [super initWithDictionary:error:] to ensure the receiver's @c site is already set.
 */
- (void)sanitizeArticles {
    NSArray* titleBlacklist =
#if DEBUG
        /*
           Allow blacklisted titles to be changed "on the fly."  App must be restarted in order to filter results w/ updated
           blacklist.
         */
        [FBTweakValue(@"Explore", @"Most Read", @"Title blacklist", @"-,Test_card,Web_scraping")
         componentsSeparatedByString:@","];
#else
        @[@"-", @"Test_card", @"Web_scraping"];
#endif

    _articles = [_articles bk_reject:^BOOL (WMFMostReadTitlesResponseItemArticle* article) {
        return [titleBlacklist containsObject:article.titleText] || [self isArticleTitleMainPage:article];
    }];
}

- (BOOL)isArticleTitleMainPage:(WMFMostReadTitlesResponseItemArticle*)article {
    WMF_TECH_DEBT_TODO(reset data on memory warning);
    static dispatch_once_t onceToken;
    static NSDictionary* mainPages;
    dispatch_once(&onceToken, ^{
        mainPages = [[[WMFAssetsFile alloc] initWithFileType:WMFAssetsFileTypeMainPages] dictionary];
    });
    return [mainPages[self.site.language] isEqualToString:article.titleText];
}

#pragma mark - MTLJSONSerializing

+ (NSDictionary*)JSONKeyPathsByPropertyKey {
    #define WMFMostReadTitlesResponseItemProperty(k) WMF_SAFE_KEYPATH(WMFMostReadTitlesResponseItem.new, k)
    return @{WMFMostReadTitlesResponseItemProperty(date): @[@"year", @"month", @"day"],
             WMFMostReadTitlesResponseItemProperty(articles): @"articles",
             WMFMostReadTitlesResponseItemProperty(site): @"project"};
}

+ (MTLValueTransformer*)articlesJSONTransformer {
    return [MTLValueTransformer transformerUsingForwardBlock:^id (id value, BOOL* success, NSError* __autoreleasing* error) {
        NSArray<WMFMostReadTitlesResponseItemArticle*>* rawArticles =
            [MTLJSONAdapter modelsOfClass:[WMFMostReadTitlesResponseItemArticle class]
                            fromJSONArray:value
                                    error:error];
        return [[rawArticles sortedArrayUsingSelector:@selector(rank)] wmf_safeSubarrayWithRange:NSMakeRange(0, 50)];
    }];
}

+ (MTLValueTransformer*)dateJSONTransformer {
    return [MTLValueTransformer transformerUsingForwardBlock :^id (NSDictionary* componentsMap,
                                                                   BOOL* outSuccess,
                                                                   NSError* __autoreleasing* outError) {
        NSDateComponents* components = [[NSDateComponents alloc] init];

        BOOL success = YES;
        NSDate* date;

        // DRY up setting specific component, returning nil if an error occurs
        // HAX: for some reason these fields come back as strings, not ints
        #define setComponent(key) \
    do { \
        NSNumber* value = [componentsMap wmf_nonnullValueOfType:[NSString class] forKey:@#key error:outError]; \
        success &= value != nil; \
        components.key = value.intValue; \
    } while (0)

        setComponent(day);
        setComponent(month);
        setComponent(year);

        if (success) {
            components.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
            date = [[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian] dateFromComponents:components];
            if (!date) {
                success = NO;
                DDLogError(@"Failed to serialize date from components %@", components);
            }
        }

        WMFSafeAssign(outSuccess, success);
        return date;
    }];
}

+ (MTLValueTransformer*)siteJSONTransformer {
    return [MTLValueTransformer transformerUsingForwardBlock:^id (NSString* value,
                                                                  BOOL* success,
                                                                  NSError* __autoreleasing* error) {
        NSArray* components = [value componentsSeparatedByString:@"."];
        if (!value.length || components.count < 2) {
            WMFSafeAssign(error,
                          [NSError errorWithDomain:@"WMFMostReadSerializationErrorDomain"
                                              code:0
                                          userInfo:value ? @{@"WMFMostReadFailingProjectUserInfoKey" : value}:nil]);
            return nil;
        }
        return [[MWKSite alloc] initWithDomain:[components[1] stringByAppendingString:@".org"] language:components[0]];
    }];
}

@end

@implementation WMFMostReadTitlesResponse

- (BOOL)validate:(NSError* __autoreleasing*)error {
    if (self.items.count > 0) {
        return YES;
    } else {
        WMFSafeAssign(error, [NSError errorWithDomain:NSStringFromClass([self class])
                                                 code:WMFMostReadTitlesResponseErrorEmptyItems
                                             userInfo:nil]);
        return NO;
    }
}

+ (NSDictionary*)JSONKeyPathsByPropertyKey {
    return @{WMF_SAFE_KEYPATH(WMFMostReadTitlesResponse.new, items): @"items"};
}

+ (NSValueTransformer<MTLTransformerErrorHandling>*)itemsJSONTransformer {
    return [MTLJSONAdapter arrayTransformerWithModelClass:[WMFMostReadTitlesResponseItem class]];
}

@end
