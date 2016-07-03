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
class AppDelegate: UIResponder, UIApplicationDelegate, GIDSignInDelegate, WCSessionDelegate, AIAuthenticationDelegate {
    static let AMZN_TOKEN_VALID_ESTIMATE_SEC = 3000.0
    let REFRESH_LEAD_SEC = 300.0
    
    
    var window: UIWindow?
    var viewController : ViewController!
    var infoPlist : NSDictionary!
    
    let wcsession = WCSession.defaultSession()
    var sensorDynamoImpl : SensorDynamoImpl!
    
    private var userCredentials : NSDictionary = [:]
    
    // AWS plumbing
    var credentialsProvider : AWSCognitoCredentialsProvider!
    var auths : [ Int : AnyObject ] = [:]
    class AWSAuth {
        var token: String
        var expires: NSDate
        
        init(token : String, expires : NSDate) {
            self.token = token
            self.expires = expires
        }
    }
    var awsSem = dispatch_semaphore_create(0)
    
    // some google sync...
    var googleSem = dispatch_semaphore_create(0)
    
    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        // Override point for customization after application launch.
        
        let path = NSBundle.mainBundle().pathForResource("Info", ofType: "plist")!
        infoPlist = NSDictionary(contentsOfFile: path)
        
        viewController = self.window?.rootViewController as! ViewController
        
        sensorDynamoImpl = SensorDynamoImpl(appDelegate: self)
        
        // set up Cognito
        //AWSLogger.defaultLogger().logLevel = .Verbose
        
        credentialsProvider = AWSCognitoCredentialsProvider(
            regionType: AWSRegionType.USEast1, identityPoolId: infoPlist[AppGlobals.IDENTITY_POOL_ID_KEY] as! String)
        
        let defaultServiceConfiguration = AWSServiceConfiguration(
            region: AWSRegionType.USEast1, credentialsProvider: credentialsProvider)
        
        AWSServiceManager.defaultServiceManager().defaultServiceConfiguration = defaultServiceConfiguration
        
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
        auths[AWSCognitoLoginProviderKey.Twitter.rawValue] = store.session()
        
        // facebook setup
        FBSDKApplicationDelegate.sharedInstance().application(application, didFinishLaunchingWithOptions: launchOptions)
        
        // wake up session to watch
        wcsession.delegate = self
        wcsession.activateSession()
        
        NSLog("application initialized")
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
    
    // amazon
    @objc func requestDidSucceed(apiResult: APIResult!) {
        NSLog("amazon: connect token")
        let token = apiResult.result as! String
        auths[AWSCognitoLoginProviderKey.LoginWithAmazon.rawValue] = AWSAuth(token : token, expires : NSDate().dateByAddingTimeInterval(AppDelegate.AMZN_TOKEN_VALID_ESTIMATE_SEC)) // a little less than an hour
        dispatch_semaphore_signal(awsSem)
        genDisplay()
    }
    
    @objc func requestDidFail(errorResponse: APIError) {
        NSLog("amazon: connect failed=\(errorResponse.error.message)")
        auths.removeValueForKey(AWSCognitoLoginProviderKey.LoginWithAmazon.rawValue)
        dispatch_semaphore_signal(awsSem)
        //        let alertController = UIAlertController(title: "",
        //            message: "AccessToken:" + errorResponse.error.message,
        //            preferredStyle: .Alert)
        //        let defaultAction = UIAlertAction(title: "OK", style: .Default, handler: nil)
        //        alertController.addAction(defaultAction)
        //        viewController.presentViewController(alertController, animated: true, completion: nil)
        genDisplay()
    }
    
    // google
    func signIn(signIn: GIDSignIn!, didSignInForUser user: GIDGoogleUser!, withError error: NSError!) {
        if (error == nil) {
            NSLog("google: connect for \(user.userID)")
            auths[AWSCognitoLoginProviderKey.Google.rawValue] = user.authentication
            dispatch_semaphore_signal(googleSem)
        } else {
            NSLog("google: error=\(error.userInfo.description)")
            auths.removeValueForKey(AWSCognitoLoginProviderKey.Google.rawValue)
            dispatch_semaphore_signal(googleSem)
        }
        genDisplay()
    }
    
