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

#import "AMZNGetAccessTokenDelegate.h"
#import "AMZNGetProfileDelegate.h"

@implementation AMZNGetAccessTokenDelegate

- (id)initWithParentController:(AMZNLoginController*)aViewController {
    if(self = [super init]) {
        parentViewController = [aViewController retain];
    }
    
    return self;
}

#pragma mark Implementation of getAccessTokenForScopes:withOverrideParams:delegate: delegates.
- (void)requestDidSucceed:(APIResult *)apiResult {
    // Your code to use access token goes here.

    // Since the application has authorization for "profile" scope, we can get the user profile.
    AMZNGetProfileDelegate* delegate = [[[AMZNGetProfileDelegate alloc] initWithParentController:parentViewController] autorelease];
    
    [AIMobileLib getProfile:delegate];
}

- (void)requestDidFail:(APIError *)errorResponse {
    // Your code to handle failed retrieval of access token.
    
    // If error code = kAIApplicationNotAuthorized, allow user to log in again.
    if(errorResponse.error.code == kAIApplicationNotAuthorized) {
        // Show authorize user button.
        [parentViewController showLogInPage];
    }
    else {
        // Handle other errors
        [[[[UIAlertView alloc] initWithTitle:@"" message:[NSString stringWithFormat:@"Error occured with message: %@", errorResponse.error.message] delegate:nil cancelButtonTitle:@"OK"otherButtonTitles:nil] autorelease] show];
    }
}

- (void)dealloc {
    [parentViewController release];
    [super dealloc];
}

@end
