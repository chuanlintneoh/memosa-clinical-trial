import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/core/models/case.dart';
import 'package:mobile_app/core/services/auth.dart';
import 'package:mobile_app/core/services/main.dart';
import 'package:mobile_app/core/services/storage.dart';
import 'package:mobile_app/core/utils/crypto.dart';

class DbManagerService {
  // static const String _baseUrl = "http://10.0.2.2:8000/dbmanager";
  static final String _baseUrl =
      "${dotenv.env['BACKEND_SERVER_URL']}/dbmanager";

  static Future<String?> createCase({
    required String caseId,
    required PublicCaseModel publicData,
    required PrivateCaseModel privateData,
  }) async {
    try {
      final serverUp = await MainService.ping();
      if (!serverUp) {
        throw Exception("Server is unreachable. Please try again later.");
      }

      final String idToken = await AuthService.authorize();

      final newAesKey = CryptoUtils.generateAESKey();
      var encryptedData = CryptoUtils.encryptString(
        jsonEncode(privateData.toJson()),
        newAesKey,
      );
      final encryptedBlob = <String, String>{
        'url': await StorageService.upload(
          encrypted: encryptedData['ciphertext'],
          fileName:
              "${caseId}_${publicData.createdAt.toIso8601String().split('.').first.replaceAll('-', '').replaceAll(':', '')}.enc",
          path: "encrypted_blobs",
        ),
        'iv': encryptedData['iv'] ?? "NULL",
      };

      final encryptedAes = CryptoUtils.encryptAESKeyWithPassphrase(
        newAesKey,
        dotenv.env['PASSWORD'] ?? '',
      );

      final encryptedComments =
          (publicData.additionalComments != "NULL" &&
              publicData.additionalComments.trim().isNotEmpty)
          ? CryptoUtils.encryptString(
              publicData.additionalComments.trim(),
              newAesKey,
            )
          : {'ciphertext': "NULL", 'iv': "NULL"};

      final url = Uri.parse("$_baseUrl/case/create?case_id=$caseId");

      final body = jsonEncode(
        CaseCreateModel(
          publicData: publicData,
          encryptedAes: encryptedAes,
          encryptedBlob: encryptedBlob,
          encryptedComments: encryptedComments,
        ).toJson(),
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'Authorization': idToken},
        body: body,
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData['case_id'] as String?;
      } else {
        throw Exception("Case creation failed: ${response.body}");
      }
    } catch (e) {
      throw Exception("Exception during case creation: $e");
    }
  }

  static Future<Map<String, dynamic>> searchCase({
    required String caseId,
  }) async {
    // Study coordinator searches for a case
    var blob = "NULL";
    String comments = "NULL";
    Uint8List aes = Uint8List(0);

    try {
      final serverUp = await MainService.ping();
      if (!serverUp) {
        throw Exception("Server is unreachable. Please try again later.");
      }

      final String idToken = await AuthService.authorize();

      final url = Uri.parse("$_baseUrl/case/get/$caseId");
      final response = await http.get(url, headers: {'Authorization': idToken});

      if (response.statusCode != 200) {
        return {"error": "Case not found"};
      }

      final rawCase = jsonDecode(response.body);

      if (rawCase["encrypted_aes"] != null) {
        if (rawCase["encrypted_aes"]["ciphertext"] != "NULL" &&
            rawCase["encrypted_aes"]["iv"] != "NULL" &&
            rawCase["encrypted_aes"]["salt"] != "NULL") {
          final ciphertext = rawCase["encrypted_aes"]["ciphertext"];
          final iv = rawCase["encrypted_aes"]["iv"];
          final salt = rawCase["encrypted_aes"]["salt"];

          // Run PBKDF2 key derivation in background isolate (2-5s operation)
          // This is the ONLY operation slow enough to justify isolate overhead
          aes = await CryptoUtils.decryptAESKeyWithPassphraseAsync(
            ciphertext,
            dotenv.env['PASSWORD'] ?? '',
            salt,
            iv,
          );

          if (rawCase["encrypted_blob"] != null) {
            if (rawCase["encrypted_blob"]["url"] != "NULL" &&
                rawCase["encrypted_blob"]["iv"] != "NULL") {
              final url = rawCase["encrypted_blob"]["url"];
              final ivBlob = rawCase["encrypted_blob"]["iv"];
              final encryptedBlob = await StorageService.download(url);

              // Use SYNC decryption - fast (~500ms), avoid 100ms isolate overhead
              blob = CryptoUtils.decryptString(encryptedBlob, ivBlob, aes);
            }
          }
          if (rawCase["additional_comments"] != null) {
            if (rawCase["additional_comments"]["ciphertext"] != "NULL" &&
                rawCase["additional_comments"]["iv"] != "NULL") {
              // Use SYNC decryption - very fast (~50ms)
              comments = CryptoUtils.decryptString(
                rawCase["additional_comments"]["ciphertext"],
                rawCase["additional_comments"]["iv"],
                aes,
              );
            }
          }
        }
      }

      // Run case parsing (JSON + base64 image decoding) in background isolate (500ms-1s)
      final caseData = await CaseRetrieveModel.fromRawAsync(
        rawCase: rawCase,
        blob: blob,
        comments: comments,
      );

      return {"case_id": caseId, "aes": aes, "case_data": caseData};
    } catch (e) {
      throw Exception("Exception during case search: $e");
    }
  }

  static Future<String?> editCase({
    required String caseId,
    required CaseEditModel caseData,
  }) async {
    // Study coordinator edit case (eg. add ground truth)
    try {
      final serverUp = await MainService.ping();
      if (!serverUp) {
        throw Exception("Server is unreachable. Please try again later.");
      }

      final String idToken = await AuthService.authorize();

      final url = Uri.parse("$_baseUrl/case/edit?case_id=$caseId");
      final body = jsonEncode(caseData.toJson());
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'Authorization': idToken},
        body: body,
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData['case_id'] as String?;
      } else {
        throw Exception("Case creation failed: ${response.body}");
      }
    } catch (e) {
      throw Exception("Exception during case editing: $e");
    }
  }

  static Future<Map<String, dynamic>> listCases({
    String? dateRange,
    String? customStart,
    String? customEnd,
    bool createdByMe = false,
    int limit = 20,
    String? startAfterId,
  }) async {
    // Study coordinator lists cases with filters
    try {
      final serverUp = await MainService.ping();
      if (!serverUp) {
        throw Exception("Server is unreachable. Please try again later.");
      }

      final String idToken = await AuthService.authorize();

      // Build query parameters
      final queryParams = <String, String>{
        'created_by_me': createdByMe.toString(),
        'limit': limit.toString(),
      };

      if (dateRange != null) {
        queryParams['date_range'] = dateRange;
      }
      if (customStart != null) {
        queryParams['custom_start'] = customStart;
      }
      if (customEnd != null) {
        queryParams['custom_end'] = customEnd;
      }
      if (startAfterId != null) {
        queryParams['start_after_id'] = startAfterId;
      }

      final url = Uri.parse(
        "$_baseUrl/cases/list",
      ).replace(queryParameters: queryParams);
      final response = await http.get(url, headers: {'Authorization': idToken});

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        // Returns: { cases: [...], next_cursor: "...", has_more: bool }
        return responseData;
      } else {
        throw Exception("Failed to list cases: ${response.body}");
      }
    } catch (e) {
      throw Exception("Exception during case listing: $e");
    }
  }

  static Future<List<Map<String, dynamic>>> getUndiagnosedCases({
    required String clinicianID,
    Function(Map<String, dynamic>)? onCaseProcessed,
    int? limit,
    int? daysBack,
  }) async {
    // Clinician retrieves undiagnosed cases
    try {
      final serverUp = await MainService.ping();
      if (!serverUp) {
        throw Exception("Server is unreachable. Please try again later.");
      }

      final String idToken = await AuthService.authorize();

      // Build URL with optional query parameters
      final queryParams = <String, String>{};
      if (limit != null) queryParams['limit'] = limit.toString();
      if (daysBack != null) queryParams['days_back'] = daysBack.toString();

      final url = Uri.parse(
        "$_baseUrl/cases/undiagnosed/$clinicianID",
      ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final response = await http.get(url, headers: {'Authorization': idToken});

      if (response.statusCode != 200) {
        return [
          {"error": "Case not found"},
        ];
      }

      final rawCases = jsonDecode(response.body) as List;
      List<Map<String, dynamic>> results = [];

      for (var rawCase in rawCases) {
        try {
          final caseId = rawCase["case_id"] ?? "UNKNOWN";

          // Return only encrypted metadata - no decryption at this stage
          final caseResult = {
            "case_id": caseId,
            "created_at": rawCase["created_at"],
            "created_by": rawCase["created_by"],
            "submitted_at": rawCase["submitted_at"],
            "encrypted_aes": rawCase["encrypted_aes"],
            "encrypted_blob": rawCase["encrypted_blob"],
            "additional_comments": rawCase["additional_comments"],
            "patient_id": rawCase["patient_id"],
          };
          results.add(caseResult);

          // Notify callback for progressive rendering
          onCaseProcessed?.call(caseResult);
        } catch (e) {
          final errorResult = {
            "error": "Exception during case metadata retrieval: $e",
            "raw_case": rawCase,
          };
          results.add(errorResult);
          onCaseProcessed?.call(errorResult);
        }
      }
      return results;
    } catch (e) {
      throw Exception("Exception during case retrieval: $e");
    }
  }

  static Future<String> diagnoseCase({
    required String caseId,
    required CaseDiagnosisModel diagnoses,
  }) async {
    // Clinician diagnoses a case (clinical diagnosis + lesion type + low quality)
    try {
      final serverUp = await MainService.ping();
      if (!serverUp) {
        throw Exception("Server is unreachable. Please try again later.");
      }

      final String idToken = await AuthService.authorize();

      final url = Uri.parse("$_baseUrl/case/diagnose?case_id=$caseId");
      final body = jsonEncode(diagnoses.toJson());
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json', 'Authorization': idToken},
        body: body,
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData['case_id'] as String;
      } else {
        throw Exception("Case diagnosis failed: ${response.body}");
      }
    } catch (e) {
      throw Exception("Exception during case diagnosis: $e");
    }
  }

  static Future<Map<String, dynamic>> exportBundle({
    required bool includeAll,
  }) async {
    // Admin exports bundle
    try {
      final serverUp = await MainService.ping();
      if (!serverUp) {
        throw Exception("Server is unreachable. Please try again later.");
      }

      final String idToken = await AuthService.authorize();

      final url = Uri.parse("$_baseUrl/bundle/export?include_all=$includeAll");
      final response = await http.get(url, headers: {'Authorization': idToken});

      return jsonDecode(response.body);
    } catch (e) {
      throw Exception("Error exporting bundle: $e");
    }
  }
}
