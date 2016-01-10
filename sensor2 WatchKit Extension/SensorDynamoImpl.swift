//
//  SensorDynamoImpl.swift
//
//  Created by Greg McNutt on 11/21/15.
//  Copyright © 2015 Greg McNutt. All rights reserved.
//

import Foundation
import CoreMotion
import Darwin

// collect up accelerometer data in a flushable format
class SensorDynamoImpl {
    static let SECONDS_PER_BATCH = 25
    static let X_BASE = "x"
    static let Y_BASE = "y"
    static let Z_BASE = "z"
    static let SAMPLE_FORMAT = "%0.4f"
    static let COLUMN_FORMAT = "%@%@"
    static let UPDATE_COLUMN_FORMAT = ",%@%@=:%@%@"
    static let ITEM_TIME_FORMAT = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    static let SYSTEM_TIME_FORMAT = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    static let COLUMN_TIME_FORMAT = "SSS"
    static let AWS_REQUEST_TIME_FORMAT = "yyyyMMdd'T'HHmmss'Z'"
    static let AWS_REQUEST_DATE_FORMAT = "yyyyMMdd"
    static let HASH_KEY_COLNAME = "hashKey"
    static let RANGE_KEY_COLNAME = "rangeKey"
    static let P_DATE_COLNAME = "pDate"
    
    let tableName = "sensor2" // TODO
    let extensionDelegate : ExtensionDelegate
    
    // an array of dictionary items -- each dictionary entry is a single second's samples
    var itemMap : [String : AnyObject] = [:]
    var itemTimeFormatter = NSDateFormatter()
    var columnTimeFormatter = NSDateFormatter()
    var systemTimeFormatter = NSDateFormatter()
    var awsRequestTimeFormatter = NSDateFormatter()
    var awsRequestDateFormatter = NSDateFormatter()
    
    var priorTimeSlot = ""
    
    init(extensionDelegate: ExtensionDelegate) {
        self.extensionDelegate = extensionDelegate
        
        itemTimeFormatter.dateFormat = SensorDynamoImpl.ITEM_TIME_FORMAT
        itemTimeFormatter.timeZone = NSTimeZone(name:"UTC")
        
        columnTimeFormatter.dateFormat = SensorDynamoImpl.COLUMN_TIME_FORMAT
        columnTimeFormatter.timeZone = NSTimeZone(name:"UTC")
        
        systemTimeFormatter.dateFormat = SensorDynamoImpl.SYSTEM_TIME_FORMAT
        systemTimeFormatter.timeZone = NSTimeZone(name:"UTC")
        
        awsRequestTimeFormatter.dateFormat = SensorDynamoImpl.AWS_REQUEST_TIME_FORMAT
        awsRequestTimeFormatter.timeZone = NSTimeZone(name:"UTC")
        
        awsRequestDateFormatter.dateFormat = SensorDynamoImpl.AWS_REQUEST_DATE_FORMAT
        awsRequestDateFormatter.timeZone = NSTimeZone(name:"UTC")
    }
    
    // add an ordered sample, auto flush as necessary
    func addSample(sample : CMRecordedAccelerometerData) -> (Bool, NSError?) {
        return addSample(sample.startDate, x : sample.acceleration.x, y : sample.acceleration.y, z : sample.acceleration.z)
    }
    
    func addSample(startDate: NSDate, x: Double, y: Double, z: Double) -> (Bool, NSError?) {
        // figure out the seconds slot for this sample
        let timeSlot = itemTimeFormatter.stringFromDate(startDate)
        
        // do an update flush if this is the initial partially filled timeSlot
        if (timeSlot != priorTimeSlot && itemMap.count == 1 && itemMap[priorTimeSlot]?.count < 50) {
            return flushHandler(true)
        }
        
        priorTimeSlot = timeSlot
        
        // if we don't have this slot int the map, prepare...
        if itemMap[timeSlot] == nil {
            
            // this is a new second, do we have space for it, or flush?
            if (itemMap.count >= SensorDynamoImpl.SECONDS_PER_BATCH) {
                return flushHandler(false)
            }
            
            // add new element to data
            itemMap[timeSlot] = [:]
        }
        
        var item = itemMap[timeSlot] as! [NSDate : [Double]]
        item[startDate] = [x, y, z]
        itemMap[timeSlot] = item
        return (false, nil)
    }
    
