//
//    Copyright (c) 2016 Joel Milne
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy of
//    this software and associated documentation files (the "Software"), to deal in
//    the Software without restriction, including without limitation the rights to
//    use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
//    the Software, and to permit persons to whom the Software is furnished to do so,
//    subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//    FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//    COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//    IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


#import "JMPPUtils.h"
#import <UIKit/UIKit.h>

@implementation JMPPUtils

+ (void)logDebug:(NSString *)format, ...;
{
#ifdef DEBUG
    va_list args;
    va_start(args, format);
    NSString *str = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"%@", str);
#endif
}

+ (NSDictionary*)parseURLParams:(NSString *)query
{
    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    for (NSString *pair in pairs) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        NSString *val = [[kv objectAtIndex:1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        [params setObject:val forKey:[kv objectAtIndex:0]];
    }
    return params;
}

+ (void)showAlert:(NSString *)msg
{
    //need to run UI on the main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^ { [JMPPUtils showAlert:msg]; });
        return;
    }

    if (!msg) msg = @" ";
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"" message:msg delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [alertView show];
}

@end
