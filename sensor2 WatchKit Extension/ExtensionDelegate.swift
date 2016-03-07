//
//  ExtensionDelegate.swift
//  sensor2 WatchKit Extension
//
//  Created by Greg McNutt on 11/21/15.
//  Copyright © 2015 Greg McNutt. All rights reserved.
//

import WatchKit
import Foundation
import CoreMotion
import WatchConnectivity

extension CMSensorDataList: SequenceType {
    public func generate() -> NSFastGenerator {
        return NSFastGenerator(self)
    }
}

class ExtensionDelegate: NSObject, WKExtensionDelegate, WCSessionDelegate {
    let SLOW_POLL_DELAY_SEC = 2.0
    let FAST_POLL_DELAY_SEC = 0.01
    let MAX_EARLIEST_TIME_SEC = -24.0 * 60.0 * 60.0 // a day ago
    let REFRESH_LEAD_SEC = 120.0
    
    let wcsession = WCSession.defaultSession()
    let sr = CMSensorRecorder()
    let haveAccelerometer = CMSensorRecorder.isAccelerometerRecordingAvailable()
    let authorizedAccelerometer = CMSensorRecorder.isAuthorizedForRecording()
    
    var appContext : NSDictionary = [:]
    
    var sensorDynamoImpl : SensorDynamoImpl!
    private var userCredentials : NSDictionary = [:]
    var durationValue = 5.0 // UI default
    private var dequeuerState: UInt8 = 0 // UI default
    
    var cmdCount = 0
    var itemCount = 0
    var latestDate = NSDate.distantPast()
    var lastError = ""
    var errors = 0
    
    var fakeData : Bool = false
    
    func applicationDidFinishLaunching() {
        // Perform any final initialization of your application.
        
        // wake up session to phone
        wcsession.delegate = self
        wcsession.activateSession()
        
        sensorDynamoImpl = SensorDynamoImpl(extensionDelegate: self)
    }
    
    func applicationDidBecomeActive() {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }
    
    func applicationWillResignActive() {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, etc.
    }
    
    func session(session: WCSession, didReceiveMessage message: [String : AnyObject]) {
        NSLog("clear credentials")
        userCredentials = [:]
        NSOperationQueue.mainQueue().addOperationWithBlock() {
            (WKExtension.sharedExtension().rootInterfaceController
                as! InterfaceController).updateCognitoId("")
        }
    }
    
    func getCredentials() -> NSDictionary {
        var sendMessage = false
        var waitForReply = true
        let expireTime = userCredentials[AppGlobals.CRED_EXPIRATION_KEY] as? NSDate
        if (expireTime == nil) {
            // no data at all so fetch and wait
            sendMessage = true
        } else {
            // data and expired so fetch and wait
            let now = NSDate()
            if (now.compare(expireTime!) == NSComparisonResult.OrderedDescending) {
                userCredentials = [:]
                sendMessage = true
            } else if (now.dateByAddingTimeInterval(REFRESH_LEAD_SEC).compare(expireTime!) == NSComparisonResult.OrderedDescending) {
                // nearing expiration so fetch [no wait]
                sendMessage = true
                waitForReply = false
            }
        }
        
        if (sendMessage) {
            NSLog("refreshing userCredentials... send=\(sendMessage), wait=\(waitForReply)")
            let sem = dispatch_semaphore_create(0)
            
            wcsession.sendMessage([AppGlobals.SESSION_ACTION : AppGlobals.GET_CREDENTIALS],
                replyHandler: {(result : [String : AnyObject]) in
                    let cognitoId = result[AppGlobals.CRED_COGNITO_KEY] as? String
                    NSLog("userCredentials refreshed cognitoId=\(cognitoId)")
                    NSOperationQueue.mainQueue().addOperationWithBlock() {
                        (WKExtension.sharedExtension().rootInterfaceController
                            as! InterfaceController).updateCognitoId(cognitoId)
                    }
                    self.userCredentials = result
                    dispatch_semaphore_signal(sem)
                }, errorHandler: {(error : NSError) in
                    NSLog("userCredentials. error=" + error.description)
                    dispatch_semaphore_signal(sem)
            })
            
            if (waitForReply) {
                dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER)
            }
        }
        
        return userCredentials
    }
    
    
    func record() {
        NSLog("recordAccelerometer(\(durationValue))")
        sr.recordAccelerometerForDuration(durationValue * 60.0)
    }
    
    func random() -> Double {
        return Double(arc4random()) / 0xFFFFFFFF
    }
    
    func setRun(state: Bool) {
        if (state) {
            OSAtomicTestAndSet(7, &dequeuerState)
        } else {
            OSAtomicTestAndClear(7, &dequeuerState)
        }
    }
    
    func isRun() -> Bool {
        return dequeuerState != 0
    }
    
    func dequeueLoop() {
        while (isRun()) {
            var foundData = false
            var commit = false
            cmdCount++
            NSLog("dequeueLoop(\(cmdCount))")
            
            // within a certain time of now
            let earliest = NSDate().dateByAddingTimeInterval(MAX_EARLIEST_TIME_SEC)
            var newLatestDate = latestDate.laterDate(earliest)
            var newItems = 0
            
            while (isRun()) {
                
                // real or faking it?
                if (haveAccelerometer && !fakeData) {
                    let data = sr.accelerometerDataFromDate(newLatestDate, toDate: NSDate())
                    if (data != nil) {
                        
                        for element in data! {
                            let lastElement = element as! CMRecordedAccelerometerData
                            
                            // skip repeated element from prior batch
                            if (!(lastElement.startDate.compare(newLatestDate) == NSComparisonResult.OrderedDescending)) {
                                continue;
                            }
                            
                            // next item, here we enqueue it
                            if (lastElement.startDate.compare(NSDate.distantPast()) == NSComparisonResult.OrderedAscending) {
                                NSLog("odd date: " + lastElement.description)
                            }
                            
                            foundData = true
                            let (isCommit, rErr) = sensorDynamoImpl.addSample(lastElement)
                            if (isCommit) {
                                commit = true
                                break;
                            } else if (rErr != nil) {
                                errors++
                                lastError = rErr!.description
                                break
                            }
                            
                            // update the uncommit state
                            newItems++
                            newLatestDate = lastElement.startDate
                        }
                    }
                } else {
                    while (isRun() && newLatestDate.compare(NSDate()) == NSComparisonResult.OrderedAscending) {
                        
                        foundData = true
                        
                        let (isCommit, rErr) = sensorDynamoImpl.addSample(newLatestDate, x: random(), y: random(), z: random())
                        if (isCommit) {
                            commit = true
                            break;
                        } else if (rErr != nil) {
                            errors++
                            lastError = rErr!.description
                            break
                        }
                        
                        newItems++
                        newLatestDate = newLatestDate.dateByAddingTimeInterval(0.02)
                    }
                }
                
                if (commit) {
                    latestDate = newLatestDate
                    itemCount += newItems
                    NSLog("commit latestDate=\(latestDate), itemCount=\(itemCount)")
                    NSOperationQueue.mainQueue().addOperationWithBlock() {
                        (WKExtension.sharedExtension().rootInterfaceController
                            as! InterfaceController).updateUI(self.cmdCount, itemCount: self.itemCount, latestDate: self.latestDate, errors: self.errors, lastError: self.lastError)
                    }
                    break
                }
                
                if (foundData) {
                    NSThread.sleepForTimeInterval(FAST_POLL_DELAY_SEC)
                } else {
                    NSThread.sleepForTimeInterval(SLOW_POLL_DELAY_SEC)
                }
            }
        }
        
        NSLog("exit dequeue loop")
    }
}
