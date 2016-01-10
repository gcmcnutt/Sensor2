//
//  GetProfileDelegate.swift
//  Watch
//
//  Created by Greg McNutt on 6/6/15.
//  Copyright (c) 2015 Greg McNutt. All rights reserved.
//

import Foundation
import UIKit

class GetProfileDelegate: NSObject, AIAuthenticationDelegate {
    let parentController: ViewController
    
    init(parentController: ViewController) {
        self.parentController = parentController
    }
    
    @objc func requestDidSucceed(apiResult: APIResult!) {
        // Get profile request succeded. Unpack the profile information
        // and pass it to the parent view controller
        
        let dict = apiResult.result as! NSDictionary
        parentController.updateLoginState(
            dict.valueForKey("name") as! String,
            email: dict.valueForKey("email") as! String,
            userId: dict.valueForKey("user_id") as! String,
            postal: dict.valueForKey("postal_code") as! String)
    }
    
    @objc func requestDidFail(errorResponse: APIError) {
        // Get Profile request failed for profile scope.
    
        // If error code = kAIApplicationNotAuthorized,
        // allow user to log in again.
        if (errorResponse.error.code == kAIApplicationNotAuthorized) {
            // Show authorize user button.
            //parentController.showLoginPage()
        }
        else {
            // Handle other errors
            let alertController = UIAlertController(title: "",
                message: "GetProfile:" + errorResponse.error.message,
                preferredStyle: .Alert)
            
            let defaultAction = UIAlertAction(title: "OK", style: .Default, handler: nil)
            alertController.addAction(defaultAction)
            
            parentController.presentViewController(alertController, animated: true, completion: nil)
        }
    }
}