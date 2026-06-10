import 'package:flutter/material.dart';
import '../core/api_service.dart';
import '../core/app_logger.dart';

class RequestItem {
  final String title;
  final String id;
  final String date;
  final String status;
  final bool isResolved;
  final int? rating;
  final String? comment;
  final String? purpose;
  final String? department;

  RequestItem({
    required this.title,
    required this.id,
    required this.date,
    required this.status,
    required this.isResolved,
    this.rating,
    this.comment,
    this.purpose,
    this.department,
  });
}

class RequestProvider with ChangeNotifier {
  List<RequestItem> _requests = [];
  bool _isLoading = false;

  List<RequestItem> get requests => [..._requests];
  bool get isLoading => _isLoading;

  Future<void> fetchRequests(int studentId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await ApiService.getStudentRequests(studentId);
      if (response['success'] == true) {
        final List<dynamic> data = response['data'];
        _requests = data.map((json) => RequestItem(
          title: json['request_type']?.toString() ?? 'Request',
          id: json['request_id']?.toString() ?? 'N/A',
          date: json['created_at']?.toString() ?? json['updated_at']?.toString() ?? 'N/A',
          status: json['status']?.toString() ?? 'pending',
          isResolved: (json['status']?.toString().toLowerCase() == 'approved' || json['status']?.toString().toLowerCase() == 'completed' || json['status']?.toString().toLowerCase() == 'rejected'),
          rating: int.tryParse(json['rating']?.toString() ?? ''),
          comment: json['comment']?.toString(),
          purpose: json['purpose']?.toString(),
          department: json['department']?.toString(),
        )).toList();
      }
    } catch (e) {
      AppLogger.error("Error fetching requests: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addRequest(RequestItem request) {
    _requests.insert(0, request);
    notifyListeners();
  }
}
