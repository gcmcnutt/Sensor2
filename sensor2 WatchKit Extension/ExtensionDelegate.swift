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

extension CMSensorDataList: Sequence {
    public func makeIterator() -> NSFastEnumerationIterator {
        return NSFastEnumerationIterator(self)
    }
}

class ExtensionDelegate: NSObject, WKExtensionDelegate, WCSessionDelegate {
    let SLOW_POLL_DELAY_SEC = 2.0
    let FAST_POLL_DELAY_SEC = 0.01
    let MAX_EARLIEST_TIME_SEC = -24.0 * 60.0 * 60.0 // a day ago
    let REFRESH_LEAD_SEC = 300.0
    
    var infoPlist : NSDictionary!
    let wcsession = WCSession.default()
    let sr = CMSensorRecorder()
    let haveAccelerometer = CMSensorRecorder.isAccelerometerRecordingAvailable()
    
    var appContext : NSDictionary = [:]
    
    var sensorDynamoImpl : SensorDynamoImpl!
    private var userCredentials : NSDictionary = [:]
    var durationValue = 5.0 // UI default
    private var dequeuerState: UInt8 = 0 // UI default
    
    var cmdCount = 0
    var itemCount = 0
    var latestDate = Date.distantPast
    var lastError = ""
    var errors = 0
    
    var fakeData : Bool = false
    
    func applicationDidFinishLaunching() {
        // Perform any final initialization of your application.
        
        let path = Bundle.main.path(forResource: "Info", ofType: "plist")!
        infoPlist = NSDictionary(contentsOfFile: path)
        
        // wake up session to phone
        wcsession.delegate = self
        wcsession.activate()
        
        sensorDynamoImpl = SensorDynamoImpl(extensionDelegate: self)
    }
    
    func applicationDidBecomeActive() {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }
    
    func applicationWillResignActive() {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, etc.
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        NSLog(String(format: "state=%d", activationState.rawValue))
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        NSLog("clear credentials")
        userCredentials = [:]
        OperationQueue.main.addOperation() {
            (WKExtension.shared().rootInterfaceController
                as! InterfaceController).updateCognitoId("")
        }
    }
    
    func getCredentials() -> NSDictionary {
        var sendMessage = false
        let waitForReply = true
        let expireTime = userCredentials[AppGlobals.CRED_EXPIRATION_KEY] as? Date
        if (expireTime == nil) {
            // no data at all so fetch and wait
            sendMessage = true
        } else {
            // data and expired so fetch and wait
            let now = Date()
            if (now.compare(expireTime!) == ComparisonResult.orderedDescending) {
                userCredentials = [:]
                sendMessage = true
            } else if (now.addingTimeInterval(REFRESH_LEAD_SEC).compare(expireTime!) == ComparisonResult.orderedDescending) {
                // nearing expiration so fetch [no wait]
                sendMessage = true
                //TODO analyze this... -> waitForReply = false
            }
        }
        
        if (sendMessage) {
            NSLog("refreshing userCredentials... send=\(sendMessage), wait=\(waitForReply)")
            let sem = DispatchSemaphore(value: 0)
            
            wcsession.sendMessage([AppGlobals.SESSION_ACTION : AppGlobals.GET_CREDENTIALS],
                replyHandler: {(result : [String : Any]) in
                    let cognitoId = result[AppGlobals.CRED_COGNITO_KEY] as? String
                    NSLog("userCredentials refreshed cognitoId=\(cognitoId)")
                    OperationQueue.main.addOperation() {
                        (WKExtension.shared().rootInterfaceController
                            as! InterfaceController).updateCognitoId(cognitoId)
                    }
                    self.userCredentials = result as NSDictionary
                    sem.signal()
                }, errorHandler: {(error : Error) in
                    NSLog("userCredentials. error=" + error.localizedDescription)
                    sem.signal()
            })
            
            if (waitForReply) {
                _ = sem.wait(timeout: DispatchTime.distantFuture)
            }
        }
        
        return userCredentials
    }
    
    
    func record() {
        NSLog("recordAccelerometer(\(durationValue))")
        sr.recordAccelerometer(forDuration: durationValue * 60.0)
    }
    
    func random() -> Double {
        return Double(arc4random()) / 0xFFFFFFFF
    }
    
    func setRun(_ state: Bool) {
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
            cmdCount += 1
            NSLog("dequeueLoop(\(cmdCount))")
            
            // within a certain time of now
            let earliest = Date().addingTimeInterval(MAX_EARLIEST_TIME_SEC)
            var newLatestDate = latestDate > earliest ? latestDate : earliest
            var newItems = 0
            
            while (isRun()) {
                
                // real or faking it?
                if (haveAccelerometer && !fakeData) {
                    let data = sr.accelerometerData(from: newLatestDate, to: Date())
                    if (data != nil) {
                        
                        for element in data! {
                            let lastElement = element as! CMRecordedAccelerometerData
                            
                            // skip repeated element from prior batch
                            if (!(lastElement.startDate.compare(newLatestDate) == ComparisonResult.orderedDescending)) {
                                continue;
                            }
                            
                            // next item, here we enqueue it
                            if (lastElement.startDate.compare(Date.distantPast) == ComparisonResult.orderedAscending) {
                                NSLog("odd date: " + lastElement.description)
                            }
                            
                            foundData = true
                            let (isCommit, rErr) = sensorDynamoImpl.addSample(lastElement)
                            if (isCommit) {
                                commit = true
                                break;
                            } else if (rErr != nil) {
                                errors += 1
                                lastError = rErr!.localizedDescription
                                break
                            }
                            
                            // update the uncommit state
                            newItems += 1
                            newLatestDate = lastElement.startDate
                        }
                    }
                } else {
                    while (isRun() && newLatestDate.compare(Date()) == ComparisonResult.orderedAscending) {
                        
                        foundData = true
                        
                        let (isCommit, rErr) = sensorDynamoImpl.addSample(newLatestDate, x: random(), y: random(), z: random())
                        if (isCommit) {
                            commit = true
                            break;
                        } else if (rErr != nil) {
                            errors += 1
                            lastError = rErr!.localizedDescription
                            break
                        }
                        
                        newItems += 1
                        newLatestDate = newLatestDate.addingTimeInterval(0.02)
                    }
                }
                
                if (commit) {
                    latestDate = newLatestDate
                    itemCount += newItems
                    NSLog("commit latestDate=\(latestDate), itemCount=\(itemCount)")
                    OperationQueue.main.addOperation() {
                        (WKExtension.shared().rootInterfaceController
                            as! InterfaceController).updateUI(self.cmdCount, itemCount: self.itemCount, latestDate: self.latestDate, errors: self.errors, lastError: self.lastError)
                    }
                    break
                }
                
                if (foundData) {
                    Thread.sleep(forTimeInterval: FAST_POLL_DELAY_SEC)
                } else {
                    Thread.sleep(forTimeInterval: SLOW_POLL_DELAY_SEC)
                }
            }
        }
        
        NSLog("exit dequeue loop")
    }
}
