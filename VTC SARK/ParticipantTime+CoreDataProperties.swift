//
//  ParticipantTime+CoreDataProperties.swift
//  VTC SARK
//
//  Created by Raoul Brahim on 23-05-2025.
//
//

import Foundation
import CoreData


extension ParticipantTime {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ParticipantTime> {
        return NSFetchRequest<ParticipantTime>(entityName: "ParticipantTime")
    }

    @NSManaged public var participant_id: Int16
    @NSManaged public var checkpoint_id: Int16
    @NSManaged public var timestamp: Date?

}

extension ParticipantTime : Identifiable {

}
