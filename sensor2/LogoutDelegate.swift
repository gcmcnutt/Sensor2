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
    
    @objc func requestDidSucceed(_ apiResult: APIResult!) {
        // Your additional logic after the user authorization state is cleared.
                
        let alertController = UIAlertController(title: "",
            message: "User Logged out.",
            preferredStyle: .alert)
        let defaultAction = UIAlertAction(title: "OK", style: .default, handler: nil)
        alertController.addAction(defaultAction)
        
        parentController.present(alertController, animated: true, completion: nil)
    }
    
    @objc func requestDidFail(_ errorResponse: APIError) {
        let alertController = UIAlertController(title: "",
            message: "Logout:" + errorResponse.error.message,
            preferredStyle: .alert)
        let defaultAction = UIAlertAction(title: "OK", style: .default, handler: nil)
        alertController.addAction(defaultAction)
        
        parentController.present(alertController, animated: true, completion: nil)
    }
}
