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

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AMZNLoginController : UIViewController

@property (strong, nonatomic) IBOutlet UIButton *loginButton;
@property (strong, nonatomic) IBOutlet UITextView *infoField;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *logoutButton;
@property (strong, nonatomic) IBOutlet UINavigationItem *navigationItem;

@property(retain) NSDictionary* userProfile;

- (void)showLogInPage;

- (void)loadSignedInUser;

- (void)checkIsUserSignedIn;
    
@end

NS_ASSUME_NONNULL_END
