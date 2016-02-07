//
//  ViewController.swift
//  sensor2
//
//  Created by Greg McNutt on 11/21/15.
//  Copyright © 2015 Greg McNutt. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    @IBOutlet weak var nameVal: UILabel!
    @IBOutlet weak var emailVal: UILabel!
    @IBOutlet weak var idVal: UILabel!
    @IBOutlet weak var postalVal: UILabel!
    
    let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func loginAction(sender: AnyObject) {
        // Requesting both scopes for the current user.
        let requestScopes: [String] = ["profile", "postal_code"]
        let delegate = AuthorizeUserDelegate(parentController: self)
        AIMobileLib.authorizeUserForScopes(requestScopes, delegate: delegate)
    }
    
    @IBAction func logoutAction(sender: AnyObject) {
        let delegate = LogoutDelegate(parentController: self)
        AIMobileLib.clearAuthorizationState(delegate)
    }
    
    func completeLogout() {
        appDelegate.clearCredentials()
        updateLoginState()
    }
    
    func updateLoginState(name : String = "", email : String = "", userId : String = "", postal : String = "") {
        NSOperationQueue.mainQueue().addOperationWithBlock() {
            self.nameVal.text = name
            self.emailVal.text = email
            self.idVal.text = userId
            self.postalVal.text = postal
        }
    }
}