    // google
    func signIn(signIn: GIDSignIn!, didDisconnectWithUser user:GIDGoogleUser!,
                withError error: NSError!) {
        NSLog("google disconnect for \(user.userID)")
        auths.removeValueForKey(AWSCognitoLoginProviderKey.Google.rawValue)
        genDisplay()
    }
    
    // twitter
    func twitterLogin(session : TWTRSession) {
        NSLog("twitter: connect for \(session.userID)")
        auths[AWSCognitoLoginProviderKey.Twitter.rawValue] = session
        genDisplay()
    }
    
    func session(session: WCSession, didReceiveFile file: WCSessionFile) {
        NSLog("didReceiveFile=\(file.fileURL.description)")
        if let aStreamReader = StreamReader(path: file.fileURL.path!) {
            defer {
                // TODO flush entry (this is a left justified flush, not implemented in flushHandler right now...
                aStreamReader.close()
            }
            while let line = aStreamReader.nextLine() {
                // write entry
                do {
                    try sensorDynamoImpl.addSample(line)
                } catch SensorDynamoImpl.FlushException.NoCredentials {
                    NSLog("no credentials")
                    return // give up on this file for now
                } catch SensorDynamoImpl.FlushException.FlushError(let cause) {
                    NSLog("flush error: \(cause?.description)")
                    return
                } catch {
                    NSLog("unknown error")
                }
            }
        }
    }
    
