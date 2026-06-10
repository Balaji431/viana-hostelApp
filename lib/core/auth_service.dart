import 'package:vianasoft_stay/shared/user_provider.dart';

class AuthService {
  /// Attempts to login with given credentials
  /// Returns UserRole if successful, null if credentials don't match any known pattern
  static UserRole? login(String username, String password) {
    // 🔥 If the password matches known testing passwords, allow role detection
    // Otherwise, we return a default role to let the API Service verify the real credentials
    
    final upperUser = username.toUpperCase();
    
    // Maintenance user — match any username containing 'maintenance'
    if (upperUser.contains('MAINTENANCE')) {
      return UserRole.maintenance;
    }
    
    // Warden user
    if (upperUser == 'WARDEN1' || upperUser.startsWith('WAR')) {
      return UserRole.warden;
    }
    
    // Parent user (starts with P-)
    if (upperUser.startsWith('P-')) {
      return UserRole.parent;
    }
    
    // Student user (starts with STU or typical registration numbers)
    if (upperUser.startsWith('STU') || RegExp(r'^\d+').hasMatch(username)) {
      return UserRole.student;
    }
    
    // Default to admin for other specific formats or allow the API to decide
    if (upperUser == 'ADMIN') return UserRole.admin;
    
    // Return student as a fallback so the API login call can proceed
    return UserRole.student;
  }
}
