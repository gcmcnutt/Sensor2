//
//  ViewController.swift
//  sensor2
//
//  Created by Greg McNutt on 11/21/15.
//  Copyright © 2015 Greg McNutt. All rights reserved.
//

import UIKit
import TwitterKit

class ViewController: UIViewController, GIDSignInUIDelegate {
    
    @IBOutlet weak var amznVal: UILabel!
    @IBOutlet weak var googVal: UILabel!
    @IBOutlet weak var twtrVal: UILabel!
    @IBOutlet weak var fbVal: UILabel!
    @IBOutlet weak var errText: UILabel!
    @IBOutlet weak var signInButton: GIDSignInButton!
    @IBOutlet weak var twitterLoginButton: TWTRLogInButton!
    @IBOutlet weak var facebookLoginButton: FBSDKLoginButton!
    
    let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        // google setup
        GIDSignIn.sharedInstance().uiDelegate = self
        
        // Uncomment to automatically sign in the user.
        GIDSignIn.sharedInstance().signInSilently()
        
        // TODO(developer) Configure the sign-in button look/feel
        // ...
        
        // twitter setup
        twitterLoginButton.logInCompletion = {
            (session, error) -> Void in
            if (session != nil) {
                self.appDelegate.twitterLogin(session!)
            } else {
                NSLog("error: \(error?.localizedDescription)")
            }
        }
        
        // facebook setup
        facebookLoginButton.readPermissions = ["email"];
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func loginAmazonAction(sender: AnyObject) {
        // Requesting both scopes for the current user.
        let requestScopes: [String] = ["profile", "postal_code"]
        let delegate = AuthorizeUserDelegate(delegate: appDelegate)
        AIMobileLib.authorizeUserForScopes(requestScopes, delegate: delegate)
    }
    
    @IBAction func logoutAction(sender: AnyObject) {
        
        // amazon
        let delegate = LogoutDelegate(parentController: self)
        AIMobileLib.clearAuthorizationState(delegate)
        
        // google
        GIDSignIn.sharedInstance().signOut()
        
        // twitter
        let store = Twitter.sharedInstance().sessionStore
        let session = store.session()
        if let userID = session?.userID {
            store.logOutUserID(userID)
        }
        
        // facebook
        FBSDKLoginManager().logOut()
        
        // rest of the app
        appDelegate.clearCredentials()
    }
    
    func updateLoginState(amzn: String, goog: String, twtr: String, fb:String) {
        NSOperationQueue.mainQueue().addOperationWithBlock() {
            self.amznVal.text = amzn
            self.googVal.text = goog
            self.twtrVal.text = twtr
            self.fbVal.text = fb
        }
        updateErrorState("")
    }
    
    func updateErrorState(err: String) {
        NSOperationQueue.mainQueue().addOperationWithBlock() {
            self.errText.text = err
        }
    }
}