    func flushHandler(doUpdate : Bool) -> (commit: Bool, error: NSError?) {
        var minDate = NSDate.distantFuture()
        var maxDate = NSDate.distantPast()
        var itemCount = 0
        var dynamoPayload : [String : AnyObject]!
        var actionType : String!
        
        NSLog("start flush")
        
        // update credentials
        if (!extensionDelegate.sensorCognitoImpl.ensureCredentials()) {
            // TODO some other error combos to consider (mem leak too)
            return (false, nil)
        }
        
        if (doUpdate) {
            
            // format assumed single-item as an updateItem request
            assert(itemMap.count == 1)
            
            // the element to process
            let (timeSlot, entry) = itemMap.first!
            
            // generate key part of expression
            let key = [
                SensorDynamoImpl.HASH_KEY_COLNAME : ["S" : extensionDelegate.sensorCognitoImpl.getIdentityId()!],
                SensorDynamoImpl.RANGE_KEY_COLNAME : ["S" : timeSlot]
            ]
            
            // generate updateExpression
            var attributeValues : [String : [String : AnyObject]] = [:]
            let processingTime = systemTimeFormatter.stringFromDate(NSDate())
            var updateExpression = "SET \(SensorDynamoImpl.P_DATE_COLNAME)=:\(SensorDynamoImpl.P_DATE_COLNAME)"
            attributeValues[":" + SensorDynamoImpl.P_DATE_COLNAME] = [ "S" : processingTime]
            
            // add in the rest of the items
            let items = entry as! [NSDate : [Double]]
            
            for (startDate, sample) in items {
                maxDate = maxDate.laterDate(startDate)
                minDate = minDate.earlierDate(startDate)
                itemCount++
                
                let columnTime = columnTimeFormatter.stringFromDate(startDate)
                
                // the update expression
                updateExpression += String(format: SensorDynamoImpl.UPDATE_COLUMN_FORMAT, SensorDynamoImpl.X_BASE, columnTime, SensorDynamoImpl.X_BASE, columnTime)
                updateExpression += String(format: SensorDynamoImpl.UPDATE_COLUMN_FORMAT, SensorDynamoImpl.Y_BASE, columnTime, SensorDynamoImpl.Y_BASE, columnTime)
                updateExpression += String(format: SensorDynamoImpl.UPDATE_COLUMN_FORMAT, SensorDynamoImpl.Z_BASE, columnTime, SensorDynamoImpl.Z_BASE, columnTime)
                
                // and the attribute values
                attributeValues[":" + String(format: SensorDynamoImpl.COLUMN_FORMAT, SensorDynamoImpl.X_BASE, columnTime)] = [ "S" : String(format: SensorDynamoImpl.SAMPLE_FORMAT, sample[0]) ]
                attributeValues[":" + String(format: SensorDynamoImpl.COLUMN_FORMAT, SensorDynamoImpl.Y_BASE, columnTime)] = [ "S" : String(format: SensorDynamoImpl.SAMPLE_FORMAT, sample[1]) ]
                attributeValues[":" + String(format: SensorDynamoImpl.COLUMN_FORMAT, SensorDynamoImpl.Z_BASE, columnTime)] = [ "S" : String(format: SensorDynamoImpl.SAMPLE_FORMAT, sample[1]) ]
            }
            
            // now build the dynamo map for serialization
            dynamoPayload = [ "Key" : key, "UpdateExpression" : updateExpression, "TableName" : tableName, "ExpressionAttributeValues" : attributeValues ]
            
            actionType = "UpdateItem"
            
        } else {
            
            // format the map as a BatchWriteItem
            var items : [AnyObject] = []
            for (timeSlot, entry) in itemMap {
                var item : [String : AnyObject] = [:]
                
                // per-slot entries
                item[SensorDynamoImpl.HASH_KEY_COLNAME] = ["S": extensionDelegate.sensorCognitoImpl.getIdentityId()!]
                item[SensorDynamoImpl.RANGE_KEY_COLNAME] = ["S": timeSlot]
                item[SensorDynamoImpl.P_DATE_COLNAME] = ["S" : systemTimeFormatter.stringFromDate(NSDate())]
                
                // per-sample entries
                for (startDate, sample) in entry as! [NSDate : [Double]] {
                    maxDate = maxDate.laterDate(startDate)
                    minDate = minDate.earlierDate(startDate)
                    itemCount++
                    
                    let columnTime = columnTimeFormatter.stringFromDate(startDate)
                    item[String(format: SensorDynamoImpl.COLUMN_FORMAT, SensorDynamoImpl.X_BASE, columnTime)] = ["N" : String(format: SensorDynamoImpl.SAMPLE_FORMAT, sample[0])]
                    item[String(format: SensorDynamoImpl.COLUMN_FORMAT, SensorDynamoImpl.Y_BASE, columnTime)] = ["N" : String(format: SensorDynamoImpl.SAMPLE_FORMAT, sample[1])]
                    item[String(format: SensorDynamoImpl.COLUMN_FORMAT, SensorDynamoImpl.Z_BASE, columnTime)] = ["N" : String(format: SensorDynamoImpl.SAMPLE_FORMAT, sample[2])]
                }
                items.append(["PutRequest" : ["Item" : item]])
            }
            dynamoPayload = ["RequestItems" : [tableName : items]]
            
            actionType = "BatchWriteItem"
        }
        
        let request = try! NSJSONSerialization.dataWithJSONObject(dynamoPayload,
            options: NSJSONWritingOptions())
        
        NSLog("flush itemCount=\(itemCount), minDate=\(systemTimeFormatter.stringFromDate(minDate)), maxDate=\(systemTimeFormatter.stringFromDate(maxDate)), length=\(request.length)")
        
        let sem = dispatch_semaphore_create(0)
        var returnedData : NSData?
        var returnedError : NSError?
        
        postData(actionType, data: request, doneHandler : {(data : NSData?, error : NSError?) in
            
            returnedData = data
            returnedError = error
            
            dispatch_semaphore_signal(sem)
        })
        
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER)
        
