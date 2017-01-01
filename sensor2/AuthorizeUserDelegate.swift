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
    let delegate: AppDelegate
    
    init(delegate: AppDelegate) {
        self.delegate = delegate
    }
    
    @objc func requestDidSucceed(_ apiResult: APIResult!) {
        launchGetAccessToken()
    }
    
    @objc func requestDidFail(_ errorResponse: APIError) {
        let alertController = UIAlertController(title: "",
                                                message: "AuthorizeUser:" + errorResponse.error.message,
                                                preferredStyle: .alert)
        let defaultAction = UIAlertAction(title: "OK", style: .default, handler: nil)
        alertController.addAction(defaultAction)
        
        delegate.viewController.present(alertController, animated: true, completion: nil)
    }
    
    func launchGetAccessToken() {
        // initialize the token system
        let requestScopes: [String] = ["profile"]
        AIMobileLib.getAccessToken(forScopes: requestScopes, withOverrideParams: ["kForceRefresh" : "YES"], delegate: delegate)
    }
}
