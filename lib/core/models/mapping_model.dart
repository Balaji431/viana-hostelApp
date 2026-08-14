class Staff {
  String id;
  String name;
  String role; 
  String phone;
  String username;
  String? hostelName;
  String? floorName;
  String? wingName;

  Staff({
    required this.id,
    required this.name,
    required this.role,
    required this.phone,
    required this.username,
    this.hostelName,
    this.floorName,
    this.wingName,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'staff_id': id, // Compatibility
      'name': name,
      'full_name': name,
      'role': role,
      'phone': phone,
      'username': username,
      'hostel_name': hostelName ?? '',
      'floor_name': floorName ?? '',
      'wing_name': wingName ?? '',
    };
  }

  factory Staff.fromJson(Map<String, dynamic> json) {
    return Staff(
      id: (json['id'] ?? json['staff_id'] ?? json['user_id'] ?? '').toString(),
      name: (json['name'] ?? json['full_name'] ?? json['username'] ?? 'Unknown').toString(),
      role: (json['role'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      hostelName: json['hostel_name']?.toString(),
      floorName: json['floor_name']?.toString(),
      wingName: json['wing_name']?.toString(),
    );
  }
}

class LocationMapping {
  String id;
  String hostelId;
  String? hostelName;
  String? zoneId; // Floor ID
  String? zoneName;
  String? subZoneId; // Wing ID
  String? subZoneName;
  String? roomId;
  int? roomCount;
  List<Staff> assignedStaff;

  LocationMapping({
    required this.id,
    required this.hostelId,
    this.hostelName,
    this.zoneId,
    this.zoneName,
    this.subZoneId,
    this.subZoneName,
    this.roomId,
    this.roomCount,
    required this.assignedStaff,
  });

  Map<String, dynamic> toJson() {
    final String hName = hostelName ?? '';
    final String fName = zoneName ?? zoneId ?? '';
    final String wName = subZoneName ?? subZoneId ?? 'All';

    return {
      'id': id,
      'hostel_id': int.tryParse(hostelId) ?? hostelId,
      'zone_id': fName,
      'sub_zone_id': wName,
      'staff': assignedStaff.map((s) {
        final Map<String, dynamic> sMap = s.toJson();
        if ((sMap['hostel_name'] ?? '').toString().isEmpty) sMap['hostel_name'] = hName;
        if ((sMap['floor_name'] ?? '').toString().isEmpty) sMap['floor_name'] = fName;
        if ((sMap['wing_name'] ?? '').toString().isEmpty) sMap['wing_name'] = wName;
        return sMap;
      }).toList(),
    };
  }

  factory LocationMapping.fromJson(Map<String, dynamic> json) {
    // zone_id and sub_zone_id in DB store the NAME strings, not numeric IDs
    final zoneVal = (json['zone_id'] ?? json['floor_id'] ?? '').toString();
    final subZoneVal = (json['sub_zone_id'] ?? json['wing_id'] ?? '').toString();
    return LocationMapping(
      id: (json['id'] ?? '').toString(),
      hostelId: (json['hostel_id'] ?? '').toString(),
      hostelName: json['hostel_name']?.toString() ?? json['hostel']?.toString(),
      zoneId: zoneVal,
      zoneName: json['zone_name']?.toString() ?? (zoneVal.isNotEmpty ? zoneVal : null),
      subZoneId: subZoneVal,
      subZoneName: json['sub_zone_name']?.toString() ?? (subZoneVal.isNotEmpty ? subZoneVal : null),
      roomId: json['room_id']?.toString(),
      roomCount: int.tryParse(json['room_count']?.toString() ?? '0') ?? 0,
      assignedStaff: json['staff'] != null 
          ? (json['staff'] as List).map((s) => Staff.fromJson(s)).toList()
          : [],
    );
  }
}
