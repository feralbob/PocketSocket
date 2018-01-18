//  Copyright 2014-Present Zwopple Limited
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import <XCTest/XCTest.h>
#import "PSAutobahnClientWebSocketOperation.h"

@interface PSAutobahnTestSuite : XCTestCase {
}

@property(nonatomic, strong) NSNumber* caseNumber;
@property(nonatomic, strong) NSDictionary* info;
@property(nonatomic, readonly) NSString* name;

@end

@implementation PSAutobahnTestSuite

+(id)defaultTestSuite {
    XCTestSuite* suite = [[XCTestSuite alloc] initWithName:NSStringFromClass(self)];
    NSLog(@"Fetching test count from server");
    NSUInteger caseCount = [self autobahnFetchTestCaseCount];
    NSLog(@"Found %d tests. Running fetching test info.", caseCount);
    for(NSUInteger i = 1; i <= caseCount; ++i) {
        PSAutobahnTestSuite* test = [[PSAutobahnTestSuite alloc] initWithInvocation:nil caseNumber:@(i)];
        
        SEL selector = @selector(test_autobahn_case_number:);
        NSMethodSignature *signature = [test methodSignatureForSelector:selector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.selector = selector;
        invocation.target = test;
        [invocation setArgument:&i atIndex:2];
        test.invocation = invocation;
        
        NSDictionary *info = [self autobahnFetchTestCaseInfoForNumber:i];
        test.info = info;
        //NSString* name = [test name];
        [suite addTest:test];
    }
    
    // Update reports
    PSAutobahnTestSuite* test = [[PSAutobahnTestSuite alloc] initWithInvocation:nil caseNumber:nil];

    SEL selector = @selector(autobahnUpdateReports);
    NSMethodSignature* signature = [test methodSignatureForSelector:selector];
    NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = selector;
    invocation.target = test;
    test.invocation = invocation;
    [suite addTest:test];
    
    return suite;
}

+ (NSUInteger)autobahnFetchTestCaseCount {
    NSURL *URL = [self.autobahnURL URLByAppendingPathComponent:@"getCaseCount"];
    PSAutobahnClientWebSocketOperation *op = [[PSAutobahnClientWebSocketOperation alloc] initWithURL:URL];
    [self runOperation:op timeout:60.0];
    //XCTAssertNil(op.error, @"Should have successfully returned the number of testCases. Instead got error %@", op.error);
    return [op.message integerValue];
}

+ (NSDictionary *)autobahnFetchTestCaseInfoForNumber:(NSUInteger)number {
    NSString *extra = [NSString stringWithFormat:@"/getCaseInfo?case=%@", @(number)];
    NSURL *URL = [NSURL URLWithString:extra relativeToURL:self.autobahnURL];
    PSAutobahnClientWebSocketOperation *op = [[PSAutobahnClientWebSocketOperation alloc] initWithURL:URL];
    [PSAutobahnTestSuite runOperation:op timeout:60.0];
    //XCTAssertNil(op.error, @"Should have successfully returned the case info. Instead got error %@", op.error);
    NSDictionary *info = [NSJSONSerialization JSONObjectWithData:[op.message dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    //XCTAssertNotNil(info, @"Should have successfully deserialized message into dictionary.");
    return info;
}

+ (void)runOperation:(NSOperation *)operation timeout:(NSTimeInterval)timeout {
    static NSOperationQueue *queue = nil;
    static dispatch_once_t once = 0;
    dispatch_once(&once, ^{
        queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
    });
    
    
    NSCondition *condition = [[NSCondition alloc] init];
    [condition lock];
    NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:^{
        [condition lock];
        [condition signal];
        [condition unlock];
    }];
    [op addDependency:operation];
    [queue addOperation:operation];
    [queue addOperation:op];
    [condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:timeout]];
    [condition unlock];
}

+ (NSURL *)autobahnURL {
    return [NSURL URLWithString:@"ws://localhost:9001/"];
}

+ (NSString *)agent {
    return @"com.zwopple.PSWebSocket";
}

-(instancetype)initWithInvocation:(NSInvocation*)invocation caseNumber:(NSNumber*)caseNumber {
    if(self = [super initWithInvocation:invocation]) {
        self.caseNumber = caseNumber;
    }
    
    return self;
}

#pragma mark - Autobahn Operations

- (NSDictionary *)test_autobahn_case_number:(NSUInteger)number {
    NSString *extra = [NSString stringWithFormat:@"/runCase?case=%@&agent=%@", @(number), [PSAutobahnTestSuite agent]];
    NSURL *URL = [NSURL URLWithString:extra relativeToURL:[PSAutobahnTestSuite autobahnURL]];
    PSAutobahnClientWebSocketOperation *op = [[PSAutobahnClientWebSocketOperation alloc] initWithURL:URL];
    op.echo = YES;
    [PSAutobahnTestSuite runOperation:op timeout:60.0];
    XCTAssertNil(op.error, @"Should have successfully run the test case. Instead got error %@", op.error);
    NSDictionary* results = [self autobahnFetchTestCaseStatusForNumber:number];
    XCTAssertEqualObjects(@"OK", results[@"behavior"], @"Test behavior should have been ok, instead got: %@", results[@"behavior"]);
}

- (NSDictionary *)autobahnFetchTestCaseStatusForNumber:(NSUInteger)number {
    NSString *extra = [NSString stringWithFormat:@"/getCaseStatus?case=%@&agent=%@", @(number),  [PSAutobahnTestSuite agent]];
    NSURL *URL = [NSURL URLWithString:extra relativeToURL:[PSAutobahnTestSuite autobahnURL]];
    PSAutobahnClientWebSocketOperation *op = [[PSAutobahnClientWebSocketOperation alloc] initWithURL:URL];
    [PSAutobahnTestSuite runOperation:op timeout:60.0];
    XCTAssertNil(op.error, @"Should have successfully returned the case status. Instead got error %@", op.error);
    NSDictionary *info = [NSJSONSerialization JSONObjectWithData:[op.message dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    XCTAssertNotNil(info, @"Should have successfully deserialized message into dictionary.");
    return info;
}

- (void)autobahnUpdateReports {
    NSString *extra = [NSString stringWithFormat:@"/updateReports?agent=%@",  [PSAutobahnTestSuite agent]];
    NSURL *URL = [NSURL URLWithString:extra relativeToURL:[PSAutobahnTestSuite autobahnURL]];
    PSAutobahnClientWebSocketOperation *op = [[PSAutobahnClientWebSocketOperation alloc] initWithURL:URL];
    [PSAutobahnTestSuite runOperation:op timeout:60.0];
    XCTAssertNil(op.error, @"Should have successfully updated the reports. Instead got error %@", op.error);
}

- (NSInvocation*)invocation {
    return [super invocation];
}

- (NSString*)languageAgnosticTestMethodName {
    NSString* desc = [NSString stringWithFormat:@"%@ - %@", self.info[@"id"], self.info[@"description"]];
    return desc;
}

- (NSString*)name {
    NSString* desc = [super name];
    //NSString *desc = [NSString stringWithFormat:@"%@ – %@", self.info[@"id"], self.info[@"description"]];
    desc = [NSString stringWithFormat:@"%@ - %@", self.info[@"id"], self.info[@"description"]];
    return desc;
}

@end


