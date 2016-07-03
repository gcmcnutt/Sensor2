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
    let SLOW_POLL_DELAY_SEC = 5.0
    let MAX_EARLIEST_TIME_SEC = -24.0 * 60.0 * 60.0 // a day ago
    
    let wcsession = WCSession.defaultSession()
    let sr = CMSensorRecorder()
    let haveAccelerometer = CMSensorRecorder.isAccelerometerRecordingAvailable()
    let authorizedAccelerometer = CMSensorRecorder.isAuthorizedForRecording()
    
    var appContext : NSDictionary = [:]
    
    var durationValue = 5.0 // UI default
    private var dequeuerState: UInt8 = 0 // UI default
    
    var cmdCount = 0
    var itemCount = 0
    var latestDate = NSDate.distantPast()
    var lastError = ""
    var errors = 0
    
    var fileCount = 0
    var writtenRecords = 0
    var outPath : NSURL!
    var outStream : NSOutputStream!
    
    var fakeData : Bool = false
    
    func applicationDidFinishLaunching() {
        // Perform any final initialization of your application.
        
        // wake up session to phone
        wcsession.delegate = self
        wcsession.activateSession()
    }
    
    func applicationDidBecomeActive() {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }
    
    func applicationWillResignActive() {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, etc.
    }
    
    func session(session: WCSession, didFinishFileTransfer file: WCSessionFileTransfer, error: NSError?) {
        if (error != nil) {
            NSLog("fileTransfer error=\(error!.description), file=\(file.file.fileURL.description)")
            // TODO stop dequeue
        }
        do {
            try NSFileManager.defaultManager().removeItemAtURL(file.file.fileURL)
            NSLog("fileTransfer removes=\(file.file.fileURL.description)")
        } catch let error as NSError {
            NSLog("fileTransfer removeError=\(error.domain), file\(file.file.fileURL.description)")
        }
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
            cmdCount += 1
            NSLog("dequeueLoop(\(cmdCount))")
            
            // within a certain time of now
            let earliest = NSDate().dateByAddingTimeInterval(MAX_EARLIEST_TIME_SEC)
            var newLatestDate = latestDate.laterDate(earliest)
            var newItems = 0
            
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
                        
                        writeRecord(lastElement.startDate, x : lastElement.acceleration.x,
                                    y : lastElement.acceleration.y, z : lastElement.acceleration.z)
                        
                        newItems += 1
                        newLatestDate = newLatestDate.laterDate(lastElement.startDate)
                    }
                }
            } else {
                while (isRun() && newLatestDate.compare(NSDate()) == NSComparisonResult.OrderedAscending) {
                    
                    writeRecord(newLatestDate, x: random(), y: random(), z: random())
                    
                    newItems += 1
                    newLatestDate = newLatestDate.dateByAddingTimeInterval(0.02)
                }
            }
            
            if (writtenRecords > 0) {
                latestDate = newLatestDate
                itemCount += newItems

                NSLog("commit latestDate=\(latestDate), writtenRecords=\(writtenRecords), fileCount=\(fileCount), itemCount=\(itemCount)")

                outStream.close()
                writtenRecords = 0
                
                wcsession.transferFile(outPath, metadata: nil)
                
                // TODO update file transfer in progress count UI
            }

            NSOperationQueue.mainQueue().addOperationWithBlock() {
                (WKExtension.sharedExtension().rootInterfaceController
                    as! InterfaceController).updateUI(self.cmdCount, itemCount: self.itemCount, latestDate: self.latestDate, errors: self.errors, lastError: self.lastError)
            }

            NSThread.sleepForTimeInterval(SLOW_POLL_DELAY_SEC)
        }
        NSLog("exit dequeue loop")
    }
    
    func writeRecord(sampleDate : NSDate, x : Double, y : Double, z: Double) {
        if (writtenRecords == 0) {
            let directory = NSTemporaryDirectory()
            let fileName = NSUUID().UUIDString
            
            outPath = NSURL.fileURLWithPathComponents([directory, fileName])
            try! "".writeToURL(outPath, atomically: true, encoding: NSUTF8StringEncoding)
            outStream = NSOutputStream(toFileAtPath: outPath.path!, append: false)
            outStream.open()
            
            fileCount += 1
        }
        
        // now write the data
        let record = String(format: "%@,%5.3f,%5.3f,%5.3f\n", AppGlobals.sharedInstance.dateFormatter.stringFromDate(sampleDate), x, y, z)
        let encodedRecord = [UInt8](record.utf8)
        let retCount = outStream.write(encodedRecord, maxLength: encodedRecord.count)
        if (retCount == -1) {
            NSLog("writeError=\(outStream.streamError!.description)")
        }
        
        writtenRecords += 1
    }
}
