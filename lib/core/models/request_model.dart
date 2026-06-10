class RequestModel {
  final int id;
  final String customId;
  final int studentId;
  final String studentName;
  final String roomNumber;
  final String department;
  final String requestType;
  final String message;
  final String? destination;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String status;
  final DateTime createdAt;

  RequestModel({
    required this.id,
    required this.customId,
    required this.studentId,
    required this.studentName,
    required this.roomNumber,
    required this.department,
    required this.requestType,
    required this.message,
    this.destination,
    this.fromDate,
    this.toDate,
    required this.status,
    required this.createdAt,
  });

  factory RequestModel.fromJson(Map<String, dynamic> json) {
    return RequestModel(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      customId: json['request_id']?.toString() ?? 'WRD-000000',
      studentId: int.tryParse(json['student_id']?.toString() ?? '') ?? 0,
      studentName: json['student_name'] ?? 'Unknown Student',
      roomNumber: json['room_allocation'] ?? json['room_number'] ?? json['room_no'] ?? 'N/A',
      department: json['department'] ?? '',
      requestType: json['request_type'] ?? '',
      message: json['purpose'] ?? json['reason'] ?? json['message'] ?? 'No purpose provided',
      destination: json['destination'],
      fromDate: json['departure_date'] != null ? DateTime.tryParse(json['departure_date']) : (json['from_date'] != null ? DateTime.tryParse(json['from_date']) : null),
      toDate: json['return_date'] != null ? DateTime.tryParse(json['return_date']) : (json['to_date'] != null ? DateTime.tryParse(json['to_date']) : null),
      status: json['request_status']?.toString() ?? json['status']?.toString() ?? 'pending',
      createdAt: json['created_at'] != null ? (DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()) : DateTime.now(),
    );
  }
}