        // reset for next round
        itemMap = [:]
        
        if (returnedError != nil) {
            return (false, returnedError)
        } else {
            // TODO check the data for partial submit
            return (true, nil)
        }
    }
    
    func postData(action : String!, data : NSData, doneHandler : (NSData?, NSError?) -> Void) {
        let requestMethod = "POST"
        let region = "us-east-1"
        let service = "dynamodb"
        
        // attempt to fully sign the request...
        let url = NSURL(string: "https://dynamodb.us-east-1.amazonaws.com/")!
        //let url = NSURL(string: "http://127.0.0.1:1234/topics/test/topic?qos=1")!
        
        let request = NSMutableURLRequest(URL: url)
        let requestTimestamp = NSDate()
        let requestTime = awsRequestTimeFormatter.stringFromDate(requestTimestamp)
        let requestDate = awsRequestDateFormatter.stringFromDate(requestTimestamp)
        request.addValue(requestTime, forHTTPHeaderField: "x-amz-date")
        request.addValue("DynamoDB_20120810." + action, forHTTPHeaderField: "x-amz-target")
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.addValue(extensionDelegate.sensorCognitoImpl.getSessionToken()!, forHTTPHeaderField: "x-amz-security-token")
        
        let signedHeaders = "content-length;content-type;host;x-amz-date;x-amz-security-token;x-amz-target" // TODO params
        
        // step 1 -- canonical request
        var canonicalRequest = requestMethod + "\n"
        canonicalRequest += url.path! + "\n"
        canonicalRequest += /*url.query! +*/ "\n"
        canonicalRequest += "content-length:" + data.length.description + "\n"
        canonicalRequest += "content-type:" + request.valueForHTTPHeaderField("Content-Type")! + "\n"
        canonicalRequest += "host:" + url.host!.lowercaseString + "\n"
        canonicalRequest += "x-amz-date:" + request.valueForHTTPHeaderField("x-amz-date")! + "\n"
        canonicalRequest += "x-amz-security-token:" + request.valueForHTTPHeaderField("x-amz-security-token")! + "\n"
        canonicalRequest += "x-amz-target:" + request.valueForHTTPHeaderField("x-amz-target")! + "\n"
        canonicalRequest += "\n"
        canonicalRequest += signedHeaders + "\n"
        canonicalRequest += sha256(data)
        
        let canonicalHash = sha256(canonicalRequest.dataUsingEncoding(NSUTF8StringEncoding)!)
        
        // step 2 string to sign
        let signing = "aws4_request"
        let credentialScope = requestDate + "/" + region + "/" + service + "/" + signing
        var stringToSign = "AWS4-HMAC-SHA256\n"
        stringToSign += requestTime + "\n"
        stringToSign += credentialScope + "\n"
        stringToSign += canonicalHash
        
        // step 3 calculate signature
        let secret = "AWS4" + extensionDelegate.sensorCognitoImpl.getSecretKey()!
        let kDate = hmac(secret.dataUsingEncoding(NSUTF8StringEncoding)!, data: requestDate)
        let kRegion = hmac(kDate, data: region)
        let kService = hmac(kRegion, data: service)
        let kSigning = hmac(kService, data: signing)
        
        let kSignature = hmac(kSigning, data: stringToSign)
        let hexSignature = NSMutableString()
        let kSignatureBytes = UnsafePointer<UInt8>(kSignature.bytes)
        for i in 0..<kSignature.length {
            hexSignature.appendFormat("%02x", kSignatureBytes[i])
        }
        let signature = String(hexSignature)
        
        // step 4 add signing information
        var authorization = "AWS4-HMAC-SHA256 Credential="
        authorization += extensionDelegate.sensorCognitoImpl.getAccessKey()!
        authorization += "/"
        authorization += credentialScope
        authorization += ", SignedHeaders="
        authorization += signedHeaders
        authorization += ", Signature="
        authorization += signature
        
        request.addValue(authorization, forHTTPHeaderField: "Authorization")
        request.HTTPMethod = requestMethod
        
        let session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration())
        
        let start = NSDate()
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
            let duration = NSDate().timeIntervalSinceDate(start)
            NSLog("*** network duration \(duration)")
        })
        task.resume()
    }
    
    func sha256(data: NSData) -> String {
        let res = NSMutableData(length: Int(CC_SHA256_DIGEST_LENGTH))!
        CC_SHA256(data.bytes, CC_LONG(data.length), UnsafeMutablePointer(res.mutableBytes))
        let resBytes = UnsafePointer<UInt8>(res.bytes)
        let hash = NSMutableString()
        for i in 0..<res.length {
            hash.appendFormat("%02x", resBytes[i])
        }
        return String(hash)
    }
    
    enum HMACAlgorithm {
        case MD5, SHA1, SHA224, SHA256, SHA384, SHA512
        
        func toCCHmacAlgorithm() -> CCHmacAlgorithm {
            var result: Int = 0
            switch self {
            case .MD5:
                result = kCCHmacAlgMD5
            case .SHA1:
                result = kCCHmacAlgSHA1
            case .SHA224:
                result = kCCHmacAlgSHA224
            case .SHA256:
                result = kCCHmacAlgSHA256
            case .SHA384:
                result = kCCHmacAlgSHA384
            case .SHA512:
                result = kCCHmacAlgSHA512
            }
            return CCHmacAlgorithm(result)
        }
        
        func digestLength() -> Int {
            var result: CInt = 0
            switch self {
            case .MD5:
                result = CC_MD5_DIGEST_LENGTH
            case .SHA1:
                result = CC_SHA1_DIGEST_LENGTH
            case .SHA224:
                result = CC_SHA224_DIGEST_LENGTH
            case .SHA256:
                result = CC_SHA256_DIGEST_LENGTH
            case .SHA384:
                result = CC_SHA384_DIGEST_LENGTH
            case .SHA512:
                result = CC_SHA512_DIGEST_LENGTH
            }
            return Int(result)
        }
    }
    
    func hmac(key: NSData, data: String) -> NSData {
        let dbytes = data.dataUsingEncoding(NSUTF8StringEncoding)!
        var context = CCHmacContext()
        let algorithm = HMACAlgorithm.SHA256
        CCHmacInit(&context, algorithm.toCCHmacAlgorithm(), key.bytes, key.length)
        CCHmacUpdate(&context, dbytes.bytes, dbytes.length)
        
        let digest = NSMutableData(length: Int(CC_SHA256_DIGEST_LENGTH))!
        CCHmacFinal(&context, UnsafeMutablePointer(digest.mutableBytes))
        return NSData(bytes : digest.bytes, length : digest.length)
    }
}
