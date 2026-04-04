//
//  UserProfileEntity+CoreDataProperties.swift
//  
//
//  Created by Dream 話 on 2026/4/3.
//
//  This file was automatically generated and should not be edited.
//

public import Foundation
public import CoreData


public typealias UserProfileEntityCoreDataPropertiesSet = NSSet

extension UserProfileEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<UserProfileEntity> {
        return NSFetchRequest<UserProfileEntity>(entityName: "UserProfileEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var email: String?
    @NSManaged public var displayName: String?
    @NSManaged public var isDemo: Bool
    @NSManaged public var createdAt: Date?
    @NSManaged public var lastSignedInAt: Date?

}

extension UserProfileEntity : Identifiable {

}
