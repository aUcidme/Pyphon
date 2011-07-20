//
//  Runtime.m
//  Pyphon
//
//  Created by Stefan Matthias Aust on 16.01.11.
//  Copyright 2011 I.C.N.H. All rights reserved.
//

#import "Runtime.h"
#import "AST.h" // resolve forward declaration


#pragma mark Runtime object


@implementation Pyphon

@synthesize delegate;

+ (Pyphon *)sharedInstance {
    static Pyphon *instance;
    if (!instance) {
        instance = [[Pyphon alloc] init];
    }
    return instance;
}

+ (NSObject *)True {
    static NSObject *True = nil;
    if (!True) {
        True = [[NSNumber alloc] initWithBool:YES];
    }
    return True;
}

+ (NSObject *)False {
    static NSObject *False = nil;
    if (!False) {
        False = [[NSNumber alloc] initWithBool:NO];
    }
    return False;
}

+ (NSObject *)None {
    static NSObject *None = nil;
    if (!None) {
        None = [NSNull null];
    }
    return None;
}

- (id)init {
    if ((self = [super init])) {
        self->builtins = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                          [Pyphon None], @"None",
                          [Pyphon True], @"True", 
                          [Pyphon False], @"False",
                          [BuiltinFunction functionWithSelector:@selector(print:)], @"print",
                          [BuiltinFunction functionWithSelector:@selector(len:)], @"len",
                          nil];
    }
    return self;
}


- (Frame *)newInitialFrame {
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    
	[dict setObject:builtins forKey:@"__builtins__"];
    
    Frame *initialFrame = [[Frame alloc] initWithLocals:dict globals:dict pyphon:self];

    
    return initialFrame;
}

@end


#pragma mark -
#pragma mark Frame object


@implementation Frame

@synthesize locals;
@synthesize globals;
@synthesize pyphon;
@synthesize resultType;
@synthesize arguments;

- (Frame *)initWithLocals:(NSMutableDictionary *)locals_ 
                  globals:(NSMutableDictionary *)globals_
                   pyphon:(Pyphon *)pyphon_ {
	if ((self = [self init])) {
		locals = locals_;
		globals = globals_;
        pyphon = pyphon_;
	}
	return self;
}


- (NSObject *)localValueForName:(NSString *)name {
	return [locals objectForKey:name];
}

- (void)setLocalValue:(NSObject *)value forName:(NSString *)name {
	[locals setObject:value forKey:name];
}

- (NSObject *)globalValueForName:(NSString *)name {
	NSObject *value = [globals objectForKey:name];
	if (!value) {
		value = [globals objectForKey:@"__builtins__"];
		value = [(NSDictionary *)value objectForKey:name];
    }
	return value;
}
	
- (void)setGlobalValue:(NSObject *)value forName:(NSString *)name {
	[globals setObject:value forKey:name];
}

- (Value *)typeError:(NSString *)message {
    self.resultType = kException;
    return [@"TypeError: " stringByAppendingString:message];
}

- (Value *)raise:(NSString *)exception {
    self.resultType = kException;
    return exception;
}

@end


#pragma mark -
#pragma mark Function objects


@implementation Function

+ (Function *)withName:(NSString *)name 
                params:(NSArray *)params 
              defaults:(NSArray *)defaults
                 suite:(Suite *)suite 
               globals:(NSMutableDictionary *)globals {
	Function *function = [[self alloc] init];
	if (function) {
		function->name = [name copy];
		function->params = [params copy];
        function->defaults = [defaults copy];
		function->suite = suite;
		function->globals = globals;
	}
	return function;
}


- (Value *)call:(Frame *)frame {
    NSUInteger acount = [frame.arguments count];
    NSUInteger pcount = [params count];
    NSUInteger dcount = [defaults count];
    
    if (acount > pcount || acount < pcount - dcount) {
        return [frame typeError:@"wrong number of arguments"];
    }
    
	NSMutableDictionary *locals = [[NSMutableDictionary alloc] initWithCapacity:pcount];
	
    for (NSUInteger i = 0; i < acount; i++) {
		[locals setObject:[frame.arguments objectAtIndex:i] forKey:[params objectAtIndex:i]];
	}
    for (NSUInteger i = acount; i < pcount; i++) {
        [locals setObject:[defaults objectAtIndex:i + dcount - pcount] forKey:[params objectAtIndex:i]];
    }
    
    frame.arguments = nil;
    
    Frame *newFrame = [[Frame alloc] initWithLocals:locals globals:globals pyphon:frame.pyphon];
    
    
    Value *result = [(Suite *)suite evaluate:newFrame];
    if (newFrame.resultType) {
        if (newFrame.resultType == kReturn) {
            newFrame.resultType = kValue;
        }
        if (newFrame.resultType == kBreak) {
            result = [newFrame raise:@"SyntaxError: 'break' outside loop"];
        }
    }
    
    frame.resultType = newFrame.resultType;
    

    return result;
}

@end


@implementation BuiltinFunction

