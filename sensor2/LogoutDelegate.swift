//
//  LogoutDelegate.swift
//  Watch
//
//  Created by Greg McNutt on 6/7/15.
//  Copyright (c) 2015 Greg McNutt. All rights reserved.
//

import Foundation
import UIKit

class LogoutDelegate: NSObject, AIAuthenticationDelegate {
    let parentController: ViewController
    
    init(parentController: ViewController) {
        self.parentController = parentController
    }
    
    @objc func requestDidSucceed(apiResult: APIResult!) {
        // Your additional logic after the user authorization state is cleared.
                
        let alertController = UIAlertController(title: "",
            message: "User Logged out.",
            preferredStyle: .Alert)
        let defaultAction = UIAlertAction(title: "OK", style: .Default, handler: nil)
        alertController.addAction(defaultAction)
        
        parentController.presentViewController(alertController, animated: true, completion: nil)
    }
    
    @objc func requestDidFail(errorResponse: APIError) {
        let alertController = UIAlertController(title: "",
            message: "Logout:" + errorResponse.error.message,
            preferredStyle: .Alert)
        let defaultAction = UIAlertAction(title: "OK", style: .Default, handler: nil)
        alertController.addAction(defaultAction)
        
        parentController.presentViewController(alertController, animated: true, completion: nil)
    }
}