    func getCredentials() -> NSDictionary {
        var refreshCredentials = false
        let expireTime = userCredentials[AppGlobals.CRED_EXPIRATION_KEY] as? NSDate
        if (expireTime == nil) {
            // no data at all so fetch and wait
            refreshCredentials = true
        } else {
            // data and expired so fetch and wait
            let now = NSDate()
            if (now.compare(expireTime!) == NSComparisonResult.OrderedDescending) {
                userCredentials = [:]
                refreshCredentials = true
            } else if (now.dateByAddingTimeInterval(REFRESH_LEAD_SEC).compare(expireTime!) == NSComparisonResult.OrderedDescending) {
                // nearing expiration so fetch [TODO no wait]
                refreshCredentials = true
            }
        }
        
        if (refreshCredentials) {
            NSLog("refreshing userCredentials...")
            let sem = dispatch_semaphore_create(0)
            var taskResult : AWSTask!
            let now = NSDate()
            
            var logins : [ NSObject : AnyObject ] = [:]
            
            // amazon
            do {
                let auth = auths[AWSCognitoLoginProviderKey.LoginWithAmazon.rawValue] as? AWSAuth
                if (auth == nil || auth!.expires.compare(now) == NSComparisonResult.OrderedAscending) {
                    NSLog("amazon: trigger refresh...")
                    auths.removeValueForKey(AWSCognitoLoginProviderKey.LoginWithAmazon.rawValue)
                    awsSem = dispatch_semaphore_create(0)
                    
                    let delegate = AuthorizeUserDelegate(delegate: self)
                    delegate.launchGetAccessToken()
                    
                    // wait up to 15 seconds
                    dispatch_semaphore_wait(awsSem, dispatch_time(
                        DISPATCH_TIME_NOW,
                        Int64(15 * Double(NSEC_PER_SEC))
                        ))
                }
                
                // load amazon auth
                if let authNew = auths[AWSCognitoLoginProviderKey.LoginWithAmazon.rawValue] as? AWSAuth {
                    NSLog("amazon: refresh found token=\(authNew.token), expires=\(authNew.expires)")
                    logins[AWSCognitoLoginProviderKey.LoginWithAmazon.rawValue] = authNew.token
                } else {
                    NSLog("amazon: refresh found no token")
                }
            }
            
            // google
            do {
                let auth = auths[AWSCognitoLoginProviderKey.Google.rawValue] as? GIDAuthentication
                if (auth == nil || auth!.accessTokenExpirationDate.compare(now) == NSComparisonResult.OrderedAscending) {
                    // sync get google token
                    NSLog("google: trigger refresh...")
                    auths.removeValueForKey(AWSCognitoLoginProviderKey.Google.rawValue)
                    googleSem = dispatch_semaphore_create(0)
                    GIDSignIn.sharedInstance().signInSilently()
                    
                    // wait up to 15 seconds
                    dispatch_semaphore_wait(googleSem, dispatch_time(
                        DISPATCH_TIME_NOW,
                        Int64(15 * Double(NSEC_PER_SEC))
                        ))
                }
                
                // load google login
                if let authNew = auths[AWSCognitoLoginProviderKey.Google.rawValue] as? GIDAuthentication {
                    NSLog("google: refresh found token=\(authNew.idToken), expires=\(authNew.idTokenExpirationDate)")
                    logins[AWSCognitoLoginProviderKey.Google.rawValue] = authNew.idToken
                } else {
                    NSLog("google: refresh found no token")
                }
            }
            
            // twitter -- no expire
            do {
                // load twitter login
                if let authNew = auths[AWSCognitoLoginProviderKey.Twitter.rawValue] as? TWTRSession {
                    NSLog("twitter: refresh found token=\(authNew.authToken)")
                    let value = authNew.authToken + ";" + authNew.authTokenSecret
                    logins[AWSCognitoLoginProviderKey.Twitter.rawValue] = value
                } else {
                    NSLog("twitter: no authToken found")
                }
            }
            
            // facebook -- no expire (well, is 60 days...)
            do {
                if let token = FBSDKAccessToken.currentAccessToken()?.tokenString {
                    NSLog("facebook: refresh found token=\(token)")
                    logins[AWSCognitoLoginProviderKey.Facebook.rawValue] = token
                } else {
                    NSLog("facebook: refresh found no token")
                }
            }
            
            // updated list of logins
            credentialsProvider.logins = logins
            
            credentialsProvider.refresh().continueWithBlock {
                (task: AWSTask!) -> AWSTask! in
                taskResult = task
                dispatch_semaphore_signal(sem)
                return task
            }
            
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER)
            
            NSLog("logins[\(credentialsProvider.logins)], expiration[\(credentialsProvider.expiration)], accessKey[\(credentialsProvider.accessKey)], secretKey[\(credentialsProvider.secretKey)], sessionKey[\(credentialsProvider.sessionKey)]")
            
            if (taskResult.error == nil) {
                userCredentials = [AppGlobals.CRED_COGNITO_KEY : self.credentialsProvider.identityId,
                                   AppGlobals.CRED_ACCESS_KEY : self.credentialsProvider.accessKey,
                                   AppGlobals.CRED_SECRET_KEY : self.credentialsProvider.secretKey,
                                   AppGlobals.CRED_SESSION_KEY : self.credentialsProvider.sessionKey,
                                   AppGlobals.CRED_EXPIRATION_KEY : self.credentialsProvider.expiration]
            } else {
                NSLog("error fetching credentials: \(taskResult.error!.userInfo.description)")
                viewController.updateErrorState(taskResult.error!.userInfo.description)
                userCredentials = [:]
            }
        }
        
        return userCredentials
    }
    
    func clearCredentials() {
        NSLog("clear credentials...")
        credentialsProvider.clearKeychain()
        userCredentials = [:]
        auths = [:]
        genDisplay()
    }
    
    func genDisplay() {
        var amznTime = ""
        var googTime = ""
        var twtrTime = ""
        var fbTime = ""
        
        if let amzn = auths[AWSCognitoLoginProviderKey.LoginWithAmazon.rawValue] as? AWSAuth {
            amznTime = amzn.expires.description
        }
        if let goog = auths[AWSCognitoLoginProviderKey.Google.rawValue] as? GIDAuthentication {
            googTime = goog.accessTokenExpirationDate.description
        }
        if auths[AWSCognitoLoginProviderKey.Twitter.rawValue] != nil {
            twtrTime = "valid"
        }
        if FBSDKAccessToken.currentAccessToken()?.tokenString != nil {
            fbTime = "valid"
        }
        
        viewController.updateLoginState(amznTime, goog: googTime, twtr: twtrTime, fb: fbTime)
    }
}

