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
import Foundation

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, GIDSignInDelegate, WCSessionDelegate, AIAuthenticationDelegate {
    static let AMZN_TOKEN_VALID_ESTIMATE_SEC = 3000.0
    
    var window: UIWindow?
    var viewController : ViewController!
    var infoPlist : NSDictionary!
    
    let wcsession = WCSession.default()
    
    // AWS plumbing
    var credentialsProvider : AWSCognitoCredentialsProvider!
    
    var auths : [ String : Any ] = [:]
    class AWSAuth {
        var token: String
        var expires: Date
        
        init(token : String, expires : Date) {
            self.token = token
            self.expires = expires
        }
    }
    var awsSem = DispatchSemaphore(value: 0)
    
    // some google sync...
    var googleSem = DispatchSemaphore(value: 0)
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]? = nil) -> Bool {
        
        // Override point for customization after application launch.
        
        let path = Bundle.main.path(forResource: "Info", ofType: "plist")!
        infoPlist = NSDictionary(contentsOfFile: path)
        
        viewController = self.window?.rootViewController as! ViewController
        
        // set up Cognito
        //AWSLogger.defaultLogger().logLevel = .Verbose
        
        credentialsProvider = AWSCognitoCredentialsProvider(
            regionType: AWSRegionType.usEast1, identityPoolId: infoPlist[AppGlobals.IDENTITY_POOL_ID_KEY] as! String)
        
        let defaultServiceConfiguration = AWSServiceConfiguration(
            region: AWSRegionType.usEast1, credentialsProvider: credentialsProvider)
        
        AWSServiceManager.default().defaultServiceConfiguration = defaultServiceConfiguration
        
        // amazon setup
        let delegate = AuthorizeUserDelegate(delegate: self)
        delegate.launchGetAccessToken()
        
        // google setup
        var configureError: NSError?
        GGLContext.sharedInstance().configureWithError(&configureError)
        assert(configureError == nil, "Error configuring Google services: \(configureError)")
        GIDSignIn.sharedInstance().delegate = self
        GIDSignIn.sharedInstance().signInSilently()
        
        // twitter setup
        Fabric.with([AWSCognito.self, Twitter.self])
        let store = Twitter.sharedInstance().sessionStore
        auths[AWSIdentityProviderTwitter] = store.session()
        
        // facebook setup
        FBSDKApplicationDelegate.sharedInstance().application(application, didFinishLaunchingWithOptions: launchOptions)
        
        // wake up session to watch
        wcsession.delegate = self
        wcsession.activate()
        
        NSLog("application initialized")
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        // TODO seems a little clunky of a dispatcher...
        if (url.absoluteString.hasPrefix("amzn")) {
            return AIMobileLib.handleOpen(url, sourceApplication: options[UIApplicationOpenURLOptionsKey.sourceApplication] as! String!)
        } else if (url.absoluteString.hasPrefix("fb")) {
            return FBSDKApplicationDelegate.sharedInstance().application(app, open: url,
                                                                         sourceApplication: options[UIApplicationOpenURLOptionsKey.sourceApplication] as! String!,
                                                                         annotation: options[UIApplicationOpenURLOptionsKey.annotation])
        } else {
            return GIDSignIn.sharedInstance().handle(url,
                                                     sourceApplication: options[UIApplicationOpenURLOptionsKey.sourceApplication] as! String,
                                                     annotation: options[UIApplicationOpenURLOptionsKey.annotation])
        }
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
    
    // amazon
    @objc func requestDidSucceed(_ apiResult: APIResult!) {
        NSLog("amazon: connect token")
        let token = apiResult.result as! String
        auths[AWSIdentityProviderLoginWithAmazon] = AWSAuth(token : token, expires : Date().addingTimeInterval(AppDelegate.AMZN_TOKEN_VALID_ESTIMATE_SEC)) // a little less than an hour
        awsSem.signal()
        genDisplay()
    }
    
    @objc func requestDidFail(_ errorResponse: APIError) {
        NSLog("amazon: connect failed=\(errorResponse.error.message)")
        auths.removeValue(forKey: AWSIdentityProviderLoginWithAmazon)
        awsSem.signal()
        //        let alertController = UIAlertController(title: "",
        //            message: "AccessToken:" + errorResponse.error.message,
        //            preferredStyle: .Alert)
        //        let defaultAction = UIAlertAction(title: "OK", style: .Default, handler: nil)
        //        alertController.addAction(defaultAction)
        //        viewController.presentViewController(alertController, animated: true, completion: nil)
        genDisplay()
    }
    
    // google
    func sign(_ signIn: GIDSignIn!, didSignInFor user: GIDGoogleUser!, withError error: Error!) {
        if (error == nil) {
            NSLog("google: connect for \(user.userID)")
            auths[AWSIdentityProviderGoogle] = user.authentication
            googleSem.signal()
        } else {
            NSLog("\(error.localizedDescription)")
            auths.removeValue(forKey: AWSIdentityProviderGoogle)
            googleSem.signal()
        }
        genDisplay()
    }
    
    // google
    func sign(_ signIn: GIDSignIn!, didDisconnectWith user:GIDGoogleUser!,
              withError error: Error!) {
        NSLog("google disconnect for \(user.userID)")
        auths.removeValue(forKey: AWSIdentityProviderGoogle)
        genDisplay()
    }
    
    // twitter
    func twitterLogin(_ session : TWTRSession) {
        NSLog("twitter: connect for \(session.userID)")
        auths[AWSIdentityProviderTwitter] = session
        genDisplay()
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        NSLog(String(format: "state=%d", activationState.rawValue))
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        NSLog("session did become inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        NSLog("session did deactivate")
    }
    
    // message from watch
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        NSLog("session message " + message.description)
        if (message[AppGlobals.SESSION_ACTION] as! String == AppGlobals.GET_CREDENTIALS) {
            var taskResult : AWSTask<AWSCredentials>!
            let sem = DispatchSemaphore(value: 0)
            let now = Date()
            
            var logins : [ String : Any ] = [:]
            
            // amazon
            do {
                let auth = auths[AWSIdentityProviderLoginWithAmazon] as? AWSAuth
                if (auth == nil || auth!.expires.compare(now) == ComparisonResult.orderedAscending) {
                    NSLog("amazon: trigger refresh...")
                    auths[AWSIdentityProviderLoginWithAmazon] = nil
                    awsSem = DispatchSemaphore(value: 0)
                    
                    let delegate = AuthorizeUserDelegate(delegate: self)
                    delegate.launchGetAccessToken()
                    
                    // wait up to 15 seconds
                    _ = awsSem.wait(timeout: DispatchTime.now() + Double(Int64(15 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC))
                }
                
                // load amazon auth
                if let authNew = auths[AWSIdentityProviderLoginWithAmazon] as? AWSAuth {
                    NSLog("amazon: refresh found token=\(authNew.token), expires=\(authNew.expires)")
                    logins[AWSIdentityProviderLoginWithAmazon] = authNew.token
                } else {
                    NSLog("amazon: refresh found no token")
                }
            }
            
            // google
            do {
                let auth = auths[AWSIdentityProviderGoogle] as? GIDAuthentication
                if (auth == nil || auth!.accessTokenExpirationDate.compare(now) == ComparisonResult.orderedAscending) {
                    // sync get google token
                    NSLog("google: trigger refresh...")
                    auths[AWSIdentityProviderGoogle] = nil
                    googleSem = DispatchSemaphore(value: 0)
                    DispatchQueue.main.async {
                        GIDSignIn.sharedInstance().signInSilently()
                    }
                    
                    // wait up to 15 seconds
                    _ = googleSem.wait(timeout: DispatchTime.now() + Double(Int64(15 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC))
                }
                
                // load google login
                if let authNew = auths[AWSIdentityProviderGoogle] as? GIDAuthentication {
                    NSLog("google: refresh found token=\(authNew.idToken), expires=\(authNew.idTokenExpirationDate)")
                    logins[AWSIdentityProviderGoogle] = authNew.idToken
                } else {
                    NSLog("google: refresh found no token")
                }
            }
            
            // twitter -- no expire
            do {
                // load twitter login
                if let authNew = auths[AWSIdentityProviderTwitter] as? TWTRSession {
                    NSLog("twitter: refresh found token=\(authNew.authToken)")
                    let value = authNew.authToken + ";" + authNew.authTokenSecret
                    logins[AWSIdentityProviderTwitter] = value
                } else {
                    NSLog("twitter: no authToken found")
                }
            }
            
            // facebook -- no expire
            do {
                if let token = FBSDKAccessToken.current()?.tokenString {
                    NSLog("facebook: refresh found token=\(token)")
                    logins[AWSIdentityProviderFacebook] = token
                } else {
                    NSLog("facebook: refresh found no token")
                }
            }
            
            // updated list of logins
            let providerManager = CognitoCustomProviderManager(tokens: logins)
            credentialsProvider.setIdentityProviderManagerOnce(providerManager)
            credentialsProvider.credentials().continue({
                (task:AWSTask<AWSCredentials>) -> AnyObject? in
                taskResult = task
                sem.signal()
                return task
            })
            
            _ = sem.wait(timeout: DispatchTime.distantFuture)
            
            if (taskResult.error == nil) {
                let credentials = taskResult.result!
                NSLog("logins[\(logins)], expiration[\(credentials.expiration)], accessKey[\(credentials.accessKey)], secretKey[\(credentials.secretKey)], sessionKey[\(credentials.sessionKey)]")
                
                let reply = [AppGlobals.CRED_COGNITO_KEY : credentialsProvider.identityId!,
                             AppGlobals.CRED_ACCESS_KEY : credentials.accessKey,
                             AppGlobals.CRED_SECRET_KEY : credentials.secretKey,
                             AppGlobals.CRED_SESSION_KEY : credentials.sessionKey!,
                             AppGlobals.CRED_EXPIRATION_KEY : credentials.expiration!] as [String : Any]
                replyHandler(reply)
            } else {
                NSLog("error fetching credentials: \(taskResult.error!.localizedDescription)")
                viewController.updateErrorState(taskResult.error!.localizedDescription)
                replyHandler([:])
            }
        }
    }
    
    func clearCredentials() {
        NSLog("clear credentials...")
        credentialsProvider.clearKeychain()
        auths = [:]
        wcsession.sendMessage([AppGlobals.SESSION_ACTION : AppGlobals.CLEAR_CREDENTIALS], replyHandler: nil, errorHandler: nil)
        genDisplay()
    }
    
    func genDisplay() {
        var amznTime = ""
        var googTime = ""
        var twtrTime = ""
        var fbTime = ""
        
        if let amzn = auths[AWSIdentityProviderLoginWithAmazon] as? AWSAuth {
            amznTime = amzn.expires.description
        }
        if let goog = auths[AWSIdentityProviderGoogle] as? GIDAuthentication {
            googTime = goog.accessTokenExpirationDate.description
        }
        if auths[AWSIdentityProviderTwitter] != nil {
            twtrTime = "valid"
        }
        if FBSDKAccessToken.current()?.tokenString != nil {
            fbTime = FBSDKAccessToken.current().expirationDate.description
        }
        
        viewController.updateLoginState(amznTime, goog: googTime, twtr: twtrTime, fb: fbTime)
    }
}

