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

#import "AMZNLoginController.h"
#import "AMZNGetAccessTokenDelegate.h"
#import "AMZNGetProfileDelegate.h"
#import "AMZNAuthorizeUserDelegate.h"
#import "AMZNLogoutDelegate.h"

@implementation AMZNLoginController

@synthesize userProfile, navigationItem, logoutButton, loginButton, infoField;

NSString* userLoggedOutMessage = @"Welcome to Login with Amazon!\nIf this is your first time logging in, you will be asked to give permission for this application to access your profile data.";
NSString* userLoggedInMessage = @"Welcome, %@ \n Your email is %@.";
BOOL isUserSignedIn;

- (IBAction)onLogInButtonClicked:(id)sender {
    // Make authorize call to SDK to get authorization from the user. While making the call you can specify the scopes for which the user authorization is needed.
    
    // Requesting 'profile' scopes for the current user.
    NSArray *requestScopes = [NSArray arrayWithObject:@"profile"];
    
    AMZNAuthorizeUserDelegate* delegate = [[AMZNAuthorizeUserDelegate alloc] initWithParentController:self];
    
    [AIMobileLib authorizeUserForScopes:requestScopes delegate:delegate];
}

- (IBAction)logoutButtonClicked:(id)sender {
    AMZNLogoutDelegate* delegate = [[[AMZNLogoutDelegate alloc] initWithParentController:self] autorelease];
    
    [AIMobileLib clearAuthorizationState:delegate];
}

- (BOOL)shouldAutorotate {
    return NO;
}

#pragma mark View controller specific functions
- (void)checkIsUserSignedIn {
    AMZNGetAccessTokenDelegate* delegate = [[[AMZNGetAccessTokenDelegate alloc] initWithParentController:self] autorelease];
    [AIMobileLib getAccessTokenForScopes:[NSArray arrayWithObject:@"profile"] withOverrideParams:nil delegate:delegate];
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

- (void)dealloc {
    self.navigationItem = nil;
    self.infoField = nil;
    self.loginButton = nil;
    self.logoutButton = nil;
    self.userProfile = nil;
    
    [super dealloc];
}

@end
