//
//  SensorCognitoImpl.swift
//
//  Created by Greg McNutt on 01/09/2016.
//  Copyright © 2015 Greg McNutt. All rights reserved.
//

import Foundation
import Darwin

// collect up accelerometer data in a flushable format
class SensorCognitoImpl {
    static let AWS_REQUEST_TIME_FORMAT = "yyyyMMdd'T'HHmmss'Z'"
    static let EXPIRATION_KEY = "Expiration"
    static let SECRET_KEY_KEY = "SecretKey"
    static let SESSION_TOKEN_KEY = "SessionToken"
    static let ACCESS_KEY_ID_KEY = "AccessKeyId"
    static let IDENTITY_ID_KEY = "IdentityId"
    static let CREDENTIALS_KEY = "Credentials"
    
    let MIN_TOKEN_REMAIN = 100.0
    
    var awsRequestTimeFormatter = NSDateFormatter()
    
    var identity : [ String : AnyObject ] = [:]
    var credentials : NSDictionary = [:]
    
    init() {
        awsRequestTimeFormatter.dateFormat = SensorDynamoImpl.AWS_REQUEST_TIME_FORMAT
        awsRequestTimeFormatter.timeZone = NSTimeZone(name:"UTC")
    }

    func getAccessKey() -> String? {
        return credentials[SensorCognitoImpl.ACCESS_KEY_ID_KEY] as? String
    }
    
    func getSecretKey() -> String? {
        return credentials[SensorCognitoImpl.SECRET_KEY_KEY] as? String
    }
    
    func getSessionToken() -> String? {
        return credentials[SensorCognitoImpl.SESSION_TOKEN_KEY] as? String
    }
    
    func getIdentityId() -> String? {
        return identity[SensorCognitoImpl.IDENTITY_ID_KEY] as? String
    }
    
    func setIdentityId(identity : [ String : AnyObject ]) {
        self.identity = identity
        credentials = [:]
        ensureCredentials()
    }
    
    // return true IFF we think we got valid credentials
    func ensureCredentials() -> Bool {
        
        // no identity
        if (identity.isEmpty) {
            return false
        }
        
        var expireTime : NSDate?
        if let refreshTimeString = credentials[SensorCognitoImpl.EXPIRATION_KEY] {
            expireTime = NSDate(timeIntervalSince1970: refreshTimeString.doubleValue)
        }
        
        // valid, not yet expired credentials
        if (expireTime != nil && expireTime!.timeIntervalSinceDate(NSDate()) > MIN_TOKEN_REMAIN) {
            return true
        }
        
        // try to refresh
        NSLog("cognitoRefresh...")
        
        let request = try! NSJSONSerialization.dataWithJSONObject(identity, options: NSJSONWritingOptions())
        
        let sem = dispatch_semaphore_create(0)
        var returnData : NSData?
        var returnError : NSError?
        
        postData(request, doneHandler : {(data : NSData?, error : NSError?) in
            
            returnData = data
            returnError = error
            
            dispatch_semaphore_signal(sem)
        })
        
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER)
        
        // refresh failed
        if (returnError != nil || returnData == nil) {
            NSLog("cognitoRefresh failed \(returnError)")
            return false
        }
        
        // finally attempt to parse/update credentials
        do {
            let response = try NSJSONSerialization.JSONObjectWithData(returnData!, options: NSJSONReadingOptions()) as! NSDictionary
            credentials = response[SensorCognitoImpl.CREDENTIALS_KEY] as! NSDictionary
            NSLog("credentials updated \(credentials)")
            return true
        } catch {
            // TODO
            NSLog("cognitoRefresh error")
        }
        return false
    }
    
    
    func postData(data : NSData, doneHandler : (NSData?, NSError?) -> Void) {
        let requestMethod = "POST"
        
        // set up the request...
        let url = NSURL(string: "https://cognito-identity.us-east-1.amazonaws.com/")!
        let request = NSMutableURLRequest(URL: url)
        request.addValue(awsRequestTimeFormatter.stringFromDate(NSDate()), forHTTPHeaderField: "x-amz-date")
        request.addValue("com.amazonaws.cognito.identity.model.AWSCognitoIdentityService.GetCredentialsForIdentity", forHTTPHeaderField: "x-amz-target")
        request.addValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.HTTPMethod = requestMethod
        
        let session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration())
        
        let task = session.uploadTaskWithRequest(request, fromData: data, completionHandler: {
            (data: NSData?, response: NSURLResponse?, error: NSError?) -> Void in
            var outData : NSData? = nil
            var outError : NSError? = nil
            if (data != nil) {
                NSLog("data(\(String(data: data!, encoding: NSUTF8StringEncoding)))")
                outData = data!.copy() as? NSData
            }
            if (error != nil) {
                NSLog("error(\(error))")
                outError = error!.copy() as? NSError
            }
            doneHandler(outData, outError)
            session.invalidateAndCancel()
        })
        task.resume()
    }
}
