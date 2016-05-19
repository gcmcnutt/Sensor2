//
//  AppDelegate.swift
//  sensor2
//
//  Created by Greg McNutt on 11/21/15.
//  Copyright © 2015 Greg McNutt. All rights reserved.
//

import UIKit
import WatchConnectivity
import Fabric
import TwitterKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, GIDSignInDelegate, WCSessionDelegate {
    
    var window: UIWindow?
    var viewController : ViewController!
    var infoPlist : NSDictionary!
    
    let wcsession = WCSession.defaultSession()
    
    var amazonToken : String?
    var googleToken : String?
    var twitterToken : String?
    var facebookToken : String?
    
    // AWS plumbing
    var credentialsProvider : AWSCognitoCredentialsProvider!
    
    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        // Override point for customization after application launch.
        
        let path = NSBundle.mainBundle().pathForResource("Info", ofType: "plist")!
        infoPlist = NSDictionary(contentsOfFile: path)
        
        viewController = self.window?.rootViewController as! ViewController
        
        // set up Cognito
        //AWSLogger.defaultLogger().logLevel = .Verbose
        
        credentialsProvider = AWSCognitoCredentialsProvider(
            regionType: AWSRegionType.USEast1, identityPoolId: infoPlist[AppGlobals.IDENTITY_POOL_ID_KEY] as! String)
        
        let defaultServiceConfiguration = AWSServiceConfiguration(
            region: AWSRegionType.USEast1, credentialsProvider: credentialsProvider)
        
        AWSServiceManager.defaultServiceManager().defaultServiceConfiguration = defaultServiceConfiguration
        
        // google setup
        var configureError: NSError?
        GGLContext.sharedInstance().configureWithError(&configureError)
        assert(configureError == nil, "Error configuring Google services: \(configureError)")
        GIDSignIn.sharedInstance().delegate = self
        
        // twitter setup
        Fabric.with([AWSCognito.self, Twitter.self])
        
        // facebook setup
        FBSDKApplicationDelegate.sharedInstance().application(application, didFinishLaunchingWithOptions: launchOptions)
        
        // wake up session to watch
        wcsession.delegate = self
        wcsession.activateSession()
        
        // TODO see if we are already logged in
        //let delegate = AuthorizeUserDelegate(parentController: viewController)
        //delegate.launchGetAccessToken()
        
        return true
    }
    
    func application(application: UIApplication, openURL url: NSURL, options: [String: AnyObject]) -> Bool {
        // TODO seems a little clunky of a dispatcher...
        if (url.absoluteString.hasPrefix("amzn")) {
            return AIMobileLib.handleOpenURL(url, sourceApplication: options[UIApplicationOpenURLOptionsSourceApplicationKey] as! String)
        } else if (url.absoluteString.hasPrefix("fb")) {
            return FBSDKApplicationDelegate.sharedInstance().application(application, openURL: url,
                sourceApplication: options[UIApplicationOpenURLOptionsSourceApplicationKey] as! String,
                annotation: options[UIApplicationOpenURLOptionsAnnotationKey])
        } else {
            return GIDSignIn.sharedInstance().handleURL(url,
                sourceApplication: options[UIApplicationOpenURLOptionsSourceApplicationKey] as! String,
                annotation: options[UIApplicationOpenURLOptionsAnnotationKey])
        }
    }
    
    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }
    
    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }
    
    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }
    
    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }
    
    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
    
    func signIn(signIn: GIDSignIn!, didSignInForUser user: GIDGoogleUser!, withError error: NSError!) {
        if (error == nil) {
            // Perform any operations on signed in user here.
            viewController.updateGoogleId(user.authentication.idToken)
            
        } else {
            NSLog("\(error.localizedDescription)")
        }
    }
    
    func signIn(signIn: GIDSignIn!, didDisconnectWithUser user:GIDGoogleUser!,
        withError error: NSError!) {
            // Perform any operations when the user disconnects from app here.
            // ...
    }
    
    func twitterLogin(session : TWTRSession) {
        viewController.updateTwitterId(session.authToken + ";" + session.authTokenSecret)
    }
    
    func session(session: WCSession, didReceiveMessage message: [String : AnyObject], replyHandler: ([String : AnyObject]) -> Void) {
        NSLog("session message " + message.description)
        if (message[AppGlobals.SESSION_ACTION] as! String == AppGlobals.GET_CREDENTIALS) {
            var taskResult : AWSTask!
            let sem = dispatch_semaphore_create(0)
            
            // HACK -- this should be in a callback function so update is correctly timed
            viewController.updateFacebookId(FBSDKAccessToken.currentAccessToken()?.tokenString)

            var logins = credentialsProvider.logins
            logins = [:]
            if (amazonToken != nil) {
                logins[AWSCognitoLoginProviderKey.LoginWithAmazon.rawValue] = amazonToken
            }
            if (googleToken != nil) {
                logins[AWSCognitoLoginProviderKey.Google.rawValue] = googleToken
            }
            if (twitterToken != nil) {
                logins[AWSCognitoLoginProviderKey.Twitter.rawValue] = twitterToken
            }
            if (facebookToken != nil) {
                logins[AWSCognitoLoginProviderKey.Facebook.rawValue] = facebookToken
            }
            credentialsProvider.logins = logins
            
            credentialsProvider.refresh().continueWithBlock {
                (task: AWSTask!) -> AWSTask! in
                taskResult = task
                dispatch_semaphore_signal(sem)
                return task
            }
            
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER)
            
            if (taskResult.error == nil) {
                let reply = [AppGlobals.CRED_COGNITO_KEY : self.credentialsProvider.identityId,
                    AppGlobals.CRED_ACCESS_KEY : self.credentialsProvider.accessKey,
                    AppGlobals.CRED_SECRET_KEY : self.credentialsProvider.secretKey,
                    AppGlobals.CRED_SESSION_KEY : self.credentialsProvider.sessionKey,
                    AppGlobals.CRED_EXPIRATION_KEY : self.credentialsProvider.expiration]
                replyHandler(reply)
            } else {
                NSLog("error fetching credentials: \(taskResult.error!.description)")
                replyHandler([:])
            }
        }
    }
    
    func clearCredentials() {
        NSLog("clear credentials...")
        credentialsProvider.clearKeychain()
        wcsession.sendMessage([AppGlobals.SESSION_ACTION : AppGlobals.CLEAR_CREDENTIALS], replyHandler: nil, errorHandler: nil)
    }
}

