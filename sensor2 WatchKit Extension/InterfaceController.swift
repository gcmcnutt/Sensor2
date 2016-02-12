//
//  InterfaceController.swift
//  sensor2 WatchKit Extension
//
//  Created by Greg McNutt on 11/21/15.
//  Copyright © 2015 Greg McNutt. All rights reserved.
//

import WatchKit
import Foundation
import CoreMotion

class InterfaceController: WKInterfaceController {
    let extensionDelegate = WKExtension.sharedExtension().delegate as! ExtensionDelegate
    
    var lastStart = NSDate()
    
    @IBOutlet var durationVal: WKInterfaceLabel!
    @IBOutlet var startVal: WKInterfaceButton!
    @IBOutlet var lastStartVal: WKInterfaceLabel!
    @IBOutlet var dequeuerButton: WKInterfaceSwitch!
    @IBOutlet var cmdCountVal: WKInterfaceLabel!
    @IBOutlet var itemCountVal: WKInterfaceLabel!
    @IBOutlet var latestVal: WKInterfaceLabel!
    @IBOutlet var errorsVal: WKInterfaceLabel!
    @IBOutlet var lastVal: WKInterfaceLabel!
    
    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
        
        // Configure interface objects here.
        
        // can we record?
        startVal.setEnabled(extensionDelegate.haveAccelerometer)
        lastStartVal.setText(AppGlobals.sharedInstance.summaryDateFormatter.stringFromDate(lastStart))
        
        // do we have access to sensor?
        if (!extensionDelegate.authorizedAccelerometer) {
            startVal.setTitle("not auth")
        }
    }
    
    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()
    }
    
    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }
    
    // UI stuff
    @IBAction func fakeDataAction(value: Bool) {
        extensionDelegate.fakeData = value
    }
    
    @IBAction func durationAction(value: Float) {
        extensionDelegate.durationValue = Double(value)
        self.durationVal.setText(value.description)
    }
    
    func stopDequeue() {
        dequeuerButton.setOn(false)
        extensionDelegate.setRun(false)

        NSLog("stop dequeuer...")
        let action1 = WKAlertAction(title: "Ok", style: .Cancel) {}
        self.presentAlertControllerWithTitle("Error", message: "Can't get credentials from iPhone", preferredStyle: .ActionSheet, actions: [action1])
    }
    
    @IBAction func startRecorderAction() {
        lastStart = NSDate()
        self.lastStartVal.setText(AppGlobals.sharedInstance.summaryDateFormatter.stringFromDate(lastStart))
        extensionDelegate.record()
    }
    
    @IBAction func dequeuerAction(value: Bool) {
        extensionDelegate.setRun(value)
        
        // reset first fetch from time of starting dequeue
        if (value) {
            extensionDelegate.latestDate = lastStart
            
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0)) {
                self.extensionDelegate.dequeueLoop()
            }
        }
    }
    
    func updateUI(cmdCount : Int, itemCount : Int, latestDate : NSDate, errors : Int, lastError : String) {
        cmdCountVal.setText(cmdCount.description)
        itemCountVal.setText(itemCount.description)
        latestVal.setText(AppGlobals.sharedInstance.summaryDateFormatter.stringFromDate(
            latestDate))
        errorsVal.setText(errors.description)
        lastVal.setText(lastError)
    }
}
