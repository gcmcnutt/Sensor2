/**
 * Copyright 2012-2015 Amazon.com, Inc. or its affiliates. All rights reserved.
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

#import "AMZNLoginController.h"

@implementation AMZNLoginController

@synthesize userProfile, navigationItem, logoutButton, loginButton, infoField;

NSString* userLoggedOutMessage = @"Welcome to Login with Amazon!\nIf this is your first time logging in, you will be asked to give permission for this application to access your profile data.";
NSString* userLoggedInMessage = @"Welcome, %@ \n Your email is %@.";
BOOL isUserSignedIn;

- (IBAction)onLogInButtonClicked:(id)sender {
    // Make authorize call to SDK to get authorization from the user. While making the call you can specify the scopes for which the user authorization is needed.
    
    // Build an authorize request.
    AMZNAuthorizeRequest *request = [[AMZNAuthorizeRequest alloc] init];
    
    // Requesting 'profile' scopes for the current user.
    request.scopes = [NSArray arrayWithObject:[AMZNProfileScope profile]];
    
    // Make an Authorize call to the Login with Amazon SDK.
    [[AMZNAuthorizationManager sharedManager] authorize:request
                                            withHandler:[self requestHandler]];
}

- (IBAction)logoutButtonClicked:(id)sender {
    [[AMZNAuthorizationManager sharedManager] signOut:^(NSError * _Nullable error) {
        // Your additional logic after the user authorization state is cleared.

        [self showLogInPage];
    }];
}

- (BOOL)shouldAutorotate {
    return NO;
}

#pragma mark View controller specific functions
- (void)checkIsUserSignedIn {
    // Make authorize call to SDK using AMZNInteractiveStrategyNever to detect whether there is an authenticated user. While making this call you can specify scopes for which user authorization is needed. If this call returns error, it means either there is no authenticated user, or at least of the requested scopes are not authorized. In both case you should show sign in page again.
    
    // Build an authorize request.
    AMZNAuthorizeRequest *request = [[AMZNAuthorizeRequest alloc] init];
    
    // Requesting 'profile' scopes for the current user.
    request.scopes = [NSArray arrayWithObject:[AMZNProfileScope profile]];
    
    // Set interactive strategy as 'AMZNInteractiveStrategyNever'.
    request.interactiveStrategy = AMZNInteractiveStrategyNever;
    
    [[AMZNAuthorizationManager sharedManager] authorize:request
                                            withHandler:[self requestHandler]];
}

- (AMZNAuthorizationRequestHandler)requestHandler
{
    AMZNAuthorizationRequestHandler requestHandler = ^(AMZNAuthorizeResult * result, BOOL userDidCancel, NSError * error) {
        if (error) {
            // If error code = kAIApplicationNotAuthorized, allow user to log in again.
            if(error.code == kAIApplicationNotAuthorized) {
                // Show authorize user button.
                [self showLogInPage];
            } else {
                // Handle other errors
                NSString *errorMessage = error.userInfo[@"AMZNLWAErrorNonLocalizedDescription"];
                [[[[UIAlertView alloc] initWithTitle:@"" message:[NSString stringWithFormat:@"Error occured with message: %@", errorMessage] delegate:nil cancelButtonTitle:@"OK"otherButtonTitles:nil] autorelease] show];
            }
        } else if (userDidCancel) {
            // Your code to handle user cancel scenario.
            
        } else {
            // Authentication was successful. Obtain the user profile data.
            AMZNUser *user = result.user;
            self.userProfile = user.profileData;
            [self loadSignedInUser];
        }
    };
    
    return [requestHandler copy];
}

- (void)loadSignedInUser {
    isUserSignedIn = true;
    self.loginButton.hidden = true;
    self.navigationItem.rightBarButtonItem = self.logoutButton;
    self.infoField.text = [NSString stringWithFormat:@"Welcome, %@ \n Your email is %@.", [userProfile objectForKey:@"name"], [userProfile objectForKey:@"email"]];
    self.infoField.hidden = false;
}

- (void)showLogInPage {
    isUserSignedIn = false;
    self.loginButton.hidden = false;
    self.navigationItem.rightBarButtonItem = nil;
    self.infoField.text = userLoggedOutMessage;
    self.infoField.hidden = false;
}

- (void)viewDidLoad {
    if (isUserSignedIn)
        [self loadSignedInUser];
    else
        [self showLogInPage];
    float systemVersion=[[[UIDevice currentDevice] systemVersion] floatValue];
    if(systemVersion>=7.0f)
    {
        CGRect tempRect;
        for(UIView *sub in [[self view] subviews])
        {
            tempRect = [sub frame];
            tempRect.origin.y += 20.0f; //Height of status bar
            [sub setFrame:tempRect];
        }
    }
}

@end
