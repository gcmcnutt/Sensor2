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

#import "AMZNLogoutDelegate.h"

@implementation AMZNLogoutDelegate

- (id)initWithParentController:(AMZNLoginController*)aViewController {
    if(self = [super init]) {
        parentViewController = [aViewController retain];
    }
    
    return self;
}

#pragma mark Implementation of clearAuthorizationState: delegates.
/*
 This delegate method that gets a call when the user's authorization state is cleared successfully. Define your functionality to update the UI to reflect the logout state of the user.
 */
- (void)requestDidFail:(APIError *)errorResponse {
    // Your additional logic after the SDK failed to clear the authorization state.
    
    [[[[UIAlertView alloc] initWithTitle:@"" message:[NSString stringWithFormat:@"User Logout failed with message: %@", errorResponse.error.message] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];
}

/*
 This delegate method that gets a call when the SDK fails to clear the authorization state of the user. Show user the failure message and let user to retry.
 */
- (void)requestDidSucceed:(APIResult *)apiResult {
    // Your additional logic after the user authorization state is cleared.
    
    [parentViewController showLogInPage];
}

- (void)dealloc {
    [parentViewController release];
    [super dealloc];
}
@end