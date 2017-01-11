//
//  AppGlobals.swift
//  sensor
//
//  Created by Greg McNutt on 8/26/15.
//  Copyright © 2015 Greg McNutt. All rights reserved.
//

import Foundation

class AppGlobals {
    
    // access credentials details
    static let CRED_COGNITO_KEY = "cognitoId"
    static let CRED_ACCESS_KEY = "accessKey"
    static let CRED_SECRET_KEY = "secretKey"
    static let CRED_SESSION_KEY = "sessionKey"
    static let CRED_EXPIRATION_KEY = "expirationKey"
    
    // key for the cognito pool in Info
    static let IDENTITY_POOL_ID_KEY = "cognitoPool"
    static let DYNAMO_TABLE_NAME_KEY = "DynamoTableName"
    
    let dateFormatter = DateFormatter()
    let summaryDateFormatter = DateFormatter()
    
    // used for global date formatting...
    static let ISO8601_TIME_FORMAT = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    static let SUMMARY_TIME_FORMAT = "HH:mm:ss.SSS"
    
    // send message constants
    static let SESSION_ACTION = "action"
    static let CLEAR_CREDENTIALS = "clearCredentials"
    static let GET_CREDENTIALS = "getCredentials"
    
    static let sharedInstance = AppGlobals()
    
    init() {
        dateFormatter.dateFormat = AppGlobals.ISO8601_TIME_FORMAT
        dateFormatter.timeZone = TimeZone(identifier:"UTC");
        
        summaryDateFormatter.dateFormat = AppGlobals.SUMMARY_TIME_FORMAT
    }
}
