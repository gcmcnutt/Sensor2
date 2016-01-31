/**
 * Copyright 2012-2013 Amazon.com, Inc. or its affiliates. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"). You may not use this file except in compliance with the License. A copy
 * of the License is located at
 *
 * http://aws.amazon.com/apache2.0/
 *
 * or in the "license" file accompanying this file. This file is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
 */

#import <LoginWithAmazon/LoginWithAmazon.h>

#import "AMZNAuthorizeUserDelegate.h"
#import "AMZNGetProfileDelegate.h"

@implementation AMZNAuthorizeUserDelegate

- (id)initWithParentController:(AMZNLoginController*)aViewController {
    if(self = [super init]) {
        parentViewController = [aViewController retain];
    }
    
    return self;
}

#pragma mark Implementation of authorizeUserForScopes:delegate: delegates.
/*
 Delegate method that gets a call when the user authoriation for requested scope succeeds. Define you logic for changing the User interface on being able to recogize the user.
 */
- (void)requestDidSucceed:(APIResult *)apiResult {
    // Your code after the user authorizes Application for requested scopes.
    
    // You can now load new view controller with user identifying information as the user is now successfully signed in or simple get the user profile information if the authorization was for "profile" scope.
    
    AMZNGetProfileDelegate* delegate = [[[AMZNGetProfileDelegate alloc] initWithParentController:parentViewController] autorelease];
    [AIMobileLib getProfile:delegate];
}

/*
 Delegate method that gets a call when the user authoriation for requested scope fails.
 */
- (void)requestDidFail:(APIError *)errorResponse {
    // Your code when the authorization fails.
    
    [[[[UIAlertView alloc] initWithTitle:@"" message:[NSString stringWithFormat:@"User authorization failed with message: %@", errorResponse.error.message] delegate:nil cancelButtonTitle:@"OK"otherButtonTitles:nil] autorelease] show];
}


@end
