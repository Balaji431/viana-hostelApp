class RoomChangeRequest {
  final String requestId;
  final int studentId;
  final String studentName;
  final String studentRegNo;
  final String currentRoom;
  final String requestedRoom;
  final String reason;
  final String status; // pending, approved, rejected, completed
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? processedBy;
  final String? remarks;
  final DateTime? reservedUntil;
  final String? paymentStatus;
  final String? requestedRoomType;
  final double? amountToPay;
  final String? campus;

  RoomChangeRequest({
    required this.requestId,
    required this.studentId,
    required this.studentName,
    required this.studentRegNo,
    required this.currentRoom,
    required this.requestedRoom,
    required this.reason,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.processedBy,
    this.remarks,
    this.reservedUntil,
    this.paymentStatus,
    this.requestedRoomType,
    this.amountToPay,
    this.campus,
  });

  factory RoomChangeRequest.fromJson(Map<String, dynamic> json) {
    final reqRoom = (json['requested_room'] ?? '').toString().toUpperCase();
    final curRoom = (json['current_room'] ?? '').toString().toUpperCase();
    final reason = (json['reason'] ?? '').toString().toLowerCase();
    final bool isPoonamallee = reqRoom.startsWith('P-') ||
        reqRoom.startsWith('P0') ||
        reqRoom.startsWith('P1') ||
        curRoom.startsWith('P-') ||
        curRoom.startsWith('P0') ||
        curRoom.startsWith('P1') ||
        reason.contains('radiance') ||
        reason.contains('stunner');

    return RoomChangeRequest(
      requestId: json['request_id'] ?? '',
      studentId: json['student_id'] ?? 0,
      studentName: json['student_name'] ?? '',
      studentRegNo: json['student_reg_no'] ?? '',
      currentRoom: json['current_room'] ?? '',
      requestedRoom: json['requested_room'] ?? '',
      reason: json['reason'] ?? '',
      status: json['status'] ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updated_at'] ?? DateTime.now().toIso8601String()),
      processedBy: json['processed_by'] != null ? json['processed_by'] as int? : null,
      remarks: json['remarks'],
      reservedUntil: json['reserved_until'] != null ? DateTime.tryParse(json['reserved_until'].toString()) : null,
      paymentStatus: json['payment_status'],
      requestedRoomType: json['requested_room_type'],
      amountToPay: json['amount_to_pay'] != null ? double.tryParse(json['amount_to_pay'].toString()) : null,
      campus: json['campus'] ?? (isPoonamallee ? 'Poonamallee Campus' : 'Thandalam Campus'),
    );
  }

  RoomChangeRequest copyWith({
    String? requestId,
    int? studentId,
    String? studentName,
    String? studentRegNo,
    String? currentRoom,
    String? requestedRoom,
    String? reason,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? processedBy,
    String? remarks,
    String? requestedRoomType,
    String? campus,
  }) {
    return RoomChangeRequest(
      requestId: requestId ?? this.requestId,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      studentRegNo: studentRegNo ?? this.studentRegNo,
      currentRoom: currentRoom ?? this.currentRoom,
      requestedRoom: requestedRoom ?? this.requestedRoom,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      processedBy: processedBy ?? this.processedBy,
      remarks: remarks ?? this.remarks,
      requestedRoomType: requestedRoomType ?? this.requestedRoomType,
      amountToPay: amountToPay,
      paymentStatus: paymentStatus,
      reservedUntil: reservedUntil,
      campus: campus ?? this.campus,
    );
  }

  @override
  String toString() {
    return 'RoomChangeRequest(id: $requestId, student: $studentName, $currentRoom → $requestedRoom)';
  }
}
