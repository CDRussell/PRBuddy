//
//  AppDelegate.swift
//  PRBuddy
//
//  Created by Chris Brind on 23/02/2018.
//  Copyright © 2018 Chris Brind. All rights reserved.
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    let settings = AppSettings()
    let polling = GithubPolling()
    
    var windowController: NSWindowController!
    var item: NSStatusItem!
    
    var lastProgress: Git.Progress?
    var progressTimer: Timer?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        windowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("Main")) as? NSWindowController

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        updateStatus()
    
        NSUserNotificationCenter.default.delegate = self
        
        if settings.username == nil || settings.personalAccessToken == nil || settings.repos.isEmpty || settings.checkoutDir == nil {
            showWindowInFront()
        } else {
            polling.pollNow()
        }
    }
    
    func updateStatus() {
        buildMenu()
        resetStatus()

        var attention = [String]()
        
        if !polling.reviewsRequested.isEmpty {
            attention.append("\(settings.reviewRequested): \(polling.reviewsRequested.count)")
        }
        
        if !polling.assigned.isEmpty {
            attention.append("\(settings.assigned): \(polling.assigned.count)")
        }
        
        if !attention.isEmpty {
            item.button?.title = attention.joined(separator: " ")
        }
        
    }
    

    func resetStatus() {
        item.button?.title = "\(settings.noPRs) \(polling.allPullRequests.count)"
        item.button?.sizeToFit()
    }
    
    func buildMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "About PRBuddy", action: #selector(self.aboutPRBuddy), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Check now", action: #selector(self.checkNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        if polling.allPullRequests.count > 0 {
            let requested = polling.reviewsRequested
            let assigned = polling.assigned
            
            let others = polling.allPullRequests.subtracting(requested).subtracting(assigned)
            
            for pr in requested.sorted(by: { $0.repoName < $1.repoName }) {
                menu.addItem(createPRMenuItem(pr: pr, prefix: settings.reviewRequested))
            }
            
            for pr in assigned.sorted(by: { $0.repoName < $1.repoName }) {
                menu.addItem(createPRMenuItem(pr: pr, prefix: settings.assigned))
            }
            
            for pr in others.sorted(by: { $0.repoName < $1.repoName }) {
                menu.addItem(createPRMenuItem(pr: pr, prefix: ""))
            }
            
            menu.addItem(NSMenuItem.separator())
        }
        
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(self.showWindowInFront), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(self.quit), keyEquivalent: ""))
        item.menu = menu
    }
    
    @objc func showWindowInFront() {
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        windowController.window?.orderFrontRegardless()
    }

    @objc func quit() {
        NSApp.terminate(self)
    }
    
    @objc func openPullRequestURL(sender: PullRequestMenuItem) {
        print(#function, sender)
        NSWorkspace.shared.open(URL(string: sender.pr.html_url)!)
    }
    
    @objc func checkNow(sender: Any) {
        print(#function, sender)
        resetStatus()
        polling.stop()
        polling.start()
        polling.pollNow()
    }

    @objc func checkoutPullRequest(sender: PullRequestMenuItem) {
        print(#function, sender)
        
        guard let xcodePath = settings.xcodePath else { return }
        guard let checkoutDir = settings.checkoutDir else { return }

        guard xcodePath.startAccessingSecurityScopedResource() else { return }
        guard checkoutDir.startAccessingSecurityScopedResource() else {
            xcodePath.stopAccessingSecurityScopedResource()
            return
        }

        let tmpCheckoutDir = checkoutDir.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmpCheckoutDir, withIntermediateDirectories: true, attributes: [:])
        
        let headBranchName = sender.pr.head.label.replacingOccurrences(of: ":", with: "-")
        let projectName = sender.pr.base.repo.name

        polling.stop()
        updateBuildingStatus(description: "Starting")
        
        Git(xcodePath: xcodePath, checkoutDir: tmpCheckoutDir, project: projectName)
            .clone(url: sender.pr.base.repo.clone_url)
            .fetch(fromRepo: sender.pr.base.repo.clone_url, withRef: sender.pr.base.ref)
            .checkout(branch: headBranchName, fromRef: sender.pr.base.ref)
            .pull(repoUrl: sender.pr.head.repo.clone_url, branch: sender.pr.head.ref)
            .start { progress in
        
                print(#function, progress)
                
                self.lastProgress = progress
                
                DispatchQueue.main.async {
                    guard progress.finished else { return }

                    self.stopCheckoutProgress()
                    
                    print(#function, "Git finished")
                    
                    self.lastProgress = nil
                    self.resetStatus()
                    self.polling.pollNow()
                    self.polling.start()
                    
                    let projectDir = tmpCheckoutDir.appendingPathComponent(projectName)
                    let projectPath = String(projectDir.absoluteString.dropFirst("file://".count))

                    self.checkoutComplete(projectPath)
                    
                    xcodePath.stopAccessingSecurityScopedResource()
                    checkoutDir.stopAccessingSecurityScopedResource()
                }
        }
        
        startCheckoutProgress()
        
    }

    @objc func ignorePullRequest(sender: PullRequestMenuItem) {
        print(#function, sender)
        // TODO keep track of requests we're not interested in
    }

    @objc func aboutPRBuddy() {
        showWindowInFront()
        guard let controller = windowController.contentViewController as? SettingsViewController else { return }
        controller.showAbout()
    }
    
    private func checkoutComplete(_ projectPath: String) {
        NSPasteboard.general.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
        let pasteboardResult = NSPasteboard.general.setString(projectPath, forType: NSPasteboard.PasteboardType.fileURL)
        print(#function, "pasteboardResult", pasteboardResult)
        
        let notification = NSUserNotification()
        notification.identifier = UUID().uuidString
        notification.title = "PRBuddy"
        notification.subtitle = "Checkout complete"
        notification.informativeText = projectPath
        NSUserNotificationCenter.default.deliver(notification)
    }

    private func stopCheckoutProgress() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func startCheckoutProgress() {
        stopCheckoutProgress()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            self.updateBuildingStatus(description: self.lastProgress?.description ?? "Starting")
        }
    }
    
    private func updateBuildingStatus(description: String) {
        var progress = "💃"
        if item.button?.title.starts(with: "💃") ?? false {
            progress = "🕺"
        }
        item.button?.title = "\(progress) \(description)"
    }
    
    private func createPRMenuItem(pr: GithubPolling.GithubPullRequest, prefix: String) -> PullRequestMenuItem {
        let title = "\(prefix)\(pr.repoName): \(pr.title)"
        let menuItem = PullRequestMenuItem(title: title, action: #selector(self.openPullRequestURL), pr: pr)
        menuItem.submenu = NSMenu(title: "Actions")
        menuItem.submenu?.addItem(PullRequestMenuItem(title: "Open in Browser", action: #selector(self.openPullRequestURL), pr: pr))
        menuItem.submenu?.addItem(PullRequestMenuItem(title: "Checkout...", action: #selector(self.checkoutPullRequest), pr: pr))
        
        if prefix == settings.reviewRequested {
            menuItem.submenu?.addItem(PullRequestMenuItem(title: "Ignore", action: #selector(self.ignorePullRequest), pr: pr))
        }
        
        return menuItem
    }
    
    class var instance: AppDelegate {
        get {
            return NSApp.delegate as! AppDelegate
        }
    }
    
}

extension AppDelegate: NSUserNotificationCenterDelegate {
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, didDeliver notification: NSUserNotification) {
        print(#function, notification)
    }
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        print(#function, notification)
        
        guard let path = notification.informativeText else { return }
        print(#function, "path", path)
        
        NSPasteboard.general.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
        let pasteboardResult = NSPasteboard.general.setString(path, forType: NSPasteboard.PasteboardType.fileURL)
        print(#function, "pasteboardResult", pasteboardResult)
        
        
        if let url = settings.checkoutDir,
            url.startAccessingSecurityScopedResource() {
            NSWorkspace.shared.openFile(path, withApplication: "Terminal")
            url.stopAccessingSecurityScopedResource()
        }
        
    }
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        print(#function, notification)
        return true
    }
    
}

class PullRequestMenuItem: NSMenuItem {
    
    var pr: GithubPolling.GithubPullRequest!
    
    init(title string: String, action selector: Selector?, pr: GithubPolling.GithubPullRequest) {
        self.pr = pr
        super.init(title: string, action: selector, keyEquivalent: "")
    }
    
    required init(coder decoder: NSCoder) {
        super.init(coder: decoder)
    }
    
}

extension GithubPolling.GithubPullRequest {
    
    var repoName: String {
        return url.components(separatedBy: "/")[4...5].joined(separator: "/")
    }
    
}




