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
    let extensionDelegate = WKExtension.shared().delegate as! ExtensionDelegate
    
    var lastStart = Date()
    
    @IBOutlet var durationVal: WKInterfaceLabel!
    @IBOutlet var startVal: WKInterfaceButton!
    @IBOutlet var lastStartVal: WKInterfaceLabel!
    @IBOutlet var dequeuerButton: WKInterfaceSwitch!
    @IBOutlet var cmdCountVal: WKInterfaceLabel!
    @IBOutlet var itemCountVal: WKInterfaceLabel!
    @IBOutlet var latestVal: WKInterfaceLabel!
    @IBOutlet var cognitoIdVal: WKInterfaceLabel!
    @IBOutlet var errorsVal: WKInterfaceLabel!
    @IBOutlet var lastVal: WKInterfaceLabel!
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        // Configure interface objects here.
        
        // can we record?
        startVal.setEnabled(extensionDelegate.haveAccelerometer)
        lastStartVal.setText(AppGlobals.sharedInstance.summaryDateFormatter.string(from: lastStart))
        
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
    @IBAction func fakeDataAction(_ value: Bool) {
        extensionDelegate.fakeData = value
    }
    
    @IBAction func durationAction(_ value: Float) {
        extensionDelegate.durationValue = Double(value)
        self.durationVal.setText(value.description)
    }
    
    func stopDequeue() {
        dequeuerButton.setOn(false)
        extensionDelegate.setRun(false)

        NSLog("stop dequeuer...")
        let action1 = WKAlertAction(title: "Ok", style: .cancel) {}
        self.presentAlert(withTitle: "Error", message: "Can't get credentials from iPhone", preferredStyle: .actionSheet, actions: [action1])
    }
    
    @IBAction func startRecorderAction() {
        lastStart = Date()
        self.lastStartVal.setText(AppGlobals.sharedInstance.summaryDateFormatter.string(from: lastStart))
        extensionDelegate.record()
    }
    
    @IBAction func dequeuerAction(_ value: Bool) {
        extensionDelegate.setRun(value)
        
        // reset first fetch from time of starting dequeue
        if (value) {
            extensionDelegate.latestDate = lastStart
            
            DispatchQueue.global(qos: DispatchQoS.QoSClass.background).async {
                self.extensionDelegate.dequeueLoop()
            }
        }
    }
    
    func updateCognitoId(_ cognitoId : String?) {
        cognitoIdVal.setText(cognitoId)
    }
    
    func updateUI(_ cmdCount : Int, itemCount : Int, latestDate : Date, errors : Int, lastError : String) {
        cmdCountVal.setText(cmdCount.description)
        itemCountVal.setText(itemCount.description)
        latestVal.setText(AppGlobals.sharedInstance.summaryDateFormatter.string(
            from: latestDate))
        errorsVal.setText(errors.description)
        lastVal.setText(lastError)
    }
}
