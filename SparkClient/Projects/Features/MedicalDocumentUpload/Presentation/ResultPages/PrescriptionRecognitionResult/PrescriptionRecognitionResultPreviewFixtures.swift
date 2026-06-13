#if DEBUG
import Foundation

enum PrescriptionRecognitionResultPreviewFixtures {
    static let prescriptionDrafts: [PrescriptionRecognitionDraft] = {
        decodePrescriptionDrafts(from: prescriptionDraftsJSON)
    }()

    static let familyMedicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox] = {
        decodeFamilyMedicineBoxes(from: familyMedicineBoxesJSON)
    }()

    private static func decodePrescriptionDrafts(from json: String) -> [PrescriptionRecognitionDraft] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([PrescriptionRecognitionDraft].self, from: data)) ?? []
    }

    private static func decodeFamilyMedicineBoxes(from json: String) -> [SparkMedicalSyncAPI.RemoteMedicineBox] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder.medicalAPI.decode([SparkMedicalSyncAPI.RemoteMedicineBox].self, from: data)) ?? []
    }

    private static let prescriptionDraftsJSON = """
    [
      {
        "prescriberName": null,
        "institutionName": "苏州大学附属第四医院",
        "prescribedAt": "2026-04-20",
        "diagnosis": "结膜炎",
        "prescriptionNo": null,
        "status": null,
        "extra": {},
        "medicationPlans": [
          {
            "medicineName": "普拉洛芬滴眼液",
            "medicineType": null,
            "brandName": "普南扑灵",
            "dosageForm": "滴眼液",
            "strength": "5ml:5mg",
            "doseUnit": null,
            "totalQuantity": "1盒",
            "expireDate": null,
            "dosePerTime": "1滴",
            "doseValue": "1",
            "frequencyType": "daily",
            "frequencyText": "每日四次",
            "startDate": null,
            "endDate": null,
            "instructions": "滴眼",
            "reminderTimes": [
              { "time": "08:00", "dose": null },
              { "time": "12:00", "dose": null },
              { "time": "16:00", "dose": null },
              { "time": "20:00", "dose": null }
            ],
            "medicineBox": {
              "medicineName": "普拉洛芬滴眼液",
              "medicineType": null,
              "brandName": "普南扑灵",
              "dosageForm": "滴眼液",
              "strength": "5ml:5mg",
              "doseUnit": null,
              "totalQuantity": "1盒",
              "expireDate": null,
              "notes": null,
              "extra": {}
            },
            "status": "active",
            "extra": {},
            "sortOrder": "0"
          },
          {
            "medicineName": "盐酸氮卓斯汀滴眼液",
            "medicineType": null,
            "brandName": "爱赛平",
            "dosageForm": "滴眼液",
            "strength": "6ml:3mg",
            "doseUnit": null,
            "totalQuantity": "1盒",
            "expireDate": null,
            "dosePerTime": "1滴",
            "doseValue": "1",
            "frequencyType": "daily",
            "frequencyText": "每日两次",
            "startDate": null,
            "endDate": null,
            "instructions": "滴眼。开瓶后，使用不可超过四周。",
            "reminderTimes": [
              { "time": "08:00", "dose": null },
              { "time": "20:00", "dose": null }
            ],
            "medicineBox": {
              "medicineName": "盐酸氮卓斯汀滴眼液",
              "medicineType": null,
              "brandName": "爱赛平",
              "dosageForm": "滴眼液",
              "strength": "6ml:3mg",
              "doseUnit": null,
              "totalQuantity": "1盒",
              "expireDate": null,
              "notes": null,
              "extra": {}
            },
            "status": "active",
            "extra": {},
            "sortOrder": "1"
          }
        ]
      },
      {
        "prescriberName": null,
        "institutionName": "东部战区总医院",
        "prescribedAt": "2025-06-27",
        "diagnosis": "高血压、高脂血症、腔隙性脑梗死、失眠",
        "prescriptionNo": "2025062700326476",
        "status": null,
        "extra": {},
        "medicationPlans": [
          {
            "medicineName": "阿托伐他汀钙片",
            "medicineType": "慢病用药",
            "brandName": null,
            "dosageForm": "片剂",
            "strength": "20mg",
            "doseUnit": null,
            "totalQuantity": "4盒",
            "expireDate": null,
            "dosePerTime": "1片",
            "doseValue": "1",
            "frequencyType": "daily",
            "frequencyText": "每晚一次",
            "startDate": null,
            "endDate": null,
            "instructions": "20mg（1片）口服",
            "reminderTimes": [
              { "time": "20:00", "dose": null }
            ],
            "medicineBox": {
              "medicineName": "阿托伐他汀钙片",
              "medicineType": "慢病用药",
              "brandName": null,
              "dosageForm": "片剂",
              "strength": "20mg",
              "doseUnit": null,
              "totalQuantity": "4盒",
              "expireDate": null,
              "notes": null,
              "extra": {}
            },
            "status": "active",
            "extra": {},
            "sortOrder": "0"
          },
          {
            "medicineName": "硫酸氢氯吡格雷片",
            "medicineType": "慢病用药",
            "brandName": null,
            "dosageForm": "片剂",
            "strength": "75mg",
            "doseUnit": null,
            "totalQuantity": null,
            "expireDate": null,
            "dosePerTime": "3片",
            "doseValue": "3",
            "frequencyType": "daily",
            "frequencyText": "每日一次",
            "startDate": null,
            "endDate": null,
            "instructions": "93.75mg（3片）口服",
            "reminderTimes": [
              { "time": "08:00", "dose": null }
            ],
            "medicineBox": {
              "medicineName": "硫酸氢氯吡格雷片",
              "medicineType": "慢病用药",
              "brandName": null,
              "dosageForm": "片剂",
              "strength": "75mg",
              "doseUnit": null,
              "totalQuantity": null,
              "expireDate": null,
              "notes": null,
              "extra": {}
            },
            "status": "active",
            "extra": {},
            "sortOrder": "1"
          },
          {
            "medicineName": "甲磺酸倍他司汀片",
            "medicineType": null,
            "brandName": "卫材",
            "dosageForm": "片剂",
            "strength": "6mg",
            "doseUnit": null,
            "totalQuantity": "1盒",
            "expireDate": null,
            "dosePerTime": "2片",
            "doseValue": "2",
            "frequencyType": "daily",
            "frequencyText": "每日三次",
            "startDate": null,
            "endDate": null,
            "instructions": "12mg（2片）口服",
            "reminderTimes": [
              { "time": "08:00", "dose": null },
              { "time": "12:00", "dose": null },
              { "time": "18:00", "dose": null }
            ],
            "medicineBox": {
              "medicineName": "甲磺酸倍他司汀片",
              "medicineType": null,
              "brandName": "卫材",
              "dosageForm": "片剂",
              "strength": "6mg",
              "doseUnit": null,
              "totalQuantity": "1盒",
              "expireDate": null,
              "notes": null,
              "extra": {}
            },
            "status": "active",
            "extra": {},
            "sortOrder": "2"
          }
        ]
      }
    ]
    """

    private static let familyMedicineBoxesJSON = """
    [
      {
        "id": 173,
        "user": 630,
        "member": 459,
        "medicine_type": null,
        "medicine_name": "盐酸氮卓斯汀滴眼液",
        "brand_name": "爱赛平",
        "dosage_form": "滴眼液",
        "strength": "6ml:3mg (0.05%)",
        "dose_unit": "片",
        "total_quantity": 1.0,
        "expire_date": null,
        "notes": "开瓶封后，使用不可超过四周",
        "extra": { "source": "typed_upload" },
        "attachments": [],
        "created_at": "2026-06-13T10:53:46.346678+08:00",
        "updated_at": "2026-06-13T10:53:46.346701+08:00"
      },
      {
        "id": 172,
        "user": 630,
        "member": 459,
        "medicine_type": null,
        "medicine_name": "普拉洛芬滴眼液",
        "brand_name": "普南扑灵",
        "dosage_form": "滴眼液",
        "strength": "5ml:5mg",
        "dose_unit": "片",
        "total_quantity": 1.0,
        "expire_date": null,
        "notes": "",
        "extra": { "source": "typed_upload" },
        "attachments": [],
        "created_at": "2026-06-13T10:53:46.329729+08:00",
        "updated_at": "2026-06-13T10:53:46.329745+08:00"
      }
    ]
    """
}
#endif
