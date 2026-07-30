// Consolidated Hierarchical Hostel Model
// Combined from admin and core models to resolve type conflicts

class HierarchicalHostel {
  final dynamic id;
  final String name;
  final String createdAt;
  final String campus;
  final String type;
  final String buildingCode;
  final int summaryZoneCount;
  final int summaryRoomCount;
  final List<Zone> zones;

  HierarchicalHostel({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.campus,
    required this.type,
    required this.buildingCode,
    this.summaryZoneCount = 0,
    this.summaryRoomCount = 0,
    required this.zones,
  });

  factory HierarchicalHostel.fromJson(Map<String, dynamic> json) {
    var zonesList = (json['zones'] as List?)
            ?.map((zone) => Zone.fromJson(zone))
            .toList() ??
        [];
    return HierarchicalHostel(
      id: json['id'],
      name: json['name'] ?? json['hostel_name'] ?? '',
      createdAt: json['created_at'] ?? '',
      campus: json['campus'] ?? '',
      type: json['hostel_type'] ?? '',
      buildingCode: json['building_code'] ?? '',
      summaryZoneCount: json['zone_count'] ?? 0,
      summaryRoomCount: json['room_count'] ?? 0,
      zones: zonesList,
    );
  }

  // Use summary counts if zones list is empty (shallow load), else calculate from list
  int get totalZones => zones.isNotEmpty ? zones.length : summaryZoneCount;
  int get totalSubZones => zones.fold(0, (sum, zone) => sum + zone.subZones.length);
  int get totalRooms => zones.isNotEmpty 
    ? zones.fold(0, (sum, zone) => zone.subZones.fold(0, (sum, subZone) => sum + subZone.rooms.length))
    : summaryRoomCount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HierarchicalHostel && 
      (other.id?.toString() == id?.toString() || other.name.toLowerCase() == name.toLowerCase());
  }

  @override
  int get hashCode => name.toLowerCase().hashCode;
}

class Zone {
  final dynamic id;
  final dynamic hostelId;
  String name;
  String code;
  final String createdAt;
  final List<SubZone> subZones;

  Zone({
    required this.id,
    required this.hostelId,
    required this.name,
    required this.code,
    required this.createdAt,
    required this.subZones,
  });

  factory Zone.fromJson(Map<String, dynamic> json) {
    var subZonesList = (json['subZones'] as List?)
            ?.map((subZone) => SubZone.fromJson(subZone))
            .toList() ??
        [];
    return Zone(
      id: json['id'],
      hostelId: json['hostel_id'],
      name: json['name'] ?? '',
      code: json['code'] ?? json['name'] ?? '',
      createdAt: json['created_at'] ?? '',
      subZones: subZonesList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'hostel_id': hostelId,
      'name': name,
      'code': code,
      'subZones': subZones.map((sz) => sz.toJson()).toList(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Zone && 
      (other.name.trim().toLowerCase() == name.trim().toLowerCase() ||
       (other.id != null && id != null && other.id.toString() == id.toString()));
  }

  @override
  int get hashCode => name.trim().toLowerCase().hashCode;
}

class SubZone {
  final dynamic id;
  final dynamic zoneId;
  String name;
  String code;
  final String createdAt;
  final List<Room> rooms;

  SubZone({
    required this.id,
    required this.zoneId,
    required this.name,
    required this.code,
    required this.createdAt,
    required this.rooms,
  });

  factory SubZone.fromJson(Map<String, dynamic> json) {
    var roomsList = (json['rooms'] as List?)
            ?.map((room) => Room.fromJson(room))
            .toList() ??
        [];
    return SubZone(
      id: json['id'],
      zoneId: json['zone_id'],
      name: json['name'] ?? '',
      code: json['code'] ?? json['name'] ?? '',
      createdAt: json['created_at'] ?? '',
      rooms: roomsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'zone_id': zoneId,
      'name': name,
      'code': code,
      'rooms': rooms.map((r) => r.toJson()).toList(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SubZone && 
      (other.name.trim().toLowerCase() == name.trim().toLowerCase() ||
       (other.id != null && id != null && other.id.toString() == id.toString()));
  }

  @override
  int get hashCode => name.trim().toLowerCase().hashCode;

  int get totalRooms => rooms.length;
}

class Room {
  final dynamic id;
  final dynamic subZoneId;
  String roomNumber;
  String roomCode;
  int capacity;
  int availableRooms;
  String floorLabel;
  double amount;
  String facility;
  final String createdAt;

  Room({
    required this.id,
    required this.subZoneId,
    required this.roomNumber,
    required this.roomCode,
    required this.capacity,
    this.availableRooms = 0,
    required this.floorLabel,
    this.amount = 0.0,
    this.facility = 'AC',
    required this.createdAt,
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    return Room(
      id: json['id'],
      subZoneId: json['sub_zone_id'],
      roomNumber: json['room_number'] ?? json['room_no'] ?? '',
      roomCode: json['room_code'] ?? '',
      capacity: int.parse((json['capacity'] ?? json['total_capacity'] ?? 0).toString()),
      availableRooms: int.parse((json['available_rooms'] ?? json['available'] ?? 0).toString()),
      floorLabel: json['floor_label'] ?? json['floor'] ?? '',
      amount: double.parse((json['amount'] ?? 0.0).toString()),
      facility: json['facility'] ?? 'AC',
      createdAt: json['created_at'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sub_zone_id': subZoneId,
      'room_number': roomNumber,
      'room_code': roomCode,
      'capacity': capacity,
      'floor_label': floorLabel,
      'amount': amount,
      'facility': facility,
    };
  }
  
  // Compatibility getters for core model
  String get number => roomNumber;
  String get floor => floorLabel;
}

// Old model kept for compatibility in some screens
class HostelModel {
  String id;
  String name;
  List<Zone> zones;
  String? assignedWarden;

  HostelModel({
    required this.id,
    required this.name,
    required this.zones,
    this.assignedWarden,
  });

  int get totalRooms {
    return zones.fold(0, (sum, zone) => 
      sum + zone.subZones.fold(0, (subSum, subZone) => subSum + subZone.rooms.length));
  }

  int get totalZones => zones.length;

  int get totalSubZones {
    return zones.fold(0, (sum, zone) => sum + zone.subZones.length);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'zones': zones.map((z) => z.toJson()).toList(),
      'assignedWarden': assignedWarden,
    };
  }

  factory HostelModel.fromJson(Map<String, dynamic> json) {
    return HostelModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      zones: (json['zones'] as List?)?.map((z) => Zone.fromJson(z)).toList() ?? [],
      assignedWarden: json['assignedWarden'],
    );
  }
}
