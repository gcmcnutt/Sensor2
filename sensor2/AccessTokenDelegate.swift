//
//  AccessTokenDelegate.swift
//  Watch
//
//  Created by Greg McNutt on 6/7/15.
//  Copyright (c) 2015 Greg McNutt. All rights reserved.
//

import Foundation
import UIKit

class AccessTokenDelegate: NSObject, AIAuthenticationDelegate {
    let parentController: ViewController
    
    init(parentController: ViewController) {
        self.parentController = parentController
    }
    
    @objc func requestDidSucceed(apiResult: APIResult!) {
        parentController.updateAmazonId(apiResult.result as? String)
    }
    
    @objc func requestDidFail(errorResponse: APIError) {
        let alertController = UIAlertController(title: "",
            message: "AccessToken:" + errorResponse.error.message,
            preferredStyle: .Alert)
        let defaultAction = UIAlertAction(title: "OK", style: .Default, handler: nil)
        alertController.addAction(defaultAction)
        
        parentController.presentViewController(alertController, animated: true, completion: nil)
    }
}
