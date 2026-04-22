import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/core/services/auth.dart';
import 'package:mobile_app/core/services/main.dart';

class UserManagerService {
  // static const String _baseUrl = "http://10.0.2.2:8000/user-manager";
  static final String _baseUrl =
      "${dotenv.env['BACKEND_SERVER_URL']}/user-manager";

  static Future<Map<String, dynamic>> listUsers({
    int limit = 5,
    String? startAfterId,
    String? searchRole,
    String? name,
  }) async {
    try {
      final serverUp = await MainService.ping();
      if (!serverUp) {
        throw Exception("Server is unreachable. Please try again later.");
      }

      final token = await AuthService.authorize();
      final queryParams = <String, String>{"limit": limit.toString()};

      if (startAfterId != null && startAfterId.isNotEmpty) {
        queryParams["start_after_id"] = startAfterId;
      }
      if (searchRole != null && searchRole.isNotEmpty) {
        queryParams["search_role"] = searchRole;
      }
      if (name != null && name.isNotEmpty) {
        queryParams["name"] = name;
      }

      final url = Uri.parse(
        "$_baseUrl/users/list",
      ).replace(queryParameters: queryParams);
      final response = await http.get(url, headers: {'Authorization': token});
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 200) {
        throw Exception(
          data["error"] ?? data["status"] ?? "Failed to list users",
        );
      }

      final nested = data["users"] as Map<String, dynamic>? ?? {};
      final users = (nested["users"] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

      return {
        "users": users,
        "next_cursor": nested["next_cursor"],
        "has_more": nested["has_more"] == true,
        "status": data["status"],
      };
    } catch (e) {
      throw Exception("Exception during user listing: $e");
    }
  }

  static Future<Map<String, dynamic>> getUserById(String userId) async {
    try {
      final serverUp = await MainService.ping();
      if (!serverUp) {
        throw Exception("Server is unreachable. Please try again later.");
      }

      final token = await AuthService.authorize();
      final url = Uri.parse("$_baseUrl/user/get/$userId");
      final response = await http.get(url, headers: {'Authorization': token});
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return data["user"] as Map<String, dynamic>? ?? {};
      }

      throw Exception(data["error"] ?? data["status"] ?? "Failed to get user");
    } catch (e) {
      throw Exception("Exception during get user: $e");
    }
  }

  static Future<void> deleteUser({
    required String userId,
    bool hardDelete = false,
  }) async {
    try {
      final serverUp = await MainService.ping();
      if (!serverUp) {
        throw Exception("Server is unreachable. Please try again later.");
      }

      final token = await AuthService.authorize();
      final url = Uri.parse("$_baseUrl/user/delete").replace(
        queryParameters: {
          "user_id": userId,
          "hard_delete": hardDelete.toString(),
        },
      );
      final response = await http.delete(
        url,
        headers: {'Authorization': token},
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 200) {
        throw Exception(
          data["error"] ?? data["status"] ?? "Failed to delete user",
        );
      }
    } catch (e) {
      throw Exception("Exception during user deletion: $e");
    }
  }

  static Future<void> reactivateUser(String userId) async {
    try {
      final serverUp = await MainService.ping();
      if (!serverUp) {
        throw Exception("Server is unreachable. Please try again later.");
      }

      final token = await AuthService.authorize();
      final url = Uri.parse(
        "$_baseUrl/user/reactivate",
      ).replace(queryParameters: {"user_id": userId});
      final response = await http.patch(url, headers: {'Authorization': token});
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 200) {
        throw Exception(
          data["error"] ?? data["status"] ?? "Failed to reactivate user",
        );
      }
    } catch (e) {
      throw Exception("Exception during user reactivation: $e");
    }
  }

  static Future<void> editUser({
    required String userId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      final serverUp = await MainService.ping();
      if (!serverUp) {
        throw Exception("Server is unreachable. Please try again later.");
      }

      final token = await AuthService.authorize();
      final url = Uri.parse(
        "$_baseUrl/user/edit",
      ).replace(queryParameters: {"user_id": userId});
      final response = await http.patch(
        url,
        headers: {'Content-Type': 'application/json', 'Authorization': token},
        body: jsonEncode(updates),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 200) {
        throw Exception(
          data["error"] ?? data["status"] ?? "Failed to edit user",
        );
      }
    } catch (e) {
      throw Exception("Exception during user edit: $e");
    }
  }
}
