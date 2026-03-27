/**
 * This file is generated using the remodel generation script.
 * The name of the input file is IPFTestRunnerConfiguration.value
 */

#import <Foundation/Foundation.h>
#import "IPFTestRunnerConfigurationType.h"

@interface IPFTestRunnerConfiguration : NSObject <NSCopying>

@property (nonatomic, readonly, copy) NSString *hostname;
@property (nonatomic, readonly) NSUInteger port;
@property (nonatomic, readonly) NSUInteger duration;
@property (nonatomic, readonly) NSUInteger streams;
@property (nonatomic, readonly) IPFTestRunnerConfigurationType type;
@property (nonatomic, readonly) BOOL useUDP;
@property (nonatomic, readonly) NSUInteger udpBandwidth;

- (instancetype)initWithHostname:(NSString *)hostname port:(NSUInteger)port duration:(NSUInteger)duration streams:(NSUInteger)streams type:(IPFTestRunnerConfigurationType)type useUDP:(BOOL)useUDP udpBandwidth:(NSUInteger)udpBandwidth;

@end
