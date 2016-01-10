//
//  AuthorizeUserDelegate.swift
//  Watch
//
//  Created by Greg McNutt on 6/6/15.
//  Copyright (c) 2015 Greg McNutt. All rights reserved.
//

import Foundation
import UIKit

class AuthorizeUserDelegate: NSObject, AIAuthenticationDelegate {
    let parentController: ViewController
    
    init(parentController: ViewController) {
        self.parentController = parentController
    }
    
    @objc func requestDidSucceed(apiResult: APIResult!) {
        launchGetAccessToken()
    }
    
    @objc func requestDidFail(errorResponse: APIError) {
        let alertController = UIAlertController(title: "",
            message: "AuthorizeUser:" + errorResponse.error.message,
            preferredStyle: .Alert)
        let defaultAction = UIAlertAction(title: "OK", style: .Default, handler: nil)
        alertController.addAction(defaultAction)
        
        parentController.presentViewController(alertController, animated: true, completion: nil)
    }
    
    func launchGetAccessToken() {
        // initialize the token system
        let delegate = AccessTokenDelegate(parentController: parentController)
        let requestScopes: [String] = ["profile", "postal_code"]
        AIMobileLib.getAccessTokenForScopes(requestScopes, withOverrideParams: nil, delegate: delegate)
    }
}
