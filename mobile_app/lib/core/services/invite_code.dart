import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/core/services/auth.dart';

class InviteCodeService {
  // static const String _baseUrl = "http://10.0.2.2:8000/invite-manager";
  static final String _baseUrl =
      "${dotenv.env['BACKEND_SERVER_URL']}/invite-manager";

  /// Generate a new invite code (Admin only)
  static Future<Map<String, dynamic>> generateInviteCode({
    String? restrictedEmail,
    String? restrictedRole,
    int maxUses = 1,
    int expiresInDays = 30,
  }) async {
    try {
      final token = await AuthService.authorize();
      final url = Uri.parse("$_baseUrl/generate");

      final Map<String, dynamic> body = {
        "max_uses": maxUses,
        "expires_in_days": expiresInDays,
      };

      if (restrictedEmail != null && restrictedEmail.isNotEmpty) {
        body["restricted_email"] = restrictedEmail;
      }

      if (restrictedRole != null && restrictedRole.isNotEmpty) {
        body["restricted_role"] = restrictedRole;
      }

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'Authorization': token},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 403) {
        throw Exception(
          "Access denied. Only admins can generate invite codes.",
        );
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? "Failed to generate invite code");
      }
    } catch (e) {
      throw Exception("Error generating invite code: $e");
    }
  }

  /// List all invite codes created by the current admin
  static Future<List<Map<String, dynamic>>> listMyInviteCodes() async {
    try {
      final token = await AuthService.authorize();
      final url = Uri.parse("$_baseUrl/list");

      final response = await http.get(url, headers: {'Authorization': token});

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else if (response.statusCode == 403) {
        throw Exception("Access denied. Only admins can view invite codes.");
      } else {
        throw Exception("Failed to fetch invite codes");
      }
    } catch (e) {
      throw Exception("Error fetching invite codes: $e");
    }
  }

  /// List all invite codes in the system (Admin only)
  static Future<List<Map<String, dynamic>>> listAllInviteCodes() async {
    try {
      final token = await AuthService.authorize();
      final url = Uri.parse("$_baseUrl/list/all");

      final response = await http.get(url, headers: {'Authorization': token});

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else if (response.statusCode == 403) {
        throw Exception("Access denied. Only admins can view invite codes.");
      } else {
        throw Exception("Failed to fetch invite codes");
      }
    } catch (e) {
      throw Exception("Error fetching invite codes: $e");
    }
  }

  /// Revoke (deactivate) an invite code
  static Future<void> revokeInviteCode(String code) async {
    try {
      final token = await AuthService.authorize();
      final url = Uri.parse("$_baseUrl/revoke");

      final response = await http.delete(
        url,
        headers: {'Content-Type': 'application/json', 'Authorization': token},
        body: jsonEncode({"code": code}),
      );

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 403) {
        throw Exception("Access denied. Only admins can revoke invite codes.");
      } else if (response.statusCode == 404) {
        throw Exception("Invite code not found.");
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? "Failed to revoke invite code");
      }
    } catch (e) {
      throw Exception("Error revoking invite code: $e");
    }
  }

  /// Get details of a specific invite code
  static Future<Map<String, dynamic>> getInviteCodeDetails(String code) async {
    try {
      final token = await AuthService.authorize();
      final url = Uri.parse("$_baseUrl/$code");

      final response = await http.get(url, headers: {'Authorization': token});

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 403) {
        throw Exception("Access denied. Only admins can view invite codes.");
      } else if (response.statusCode == 404) {
        throw Exception("Invite code not found.");
      } else {
        throw Exception("Failed to fetch invite code details");
      }
    } catch (e) {
      throw Exception("Error fetching invite code: $e");
    }
  }
}
