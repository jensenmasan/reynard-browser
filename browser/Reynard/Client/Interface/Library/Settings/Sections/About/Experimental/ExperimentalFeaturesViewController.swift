//
//  ExperimentalFeaturesViewController.swift
//  Reynard
//
//  Created by Minh Ton on 19/7/26.
//

import UIKit

final class ExperimentalFeaturesViewController: SettingsTableViewController {
    private enum Section: CaseIterable {
        case webCapabilities
        
        var text: SettingsSectionText {
            switch self {
            case .webCapabilities:
                return SettingsSectionText(
                    headerTitle: NSLocalizedString("Web Capabilities", comment: "Experimental settings section title"),
                    footerTitle: NSLocalizedString("These switches change how websites are allowed to interact with this device.", comment: "")
                )
            }
        }
    }
    
    private enum Row: CaseIterable {
        case webMIDI
        case confirmBeforeLeaving
        
        var title: String {
            switch self {
            case .webMIDI:
                return NSLocalizedString("Web MIDI", comment: "")
            case .confirmBeforeLeaving:
                return NSLocalizedString("Confirm Before Leaving", comment: "")
            }
        }
        
        var subtitle: String {
            switch self {
            case .webMIDI:
                return NSLocalizedString("Let sites use your connected MIDI devices.", comment: "")
            case .confirmBeforeLeaving:
                return NSLocalizedString("Ask before leaving a page with unsaved changes.", comment: "")
            }
        }
    }
    
    private let webMIDISwitch = UISwitch()
    private let confirmBeforeLeavingSwitch = UISwitch()
    
    init() {
        super.init(style: .insetGrouped)
        title = NSLocalizedString("Experimental Features", comment: "")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        webMIDISwitch.addTarget(self, action: #selector(webMIDISwitchDidChange(_:)), for: .valueChanged)
        confirmBeforeLeavingSwitch.addTarget(self, action: #selector(confirmBeforeLeavingSwitchDidChange(_:)), for: .valueChanged)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        webMIDISwitch.isOn = Prefs.ExperimentalSettings.webMIDIEnabled
        confirmBeforeLeavingSwitch.isOn = Prefs.ExperimentalSettings.confirmBeforeLeaving
        tableView.reloadData()
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard Section.allCases.indices.contains(section) else {
            return 0
        }
        return Row.allCases.count
    }
    
    override func sectionText(for section: Int) -> SettingsSectionText {
        guard Section.allCases.indices.contains(section) else {
            return SettingsSectionText()
        }
        return Section.allCases[section].text
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard Section.allCases.indices.contains(indexPath.section),
              Row.allCases.indices.contains(indexPath.row) else {
            return UITableViewCell()
        }
        
        let row = Row.allCases[indexPath.row]
        let cell = SettingsTableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.text = row.title
        cell.detailTextLabel?.text = row.subtitle
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryView = row == .webMIDI ? webMIDISwitch : confirmBeforeLeavingSwitch
        return cell
    }
    
    // MARK: - Actions
    
    @objc private func webMIDISwitchDidChange(_ sender: UISwitch) {
        Prefs.ExperimentalSettings.webMIDIEnabled = sender.isOn
        RuntimePreferences.applyWebMIDI()
    }
    
    @objc private func confirmBeforeLeavingSwitchDidChange(_ sender: UISwitch) {
        Prefs.ExperimentalSettings.confirmBeforeLeaving = sender.isOn
        RuntimePreferences.applyLeaveConfirmation()
    }
}