+ (BuiltinFunction *)functionWithSelector:(SEL)selector {
	BuiltinFunction *bf = [[self alloc] init];
	if (bf) {
		bf->selector = selector;
	}
	return bf;
}

- (Value *)call:(Frame *)frame {
	Value *result = [self performSelector:selector withObject:frame];
    frame.arguments = nil;
    return result;
}

- (Value *)print:(Frame *)frame {
    if ([frame.arguments count] != 1) {
        return [frame typeError:@"print(): wrong number of arguments"];
    }

    NSMutableString *buffer = [[NSMutableString alloc] init];
    
    BOOL first = YES;
    for (NSObject *argument in frame.arguments) {
        if (first) {
            first = NO;
        } else {
            [buffer appendString:@" "];
        }
        [buffer appendString:[argument __str__]];
    }
	[frame.pyphon.delegate print:buffer];
    
    
	return nil;
}

- (Value *)len:(Frame *)frame {
    if ([frame.arguments count] != 1) {
        return [frame typeError:@"len(): wrong number of arguments"];
    }
    
    Value *arg = [frame.arguments objectAtIndex:0];
    
    if ([arg isKindOfClass:[NSString class]]) {
        return [NSNumber numberWithInteger:[(NSString *)arg length]];
    }
    if ([arg respondsToSelector:@selector(count)]) {
        return [NSNumber numberWithInteger:[(NSArray *)arg count]];
    }
    
    return [frame typeError:@"object has no len()"];
}

@end


@implementation BuiltinMethod

+ (BuiltinMethod *)methodWithSelector:(SEL)selector receiver:(Value *)receiver {
    BuiltinMethod *method = [[self alloc] init];
    if (method) {
        method->selector = selector;
        method->receiver = receiver;
    }
    return method;
}

- (Value *)append:(Frame *)frame {
    if ([frame.arguments count] != 1) {
        return [frame typeError:@"append(): wrong number of arguments"];
    }
    
    [(NSMutableArray *)receiver addObject:[frame.arguments objectAtIndex:0]];
    
    return nil;
}

@end


#pragma mark -
#pragma mark Foundation class extensions


@implementation NSObject (Pyphon)

- (NSString *)__repr__ {
    return [self description];
}

- (NSString *)__str__ {
    return [self __repr__];
}

@end


@implementation NSString (Pyphon)

- (NSString *)__repr__ {
    NSString *singleQuote = @"\'";
    NSString *doubleQuote = @"\"";
    
    BOOL useDoubleQuote = [self rangeOfString:singleQuote].location != NSNotFound
        && [self rangeOfString:doubleQuote].location == NSNotFound;
    NSString *quote = useDoubleQuote ? doubleQuote : singleQuote;
    
    NSString *string = self;
    string = [string stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    string = [string stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    if (!useDoubleQuote) {
        string = [string stringByReplacingOccurrencesOfString:singleQuote withString:@"\\'"];
    }
    return [NSString stringWithFormat:@"%@%@%@", quote, string, quote];
}

- (NSString *)__str__ {
    return self;
}

@end


@implementation NSArray (Pyphon)

- (NSString *)__repr__ {
    NSMutableString *buffer = [NSMutableString string];
    [buffer appendString:@"("];
    BOOL first = YES;
    for (NSObject *value in self) {
        if (first) {
            first = NO;
        } else {
            [buffer appendString:@", "];
        }
        [buffer appendString:[value __repr__]];
    }
    if ([self count] == 1) {
        [buffer appendString:@","];
    }
    [buffer appendString:@")"];
    return buffer;
}

@end


@implementation NSMutableArray (Pyphon)

- (NSString *)__repr__ {
    NSMutableString *buffer = [NSMutableString string];
    [buffer appendString:@"["];
    BOOL first = YES;
    for (NSObject *value in self) {
        if (first) {
            first = NO;
        } else {
            [buffer appendString:@", "];
        }
        [buffer appendString:[value __repr__]];
    }
    [buffer appendString:@"]"];
    return buffer;
}

@end


@implementation NSMutableSet (Pyphon)

- (NSString *)__repr__ {
    if (![self count]) {
        return @"set()";
    }
    NSMutableString *buffer = [NSMutableString string];
    [buffer appendString:@"{"];
    BOOL first = YES;
    for (NSObject *value in self) {
        if (first) {
            first = NO;
        } else {
            [buffer appendString:@", "];
        }
        [buffer appendString:[value __repr__]];
    }
    [buffer appendString:@"}"];
    return buffer;
}

@end


@implementation NSMutableDictionary (Pyphon)

- (NSString *)__repr__ {
    NSMutableString *buffer = [NSMutableString string];
    [buffer appendString:@"{"];
    BOOL first = YES;
    for (NSObject *key in self) {
        if (first) {
            first = NO;
        } else {
            [buffer appendString:@", "];
        }
        [buffer appendString:[key __repr__]];
        [buffer appendString:@": "];
        [buffer appendString:[[self objectForKey:key] __repr__]];
    }
    [buffer appendString:@"}"];
    return buffer;
}

@end


@implementation NSNull (Pyphon)

- (NSString *)__repr__ {
    return @"None";
}

@end
