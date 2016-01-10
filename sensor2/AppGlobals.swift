//
//  AppGlobals.swift
//  sensor
//
//  Created by Greg McNutt on 8/26/15.
//  Copyright © 2015 Greg McNutt. All rights reserved.
//

import Foundation

class AppGlobals {
    
    // key for the cognito pool in Info
    static let IDENTITY_POOL_ID_KEY = "cognitoPool"
    static let ACCOUNT_ID_KEY = "awsAccount"
    
    // dictionary keys for state update
    static let IDENTITY_KEY = "identity"
        
    let dateFormatter = NSDateFormatter()
    let summaryDateFormatter = NSDateFormatter()
    
    // used for global date formatting...
    static let ISO8601_TIME_FORMAT = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    static let SUMMARY_TIME_FORMAT = "HH:mm:ss.SSS"
    
    static let sharedInstance = AppGlobals()
    
    init() {
        dateFormatter.dateFormat = AppGlobals.ISO8601_TIME_FORMAT
        dateFormatter.timeZone = NSTimeZone(name:"UTC");
        
        summaryDateFormatter.dateFormat = AppGlobals.SUMMARY_TIME_FORMAT
    }
}
