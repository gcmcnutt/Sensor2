//
//  CognitoCustomProviderManager.swift
//    from: http://stackoverflow.com/questions/38311479/iosaws-cognito-logins-is-deprecated-use-awsidentityprovidermanager#38464781
//  sensor2
//
//  Created by Greg McNutt on 1/8/17.
//  Copyright © 2017 Greg McNutt. All rights reserved.
//
import Foundation

class CognitoCustomProviderManager: NSObject, AWSIdentityProviderManager {
    var tokens : [String: Any]
    
    init(tokens: [String: Any]) {
        self.tokens = tokens
    }
    
    @objc func logins() -> AWSTask<NSDictionary> {
        let dToken = NSDictionary(dictionary: tokens)
        return AWSTask(result: dToken)
    }
}
