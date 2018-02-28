//
//  Git.swift
//  PRBuddy
//
//  Created by Chris Brind on 28/02/2018.
//  Copyright © 2018 DuckDuckGo, Inc. All rights reserved.
//

import Foundation

class Git {
    
    struct Progress {
        
        let command: String?
        let exitStatus: Int32?
        let progress: Double
        let finished: Bool
        
    }
    
    private struct Command {
        
        let dir: String
        let arguments: [String]
        
    }
    
    private var commands = [Command]()
    
    let xcodePath: URL
    let checkoutDir: URL
    let project: String

    init(xcodePath: URL, checkoutDir: URL, project: String) {
        self.xcodePath = xcodePath
        self.checkoutDir = checkoutDir
        self.project = project
    }
    
    var checkoutPath: String {
        return String(checkoutDir.absoluteString.dropFirst("file://".count))
    }
    
    var projectPath: String {
        return "\(checkoutPath)/\(project)"
    }
    
    var gitPath: String {
        return String(xcodePath.absoluteString.dropFirst("file://".count))
    }
    
    func clone(url: String) -> Git {
        commands.append(Command(dir: checkoutPath, arguments: [ "clone",  "--recursive", url ]))
        return self
    }
    
    func fetch(fromRepo repo: String, withRef ref: String) -> Git {
        commands.append(Command(dir: projectPath, arguments: [ "fetch",  repo, ref ]))
        return self
    }
    
    func checkout(branch: String, fromRef ref: String) -> Git {
        commands.append(Command(dir: projectPath, arguments: [ "checkout",  "-b", branch, ref ]))
        return self
    }

    func merge(branch localBranch: String) -> Git {
        commands.append(Command(dir: projectPath, arguments: [ "merge",  localBranch ]))
        return self
    }
    
    func pull(repoUrl: String, branch: String) -> Git {
        commands.append(Command(dir: projectPath, arguments: [ "pull",  repoUrl, branch ]))
        return self
    }
    
    func start(withProgressHandler handler: @escaping (Progress) -> ()) {
        next(progressHandler: handler)
    }
    
    private func next(progressHandler: @escaping (Progress) -> ()) {
        guard let command = commands.first else {
            progressHandler(Progress(command: nil, exitStatus: nil, progress: 1.0, finished: false))
            return
        }
        
        commands.remove(at: 0)
        
        let commandString = command.arguments.joined(separator: " ")
        let progress = 1.0 / Double(commands.count + 1)
        print(#function, progress)
        progressHandler(Progress(command: commandString, exitStatus: nil, progress: progress, finished: false))
        
        execute(command: command) { exitStatus in
            progressHandler(Progress(command: commandString, exitStatus: exitStatus, progress: progress, finished: exitStatus != 0))
            guard exitStatus == 0 else { return }
            self.next(progressHandler: progressHandler)
        }
        
    }
    
    private func execute(command: Command, completion: @escaping (Int32) -> ()) {
        
        let process = Process()
        process.launchPath = "\(gitPath)Contents/Developer/usr/bin/git"
        process.arguments = ["-C", command.dir ] + command.arguments
        process.terminationHandler = { process in
            completion(process.terminationStatus)
        }
        
        print("> \(process.launchPath!) \(process.arguments!.joined(separator: " "))")
        do {
           try process.run()
        } catch {
            print(#function, error.localizedDescription)
            completion(-1)
        }
        
    }
    
}
