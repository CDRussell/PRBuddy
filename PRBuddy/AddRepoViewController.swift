//
//  AddRepoViewController.swift
//  PRBuddy
//
//  Created by Chris Brind on 24/02/2018.
//  Copyright © 2018 Chris Brind. All rights reserved.
//

import Cocoa

protocol AddRepoViewControllerDelegate: class {
    
    func repoAdded(controller: AddRepoViewController)
    
}

class AddRepoViewController: NSViewController {
    
    @IBOutlet var repoField: NSTextField!
    @IBOutlet var addButton: NSButton!
    
    weak var delegate: AddRepoViewControllerDelegate?

    let settings = AppSettings()
    
    @IBAction func addRepo(sender: Any) {
        settings.repos.append(repoField.stringValue)
        delegate?.repoAdded(controller: self)
        dismiss(self)
    }
    
}

extension AddRepoViewController: NSTextFieldDelegate {
    
    override func controlTextDidChange(_ obj: Notification) {
        addButton.isEnabled = !repoField.stringValue.isEmpty && repoField.stringValue.contains("/")
    }
    
}
