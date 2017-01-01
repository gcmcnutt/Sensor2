//
//  SensorDynamoImpl.swift
//
//  Created by Greg McNutt on 11/21/15.
//  Copyright © 2015 Greg McNutt. All rights reserved.
//

import Foundation
import CoreMotion
import Darwin
import WatchKit

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
    var itemTimeFormatter = DateFormatter()
    var columnTimeFormatter = DateFormatter()
    var systemTimeFormatter = DateFormatter()
    var awsRequestTimeFormatter = DateFormatter()
    var awsRequestDateFormatter = DateFormatter()
    
    var priorTimeSlot = ""
    
    init(extensionDelegate: ExtensionDelegate) {
        self.extensionDelegate = extensionDelegate
        
        itemTimeFormatter.dateFormat = SensorDynamoImpl.ITEM_TIME_FORMAT
        itemTimeFormatter.timeZone = TimeZone(identifier:"UTC")
        
        columnTimeFormatter.dateFormat = SensorDynamoImpl.COLUMN_TIME_FORMAT
        columnTimeFormatter.timeZone = TimeZone(identifier:"UTC")
        
        systemTimeFormatter.dateFormat = SensorDynamoImpl.SYSTEM_TIME_FORMAT
        systemTimeFormatter.timeZone = TimeZone(identifier:"UTC")
        
        awsRequestTimeFormatter.dateFormat = SensorDynamoImpl.AWS_REQUEST_TIME_FORMAT
        awsRequestTimeFormatter.timeZone = TimeZone(identifier:"UTC")
        
        awsRequestDateFormatter.dateFormat = SensorDynamoImpl.AWS_REQUEST_DATE_FORMAT
        awsRequestDateFormatter.timeZone = TimeZone(identifier:"UTC")
    }
    
    // add an ordered sample, auto flush as necessary
    func addSample(_ sample : CMRecordedAccelerometerData) -> (Bool, Error?) {
        return addSample(sample.startDate, x : sample.acceleration.x, y : sample.acceleration.y, z : sample.acceleration.z)
    }
    
    func addSample(_ startDate: Date, x: Double, y: Double, z: Double) -> (Bool, Error?) {
        // figure out the seconds slot for this sample
        let timeSlot = itemTimeFormatter.string(from: startDate)
        
        // do an update flush if this is the initial partially filled timeSlot
        if (timeSlot != priorTimeSlot && itemMap.count == 1 && (itemMap[priorTimeSlot]?.count)! < 50) {
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
            itemMap[timeSlot] = [:] as AnyObject
        }
        
        var item = itemMap[timeSlot] as! [Date : [Double]]
        item[startDate] = [x, y, z]
        itemMap[timeSlot] = item as AnyObject?
        return (false, nil)
    }
    
    func flushHandler(_ doUpdate : Bool) -> (commit: Bool, error: Error?) {
        var returnedData : Data?
        var returnedError : Error?
        
        NSLog("start flush")
        
        // update credentials
        let credentials = extensionDelegate.getCredentials()
        if (credentials.count == 0) {
            OperationQueue.main.addOperation() {
                (WKExtension.shared().rootInterfaceController
                    as! InterfaceController).stopDequeue()
            }
            
            return (false, nil)
        }
        
        autoreleasepool { () -> Void in
            var minDate = Date.distantFuture
            var maxDate = Date.distantPast
            var itemCount = 0
            var dynamoPayload : [String : Any]!
            var actionType : String!
            
            
            if (doUpdate) {
                
                // format assumed single-item as an updateItem request
                assert(itemMap.count == 1)
                
                // the element to process
                let (timeSlot, entry) = itemMap.first!
                
                // generate key part of expression
                let key = [
                    SensorDynamoImpl.HASH_KEY_COLNAME : ["S" : credentials[AppGlobals.CRED_COGNITO_KEY]!],
                    SensorDynamoImpl.RANGE_KEY_COLNAME : ["S" : timeSlot]
                ]
                
                // generate updateExpression
                var attributeValues : [String : [String : Any]] = [:]
                let processingTime = systemTimeFormatter.string(from: Date())
                var updateExpression = "SET \(SensorDynamoImpl.P_DATE_COLNAME)=:\(SensorDynamoImpl.P_DATE_COLNAME)"
                attributeValues[":" + SensorDynamoImpl.P_DATE_COLNAME] = [ "S" : processingTime]
                
                // add in the rest of the items
                let items = entry as! [Date : [Double]]
                
                for (startDate, sample) in items {
                    maxDate = maxDate < startDate ? startDate : maxDate
                    minDate = minDate < startDate ? minDate : startDate
                    itemCount += 1
                    
                    let columnTime = columnTimeFormatter.string(from: startDate)
                    
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
                var items : [Any] = []
                for (timeSlot, entry) in itemMap {
                    var item : [String : Any] = [:]
                    
                    // per-slot entries
                    item[SensorDynamoImpl.HASH_KEY_COLNAME] = ["S": credentials[AppGlobals.CRED_COGNITO_KEY]!]
                    item[SensorDynamoImpl.RANGE_KEY_COLNAME] = ["S": timeSlot]
                    item[SensorDynamoImpl.P_DATE_COLNAME] = ["S" : systemTimeFormatter.string(from: Date())]
                    
                    // per-sample entries
                    for (startDate, sample) in entry as! [Date : [Double]] {
                        maxDate = maxDate < startDate ? startDate : maxDate
                        minDate = minDate < startDate ? minDate : startDate
                        itemCount += 1
                        
                        let columnTime = columnTimeFormatter.string(from: startDate)
                        item[String(format: SensorDynamoImpl.COLUMN_FORMAT, SensorDynamoImpl.X_BASE, columnTime)] = ["N" : String(format: SensorDynamoImpl.SAMPLE_FORMAT, sample[0])]
                        item[String(format: SensorDynamoImpl.COLUMN_FORMAT, SensorDynamoImpl.Y_BASE, columnTime)] = ["N" : String(format: SensorDynamoImpl.SAMPLE_FORMAT, sample[1])]
                        item[String(format: SensorDynamoImpl.COLUMN_FORMAT, SensorDynamoImpl.Z_BASE, columnTime)] = ["N" : String(format: SensorDynamoImpl.SAMPLE_FORMAT, sample[2])]
                    }
                    items.append(["PutRequest" : ["Item" : item]])
                }
                dynamoPayload = ["RequestItems" : [tableName : items]]
                
                actionType = "BatchWriteItem"
            }
            
            let request = try! JSONSerialization.data(withJSONObject: dynamoPayload,
                                                      options: JSONSerialization.WritingOptions())
            
            NSLog("flush itemCount=\(itemCount), minDate=\(systemTimeFormatter.string(from: minDate)), maxDate=\(systemTimeFormatter.string(from: maxDate)), length=\(request.count)")
            
            let sem = DispatchSemaphore(value: 0)
            
            postData(credentials, action: actionType, data: request, doneHandler : {(data : Data?, error : Error?) in
                
                returnedData = data
                returnedError = error
                
                sem.signal()
            })
            
            _ = sem.wait(timeout: DispatchTime.distantFuture)
            
        }
        
        // reset for next round
        itemMap = [:]
        
        if (returnedError != nil) {
            return (false, returnedError)
        } else {
            // TODO check the data for partial submit
            return (true, nil)
        }
    }
    
    func postData(_ creds : NSDictionary, action : String!, data : Data, doneHandler : @escaping (Data?, Error?) -> Void) {
        let requestMethod = "POST"
        let region = "us-east-1"
        let service = "dynamodb"
        
        // attempt to fully sign the request...
        let url = URL(string: "https://dynamodb.us-east-1.amazonaws.com/")!
        //let url = NSURL(string: "http://127.0.0.1:1234/topics/test/topic?qos=1")!
        
        let request = NSMutableURLRequest(url: url)
        let requestTimestamp = Date()
        let requestTime = awsRequestTimeFormatter.string(from: requestTimestamp)
        let requestDate = awsRequestDateFormatter.string(from: requestTimestamp)
        request.addValue(requestTime, forHTTPHeaderField: "x-amz-date")
        request.addValue("DynamoDB_20120810." + action, forHTTPHeaderField: "x-amz-target")
        request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.addValue(creds[AppGlobals.CRED_SESSION_KEY] as! String, forHTTPHeaderField: "x-amz-security-token")
        
        let signedHeaders = "content-length;content-type;host;x-amz-date;x-amz-security-token;x-amz-target" // TODO params
        
        // step 1 -- canonical request
        var canonicalRequest = requestMethod + "\n"
        canonicalRequest += url.path + "\n"
        canonicalRequest += /*url.query! +*/ "\n"
        canonicalRequest += "content-length:" + data.count.description + "\n"
        canonicalRequest += "content-type:" + request.value(forHTTPHeaderField: "Content-Type")! + "\n"
        canonicalRequest += "host:" + url.host!.lowercased() + "\n"
        canonicalRequest += "x-amz-date:" + request.value(forHTTPHeaderField: "x-amz-date")! + "\n"
        canonicalRequest += "x-amz-security-token:" + request.value(forHTTPHeaderField: "x-amz-security-token")! + "\n"
        canonicalRequest += "x-amz-target:" + request.value(forHTTPHeaderField: "x-amz-target")! + "\n"
        canonicalRequest += "\n"
        canonicalRequest += signedHeaders + "\n"
        canonicalRequest += sha256(data)
        
        let canonicalHash = sha256(canonicalRequest.data(using: String.Encoding.utf8)!)
        
        // step 2 string to sign
        let signing = "aws4_request"
        let credentialScope = requestDate + "/" + region + "/" + service + "/" + signing
        var stringToSign = "AWS4-HMAC-SHA256\n"
        stringToSign += requestTime + "\n"
        stringToSign += credentialScope + "\n"
        stringToSign += canonicalHash
        
        // step 3 calculate signature
        let secret = "AWS4" + (creds[AppGlobals.CRED_SECRET_KEY] as! String)
        let kDate = hmac(secret.data(using: String.Encoding.utf8)!, data: requestDate)
        let kRegion = hmac(kDate, data: region)
        let kService = hmac(kRegion, data: service)
        let kSigning = hmac(kService, data: signing)
        
        let kSignature = hmac(kSigning, data: stringToSign)
        var signature = ""
        for i in 0..<kSignature.count {
            signature += String(format: "%02x", kSignature[i])
        }
        
        // step 4 add signing information
        var authorization = "AWS4-HMAC-SHA256 Credential="
        authorization += creds[AppGlobals.CRED_ACCESS_KEY] as! String
        authorization += "/"
        authorization += credentialScope
        authorization += ", SignedHeaders="
        authorization += signedHeaders
        authorization += ", Signature="
        authorization += signature
        
        request.addValue(authorization, forHTTPHeaderField: "Authorization")
        request.httpMethod = requestMethod
        
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = NSURLRequest.CachePolicy.reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config)
        
        let start = Date()
        let task = session.uploadTask(with: request as URLRequest, from: data, completionHandler: {
            (data: Data?, response: URLResponse?, error: Error?) -> Void in
            var outData : Data? = nil
            if (data != nil) {
                NSLog("data(\(String(data: data!, encoding: String.Encoding.utf8)))")
                outData = (data! as NSData).copy() as? Data
            }
            if (error != nil) {
                NSLog("error(\(error))")
            }
            doneHandler(outData, error)
            session.invalidateAndCancel()
            let duration = Date().timeIntervalSince(start)
            NSLog("*** network duration \(duration)")
        })
        task.resume()
    }
    
    func sha256(_ data: Data) -> String {
        var res = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0, CC_LONG(data.count), &res)
        }
        var hash = ""
        for i in 0..<res.count {
            hash += String(format: "%02x", res[i])
        }
        return hash
    }
    
    enum HMACAlgorithm {
        case md5, sha1, sha224, sha256, sha384, sha512
        
        func toCCHmacAlgorithm() -> CCHmacAlgorithm {
            var result: Int = 0
            switch self {
            case .md5:
                result = kCCHmacAlgMD5
            case .sha1:
                result = kCCHmacAlgSHA1
            case .sha224:
                result = kCCHmacAlgSHA224
            case .sha256:
                result = kCCHmacAlgSHA256
            case .sha384:
                result = kCCHmacAlgSHA384
            case .sha512:
                result = kCCHmacAlgSHA512
            }
            return CCHmacAlgorithm(result)
        }
        
        func digestLength() -> Int {
            var result: CInt = 0
            switch self {
            case .md5:
                result = CC_MD5_DIGEST_LENGTH
            case .sha1:
                result = CC_SHA1_DIGEST_LENGTH
            case .sha224:
                result = CC_SHA224_DIGEST_LENGTH
            case .sha256:
                result = CC_SHA256_DIGEST_LENGTH
            case .sha384:
                result = CC_SHA384_DIGEST_LENGTH
            case .sha512:
                result = CC_SHA512_DIGEST_LENGTH
            }
            return Int(result)
        }
    }
    
    func hmac(_ key: Data, data: String) -> Data {
        let dbytes = data.data(using: String.Encoding.utf8)!
        var context = CCHmacContext()
        let algorithm = HMACAlgorithm.sha256
        CCHmacInit(&context, algorithm.toCCHmacAlgorithm(), (key as NSData).bytes, key.count)
        CCHmacUpdate(&context, (dbytes as NSData).bytes, dbytes.count)
        
        let digest = NSMutableData(length: Int(CC_SHA256_DIGEST_LENGTH))!
        CCHmacFinal(&context, UnsafeMutableRawPointer(digest.mutableBytes))
        return Data(bytes: UnsafeRawPointer(digest.bytes), count : digest.length)
    }
}
