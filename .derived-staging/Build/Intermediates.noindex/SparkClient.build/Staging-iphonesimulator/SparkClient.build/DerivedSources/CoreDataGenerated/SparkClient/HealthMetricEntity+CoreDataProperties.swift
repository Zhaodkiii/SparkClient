//
//  HealthMetricEntity+CoreDataProperties.swift
//  
//
//  Created by Dream 話 on 2026/4/3.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias HealthMetricEntityCoreDataPropertiesSet = NSSet

extension HealthMetricEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<HealthMetricEntity> {
        return NSFetchRequest<HealthMetricEntity>(entityName: "HealthMetricEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var profileID: UUID?
    @NSManaged public var type: String?
    @NSManaged public var value: Double
    @NSManaged public var unit: String?
    @NSManaged public var recordedAt: Date?
    @NSManaged public var note: String?

}

extension HealthMetricEntity : Identifiable {

}
