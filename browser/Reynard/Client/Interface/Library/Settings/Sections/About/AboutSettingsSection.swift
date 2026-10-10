//
//  AboutSettingsSection.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import GeckoView
import UIKit

final class AboutSettingsSection {
    enum Row: CaseIterable {
        case experimentalFeatures
        case appVersion
        case engineVersion
    }
    
    private var showsExperimentalFeatures = false
    
    private var displayedRows: [Row] {
        return Row.allCases.filter {
            showsExperimentalFeatures || $0 != .experimentalFeatures
        }
    }
    
    var rowCount: Int {
        return displayedRows.count
    }
    
    func revealExperimentalFeatures() -> Bool {
        guard !showsExperimentalFeatures else {
            return false
        }
        showsExperimentalFeatures = true
        return true
    }
    
    func isAppVersionRow(at index: Int) -> Bool {
        return displayedRows.indices.contains(index) &&
        displayedRows[index] == .appVersion
    }
    
    func cell(at index: Int) -> UITableViewCell {
        guard displayedRows.indices.contains(index) else {
            return UITableViewCell()
        }
        
        switch displayedRows[index] {
        case .experimentalFeatures:
            return SettingsViewUtils.disclosureCell(title: "Experimental Features")
        case .appVersion:
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
            let build = info?["CFBundleVersion"] as? String ?? "Unknown"
            return valueCell(title: NSLocalizedString("马老师专属", comment: ""), value: "\(version) (\(build))")
        case .engineVersion:
            return valueCell(title: NSLocalizedString("Engine Version", comment: ""), value: GeckoRuntime.version)
        }
    }
    
    func selectRow(at index: Int, from viewController: UIViewController) {
        guard displayedRows.indices.contains(index) else {
            return
        }
        
        let row = displayedRows[index]
        if row == .experimentalFeatures {
            viewController.navigationController?.pushViewController(
                ExperimentalFeaturesViewController(),
                animated: true
            )
            return
        }
    }
    
    private func valueCell(title: String, value: String) -> UITableViewCell {
        let cell = SettingsTableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.detailTextLabel?.text = value
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.selectionStyle = .none
        cell.accessoryType = .none
        cell.configureDetailTextCopying()
        return cell
    }
}
