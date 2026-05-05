// Search and edit / add ground truth for existing case in database
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_app/core/models/case.dart';
import 'package:mobile_app/core/models/lesion_data.dart';
import 'package:mobile_app/core/services/dbmanager.dart';
import 'package:mobile_app/core/services/storage.dart';
import 'package:mobile_app/core/utils/crypto.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class EditCaseScreen extends StatefulWidget {
  const EditCaseScreen({super.key});

  @override
  State<EditCaseScreen> createState() => _EditCaseScreenState();
}

class _EditCaseScreenState extends State<EditCaseScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? _searchResult;
  String? _errorMessage;

  final TextEditingController _searchController = TextEditingController();

  CaseRetrieveModel? _caseData;
  final _caseIdController = TextEditingController();
  final _createdAtController = TextEditingController();
  final _submittedAtController = TextEditingController();
  final _createdByController = TextEditingController();
  final _nameController = TextEditingController();
  final _idTypeController = TextEditingController();
  final _idNumController = TextEditingController();
  final _dobController = TextEditingController();
  final _ageController = TextEditingController();
  final _genderController = TextEditingController();
  final _ethnicityController = TextEditingController();
  final _phoneNumberController = TextEditingController();
  final _addressController = TextEditingController();
  final _attendingHospitalController = TextEditingController();
  String _consentFormType = "NULL";
  Uint8List _consentFormBytes = Uint8List(0);
  Habit? _smoking;
  final _smokingDurationController = TextEditingController();
  DurationUnit? _smokingDurationUnit;
  Habit? _betelQuid;
  final _betelQuidDurationController = TextEditingController();
  DurationUnit? _betelQuidDurationUnit;
  Habit? _alcohol;
  final _alcoholDurationController = TextEditingController();
  DurationUnit? _alcoholDurationUnit;
  final _lesionClinicalPresentationController = TextEditingController();
  final _chiefComplaintController = TextEditingController();
  final _presentingComplaintHistoryController = TextEditingController();
  final _medicationHistoryController = TextEditingController();
  final _medicalHistoryController = TextEditingController();
  bool? _slsContainingToothpaste;
  final _slsContainingToothpasteUsedController = TextEditingController();
  bool? _oralHygieneProductsUsed;
  final _oralHygieneProductTypeUsedController = TextEditingController();
  final _additionalCommentsController = TextEditingController();
  List<Uint8List> _images = List.generate(9, (_) => Uint8List(0));
  late List<Diagnosis> _diagnoses;

  final List<String> _imageNamesList = [
    "IMG1: Tongue",
    "IMG2: Below Tongue",
    "IMG3: Left of Tongue",
    "IMG4: Right of Tongue",
    "IMG5: Palate",
    "IMG6: Left Cheek",
    "IMG7: Right Cheek",
    "IMG8: Upper Lip / Gum",
    "IMG9: Lower Lip / Gum",
  ];
  int _selectedImageIndex = 0;
  late List<LesionTypeEnum> _biopsyLesionTypes;
  late List<ClinicalDiagnosisEnum> _biopsyClinicalDiagnoses;
  late List<LesionTypeEnum> _coeLesionTypes;
  late List<ClinicalDiagnosisEnum> _coeClinicalDiagnoses;
  List<BiopsyAgreeWithCOE> _biopsyAgreeWithCOE = List.filled(
    9,
    BiopsyAgreeWithCOE.NULL,
  );
  List<TextEditingController> _biopsyAgreeWithCOEController = List.generate(
    9,
    (index) => TextEditingController(text: BiopsyAgreeWithCOE.NULL.name),
  );
  List<Map<String, dynamic>> _biopsyReports = List.generate(
    9,
    (_) => {"url": "NULL", "iv": "NULL", "fileType": "NULL"},
  ); // report from database
  List<File?> _biopsyReportFiles = List.filled(
    9,
    null,
  ); // recently picked file pending to upload to storage upon case changes submission
  late List<LesionTypeEnum> _aiLesionTypes;
  bool _isUpdating = false; // Prevent circular updates

  final ImagePicker _picker = ImagePicker();
  final LesionDataManager _lesionDataManager = LesionDataManager();

  bool _hasCheckedArguments = false;

  @override
  void initState() {
    super.initState();
    _initializeLesionData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Check for navigation arguments (case data from cases_list screen)
    if (!_hasCheckedArguments) {
      _hasCheckedArguments = true;
      final args = ModalRoute.of(context)?.settings.arguments;

      if (args != null && args is Map<String, dynamic>) {
        final caseId = args['case_id'] as String?;
        final encryptedBlob = args['encrypted_blob'];
        final encryptedAes = args['encrypted_aes'];

        // Check if we have complete case data with encrypted blob URLs
        if (caseId != null &&
            caseId.isNotEmpty &&
            encryptedBlob != null &&
            encryptedAes != null) {
          // Complete case data was passed - process it without API call
          _searchController.text = caseId;

          WidgetsBinding.instance.addPostFrameCallback((_) async {
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });

            try {
              // Ensure lesion data is loaded before populating
              await _lesionDataManager.loadData();

              if (!mounted) return;

              // Process the raw case data (decrypt blob and parse)
              final processedResult = await _processRawCaseData(args);

              if (!mounted) return;

              setState(() {
                _searchResult = processedResult;
                _errorMessage = null;
              });
              _populateData();
            } catch (e) {
              if (!mounted) return;
              setState(() {
                _errorMessage = e.toString();
                _searchResult = null;
              });
            } finally {
              if (mounted) {
                setState(() => _isLoading = false);
              }
            }
          });
        } else if (caseId != null && caseId.isNotEmpty) {
          // Only case_id was passed - use existing search flow
          _searchController.text = caseId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _searchCase();
          });
        }
      }
    }
  }

  Future<Map<String, dynamic>> _processRawCaseData(
    Map<String, dynamic> rawCase,
  ) async {
    // This mimics what DbManagerService.searchCase does
    // Download and decrypt the blob, then parse it into CaseRetrieveModel

    Uint8List aes = Uint8List(0);
    String blob = 'NULL';
    String comments = 'NULL';

    // Decrypt AES key
    if (rawCase["encrypted_aes"] != null) {
      if (rawCase["encrypted_aes"]["ciphertext"] != "NULL" &&
          rawCase["encrypted_aes"]["iv"] != "NULL" &&
          rawCase["encrypted_aes"]["salt"] != "NULL") {
        final ciphertext = rawCase["encrypted_aes"]["ciphertext"];
        final iv = rawCase["encrypted_aes"]["iv"];
        final salt = rawCase["encrypted_aes"]["salt"];

        // Use async ONLY for PBKDF2 (2-5s operation) to avoid UI freeze
        aes = await CryptoUtils.decryptAESKeyWithPassphraseAsync(
          ciphertext,
          dotenv.env['PASSWORD'] ?? '',
          salt,
          iv,
        );

        // Download blob (network operation - must be async)
        if (rawCase["encrypted_blob"] != null) {
          if (rawCase["encrypted_blob"]["url"] != "NULL" &&
              rawCase["encrypted_blob"]["iv"] != "NULL") {
            final url = rawCase["encrypted_blob"]["url"];
            final ivBlob = rawCase["encrypted_blob"]["iv"];
            final encryptedBlob = await StorageService.download(url);

            // Use SYNC for AES decryption (fast ~500ms, avoid isolate overhead)
            blob = CryptoUtils.decryptString(encryptedBlob, ivBlob, aes);
          }
        }

        // Decrypt additional comments - use SYNC (fast operation)
        if (rawCase["additional_comments"] != null) {
          if (rawCase["additional_comments"]["ciphertext"] != "NULL" &&
              rawCase["additional_comments"]["iv"] != "NULL") {
            comments = CryptoUtils.decryptString(
              rawCase["additional_comments"]["ciphertext"],
              rawCase["additional_comments"]["iv"],
              aes,
            );
          }
        }
      }
    }

    // Parse case data
    final caseData = await CaseRetrieveModel.fromRawAsync(
      rawCase: rawCase,
      blob: blob,
      comments: comments,
    );

    return {"case_id": rawCase["case_id"], "aes": aes, "case_data": caseData};
  }

  Future<void> _initializeLesionData() async {
    await _lesionDataManager.loadData();
    setState(() {
      // Initialize with NULL values
      _diagnoses = List.generate(9, (_) => Diagnosis.empty());
      _biopsyLesionTypes = List.filled(9, _lesionDataManager.nullLesionType);
      _biopsyClinicalDiagnoses = List.filled(
        9,
        _lesionDataManager.nullClinicalDiagnosis,
      );
      _coeLesionTypes = List.filled(9, _lesionDataManager.nullLesionType);
      _coeClinicalDiagnoses = List.filled(
        9,
        _lesionDataManager.nullClinicalDiagnosis,
      );
      _aiLesionTypes = List.filled(9, _lesionDataManager.nullLesionType);
    });
  }

  void _parseDuration(
    String? durationStr,
    TextEditingController controller,
    Function(DurationUnit?) setUnit,
  ) {
    if (durationStr == null || durationStr.isEmpty || durationStr == "NULL") {
      controller.text = '';
      setUnit(null);
      return;
    }

    // Parse format: "2 YEARS" into number and unit
    final parts = durationStr.trim().split(' ');
    if (parts.length >= 2) {
      controller.text = parts[0];
      final unitStr = parts.sublist(1).join(' ');
      try {
        final unit = DurationUnit.values.firstWhere(
          (e) => e.name == unitStr,
          orElse: () => DurationUnit.YEARS,
        );
        setUnit(unit);
      } catch (_) {
        setUnit(DurationUnit.YEARS);
      }
    } else {
      controller.text = durationStr;
      setUnit(null);
    }
  }

  String _combineDuration(String number, DurationUnit? unit) {
    if (number.isEmpty || unit == null) {
      return '';
    }
    return '$number ${unit.name}';
  }

  Future<void> _resetState() async {
    // Ensure lesion data is loaded before resetting
    await _lesionDataManager.loadData();

    setState(() {
      _isLoading = false;
      _searchResult = null;
      _errorMessage = null;

      _searchController.clear();

      _caseData = null;
      _caseIdController.clear();
      _createdAtController.clear();
      _submittedAtController.clear();
      _createdByController.clear();
      _nameController.clear();
      _idTypeController.clear();
      _idNumController.clear();
      _dobController.clear();
      _ageController.clear();
      _genderController.clear();
      _ethnicityController.clear();
      _phoneNumberController.clear();
      _addressController.clear();
      _attendingHospitalController.clear();
      _consentFormType = "NULL";
      _consentFormBytes = Uint8List(0);
      _smoking = null;
      _smokingDurationController.clear();
      _smokingDurationUnit = null;
      _betelQuid = null;
      _betelQuidDurationController.clear();
      _betelQuidDurationUnit = null;
      _alcohol = null;
      _alcoholDurationController.clear();
      _alcoholDurationUnit = null;
      _lesionClinicalPresentationController.clear();
      _chiefComplaintController.clear();
      _presentingComplaintHistoryController.clear();
      _medicationHistoryController.clear();
      _medicalHistoryController.clear();
      _slsContainingToothpaste = null;
      _slsContainingToothpasteUsedController.clear();
      _oralHygieneProductsUsed = null;
      _oralHygieneProductTypeUsedController.clear();
      _additionalCommentsController.clear();
      _images = List.generate(9, (_) => Uint8List(0));
      _diagnoses = List.generate(9, (_) => Diagnosis.empty());

      _selectedImageIndex = 0;
      _biopsyLesionTypes = List.filled(9, _lesionDataManager.nullLesionType);
      _biopsyClinicalDiagnoses = List.filled(
        9,
        _lesionDataManager.nullClinicalDiagnosis,
      );
      _coeLesionTypes = List.filled(9, _lesionDataManager.nullLesionType);
      _coeClinicalDiagnoses = List.filled(
        9,
        _lesionDataManager.nullClinicalDiagnosis,
      );
      _biopsyAgreeWithCOE = List.filled(9, BiopsyAgreeWithCOE.NULL);
      _biopsyAgreeWithCOEController = List.generate(
        9,
        (index) => TextEditingController(text: BiopsyAgreeWithCOE.NULL.name),
      );
      _biopsyReports = List.generate(
        9,
        (_) => {"url": "NULL", "iv": "NULL", "fileType": "NULL"},
      );
      _biopsyReportFiles = List.filled(9, null);
      _aiLesionTypes = List.filled(9, _lesionDataManager.nullLesionType);
    });
  }

  void _populateData() {
    if (_searchResult == null) return;

    setState(() {
      final result = _searchResult!;
      _caseData = result["case_data"];
      _caseIdController.text = result["case_id"] ?? "";
      _createdAtController.text = _caseData!.createdAt;
      _submittedAtController.text = _caseData!.submittedAt;
      _createdByController.text = _caseData!.createdBy;
      _nameController.text = _caseData!.name;
      _idTypeController.text = _caseData!.idtype;
      _idNumController.text = _caseData!.idnum;
      _dobController.text = _caseData!.dob;
      _ageController.text = _caseData!.age;
      _genderController.text = _caseData!.gender;
      _ethnicityController.text = _caseData!.ethnicity;
      _phoneNumberController.text = _caseData!.phonenum;
      _addressController.text = _caseData!.address;
      _attendingHospitalController.text = _caseData!.attendingHospital;
      _consentFormType = _caseData!.consentForm["fileType"] ?? "NULL";
      _consentFormBytes = _caseData!.consentForm["fileBytes"] ?? Uint8List(0);
      _smoking = _caseData!.smoking;
      _parseDuration(
        _caseData!.smokingDuration,
        _smokingDurationController,
        (unit) => _smokingDurationUnit = unit,
      );
      _betelQuid = _caseData!.betelQuid;
      _parseDuration(
        _caseData!.betelQuidDuration,
        _betelQuidDurationController,
        (unit) => _betelQuidDurationUnit = unit,
      );
      _alcohol = _caseData!.alcohol;
      _parseDuration(
        _caseData!.alcoholDuration,
        _alcoholDurationController,
        (unit) => _alcoholDurationUnit = unit,
      );
      _lesionClinicalPresentationController.text =
          _caseData!.lesionClinicalPresentation;
      _chiefComplaintController.text = _caseData!.chiefComplaint;
      _presentingComplaintHistoryController.text =
          _caseData!.presentingComplaintHistory;
      _medicationHistoryController.text = _caseData!.medicationHistory;
      _medicalHistoryController.text = _caseData!.medicalHistory;
      _slsContainingToothpaste = _caseData!.slsContainingToothpaste;
      _slsContainingToothpasteUsedController.text =
          _caseData!.slsContainingToothpasteUsed;
      _oralHygieneProductsUsed = _caseData!.oralHygieneProductsUsed;
      _oralHygieneProductTypeUsedController.text =
          _caseData!.oralHygieneProductTypeUsed;
      _additionalCommentsController.text = _caseData!.additionalComments;
      _images = _caseData!.images;
      _diagnoses = _caseData!.diagnoses;
      for (int i = 0; i < _diagnoses.length && i < 9; i++) {
        _biopsyLesionTypes[i] = _diagnoses[i].biopsyLesionType;
        _biopsyClinicalDiagnoses[i] = _diagnoses[i].biopsyClinicalDiagnosis;
        _coeLesionTypes[i] = _diagnoses[i].coeLesionType;
        _coeClinicalDiagnoses[i] = _diagnoses[i].coeClinicalDiagnosis;
        _aiLesionTypes[i] = _diagnoses[i]
            .aiLesionType; // for creation of CaseEditModel, not submitted for editing to server

        final dynamic incomingReport = _diagnoses[i].biopsyReport;
        if (incomingReport != null &&
            incomingReport is Map &&
            incomingReport.containsKey("url") &&
            incomingReport.containsKey("iv") &&
            incomingReport.containsKey("fileType")) {
          _biopsyReports[i] = {
            "url": incomingReport["url"] ?? "NULL",
            "iv": incomingReport["iv"] ?? "NULL",
            "fileType": incomingReport["fileType"] ?? "NULL",
          };
        } else {
          _biopsyReports[i] = {"url": "NULL", "iv": "NULL", "fileType": "NULL"};
        }

        _updateBiopsyAgreeWithCOE(i);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _caseIdController.dispose();
    _createdAtController.dispose();
    _submittedAtController.dispose();
    _createdByController.dispose();
    _nameController.dispose();
    _idTypeController.dispose();
    _idNumController.dispose();
    _dobController.dispose();
    _ageController.dispose();
    _genderController.dispose();
    _ethnicityController.dispose();
    _phoneNumberController.dispose();
    _addressController.dispose();
    _attendingHospitalController.dispose();
    _smokingDurationController.dispose();
    _betelQuidDurationController.dispose();
    _alcoholDurationController.dispose();
    _lesionClinicalPresentationController.dispose();
    _chiefComplaintController.dispose();
    _presentingComplaintHistoryController.dispose();
    _medicationHistoryController.dispose();
    _medicalHistoryController.dispose();
    _slsContainingToothpasteUsedController.dispose();
    _oralHygieneProductTypeUsedController.dispose();
    _additionalCommentsController.dispose();
    for (var controller in _biopsyAgreeWithCOEController) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _searchCase() async {
    final caseId = _searchController.text.trim();
    if (caseId.isEmpty) {
      setState(() {
        _errorMessage = "Please enter a case ID";
        _searchResult = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _searchResult = null;
    });

    try {
      // Ensure lesion data is loaded before searching
      await _lesionDataManager.loadData();

      final result = await DbManagerService.searchCase(caseId: caseId);

      if (!mounted) return;

      if (result.containsKey("error")) {
        setState(() {
          _errorMessage = "Case not found.";
          _searchResult = null;
        });
      } else {
        setState(() {
          _searchResult = result;
          _errorMessage = null;
        });
        _populateData();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _searchResult = null;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
    IconData? icon,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildCaseForm(Map<String, dynamic> result) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth > 600;

        if (isTablet) {
          return _buildTabletLayout();
        } else {
          return _buildMobileLayout();
        }
      },
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCaseInfoSection(),
        _buildPersonalDetailsSection(),
        _buildConsentFormSection(),
        _buildHabitsSection(),
        _buildClinicalInfoSection(),
        _buildOralHygieneSection(),
        _buildDiagnosisSection(),
      ],
    );
  }

  Widget _buildTabletLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  _buildCaseInfoSection(),
                  _buildPersonalDetailsSection(),
                  _buildConsentFormSection(),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                children: [
                  _buildHabitsSection(),
                  _buildClinicalInfoSection(),
                  _buildOralHygieneSection(),
                ],
              ),
            ),
          ],
        ),
        _buildDiagnosisSection(),
      ],
    );
  }

  Widget _buildCaseInfoSection() {
    return _buildSectionCard(
      title: 'Case Information',
      icon: Icons.info_outline,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                _caseIdController,
                "Case ID",
                noExpand: true,
                copiable: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                _createdByController,
                "Created By",
                noExpand: true,
                copiable: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(_createdAtController, "Created At", copiable: true),
        const SizedBox(height: 16),
        _buildTextField(_submittedAtController, "Submitted At", copiable: true),
      ],
    );
  }

  Widget _buildPersonalDetailsSection() {
    return _buildSectionCard(
      title: 'Personal Details',
      icon: Icons.person_outline,
      children: [
        _buildTextField(_nameController, "Name"),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 35,
              child: _buildTextField(
                _idTypeController,
                "ID Type",
                noExpand: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 65,
              child: _buildTextField(
                _idNumController,
                "ID Number",
                noExpand: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 75,
              child: _buildTextField(
                _dobController,
                "Date of Birth",
                noExpand: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 25,
              child: _buildTextField(_ageController, "Age", noExpand: true),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(_genderController, "Gender"),
        const SizedBox(height: 16),
        _buildTextField(_ethnicityController, "Ethnicity"),
        const SizedBox(height: 16),
        _buildTextField(_phoneNumberController, "Phone Number"),
        const SizedBox(height: 16),
        _buildTextField(_addressController, "Address"),
        const SizedBox(height: 16),
        _buildTextField(_attendingHospitalController, "Attending Hospital"),
      ],
    );
  }

  Widget _buildConsentFormSection() {
    return _buildSectionCard(
      title: 'Consent Form',
      icon: Icons.description_outlined,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _consentFormBytes.isNotEmpty
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _consentFormBytes.isNotEmpty ? Colors.green : Colors.grey,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(
                _consentFormBytes.isNotEmpty
                    ? Icons.check_circle_outline
                    : Icons.upload_file_outlined,
                size: 48,
                color: _consentFormBytes.isNotEmpty
                    ? Colors.green
                    : Colors.grey,
              ),
              const SizedBox(height: 8),
              Text(
                _consentFormBytes.isNotEmpty
                    ? "Consent form available"
                    : "No consent form available",
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _consentFormBytes.isEmpty
              ? () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("No consent form available")),
                )
              : () => _viewFile(_consentFormBytes, fileType: _consentFormType),
          icon: const Icon(Icons.remove_red_eye),
          label: const Text("View Consent Form"),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(16),
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ],
    );
  }

  Widget _buildHabitsSection() {
    return _buildSectionCard(
      title: 'Habits & Lifestyle',
      icon: Icons.smoking_rooms_outlined,
      children: [
        _buildDropdown<Habit>("Smoking", _smoking, Habit.values, (val) {
          setState(() {
            _smoking = val;
            if (val == Habit.NO) {
              _smokingDurationController.clear();
              _smokingDurationUnit = null;
            }
          });
        }),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 45,
              child: TextFormField(
                controller: _smokingDurationController,
                enabled: _smoking != Habit.NO,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: "Duration (Number)",
                  disabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 55,
              child: IgnorePointer(
                ignoring: _smoking == Habit.NO,
                child: DropdownButtonFormField<DurationUnit>(
                  value: _smokingDurationUnit,
                  decoration: InputDecoration(
                    labelText: "Duration Unit",
                    filled: _smoking == Habit.NO,
                    fillColor: _smoking == Habit.NO
                        ? Colors.grey.withValues(alpha: 0.1)
                        : null,
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  items: DurationUnit.values
                      .map(
                        (e) => DropdownMenuItem(value: e, child: Text(e.name)),
                      )
                      .toList(),
                  onChanged: _smoking != Habit.NO
                      ? (val) => setState(() => _smokingDurationUnit = val)
                      : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildDropdown<Habit>("Betel Quid", _betelQuid, Habit.values, (val) {
          setState(() {
            _betelQuid = val;
            if (val == Habit.NO) {
              _betelQuidDurationController.clear();
              _betelQuidDurationUnit = null;
            }
          });
        }),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 45,
              child: TextFormField(
                controller: _betelQuidDurationController,
                enabled: _betelQuid != Habit.NO,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: "Duration (Number)",
                  disabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 55,
              child: IgnorePointer(
                ignoring: _betelQuid == Habit.NO,
                child: DropdownButtonFormField<DurationUnit>(
                  value: _betelQuidDurationUnit,
                  decoration: InputDecoration(
                    labelText: "Duration Unit",
                    filled: _betelQuid == Habit.NO,
                    fillColor: _betelQuid == Habit.NO
                        ? Colors.grey.withValues(alpha: 0.1)
                        : null,
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  items: DurationUnit.values
                      .map(
                        (e) => DropdownMenuItem(value: e, child: Text(e.name)),
                      )
                      .toList(),
                  onChanged: _betelQuid != Habit.NO
                      ? (val) => setState(() => _betelQuidDurationUnit = val)
                      : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildDropdown<Habit>("Alcohol", _alcohol, Habit.values, (val) {
          setState(() {
            _alcohol = val;
            if (val == Habit.NO) {
              _alcoholDurationController.clear();
              _alcoholDurationUnit = null;
            }
          });
        }),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 45,
              child: TextFormField(
                controller: _alcoholDurationController,
                enabled: _alcohol != Habit.NO,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: "Duration (Number)",
                  disabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 55,
              child: IgnorePointer(
                ignoring: _alcohol == Habit.NO,
                child: DropdownButtonFormField<DurationUnit>(
                  value: _alcoholDurationUnit,
                  decoration: InputDecoration(
                    labelText: "Duration Unit",
                    filled: _alcohol == Habit.NO,
                    fillColor: _alcohol == Habit.NO
                        ? Colors.grey.withValues(alpha: 0.1)
                        : null,
                    disabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  items: DurationUnit.values
                      .map(
                        (e) => DropdownMenuItem(value: e, child: Text(e.name)),
                      )
                      .toList(),
                  onChanged: _alcohol != Habit.NO
                      ? (val) => setState(() => _alcoholDurationUnit = val)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildClinicalInfoSection() {
    return _buildSectionCard(
      title: 'Clinical Information',
      icon: Icons.medical_information_outlined,
      children: [
        _buildTextField(
          _lesionClinicalPresentationController,
          "Lesion Clinical Presentation",
          copiable: true,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          _chiefComplaintController,
          "Chief Complaint",
          copiable: true,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          _presentingComplaintHistoryController,
          "Presenting Complaint History",
          copiable: true,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          _medicationHistoryController,
          "Medication History",
          copiable: true,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          _medicalHistoryController,
          "Medical History",
          copiable: true,
        ),
      ],
    );
  }

  Widget _buildOralHygieneSection() {
    return _buildSectionCard(
      title: 'Oral Hygiene',
      icon: Icons.clean_hands_outlined,
      children: [
        Row(
          children: [
            Expanded(
              flex: 35,
              child: _buildDropdown<bool>(
                "SLS Toothpaste",
                _slsContainingToothpaste,
                [true, false],
                (val) {
                  setState(() {
                    _slsContainingToothpaste = val;
                    if (val == false) {
                      _slsContainingToothpasteUsedController.clear();
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 65,
              child: TextFormField(
                controller: _slsContainingToothpasteUsedController,
                enabled: _slsContainingToothpaste != false,
                decoration: InputDecoration(
                  labelText: "Type",
                  disabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 35,
              child: _buildDropdown<bool>(
                "Other Products",
                _oralHygieneProductsUsed,
                [true, false],
                (val) {
                  setState(() {
                    _oralHygieneProductsUsed = val;
                    if (val == false) {
                      _oralHygieneProductTypeUsedController.clear();
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 65,
              child: TextFormField(
                controller: _oralHygieneProductTypeUsedController,
                enabled: _oralHygieneProductsUsed != false,
                decoration: InputDecoration(
                  labelText: "Type",
                  disabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          _additionalCommentsController,
          "Additional Comments",
          readOnly: false,
          multiline: true,
        ),
      ],
    );
  }

  Widget _buildDiagnosisSection() {
    return _buildSectionCard(
      title: 'Diagnosis & Image Review',
      icon: Icons.photo_camera_outlined,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Select an image to view and add diagnosis information.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          value: _selectedImageIndex,
          decoration: const InputDecoration(
            labelText: "Select Oral Cavity Image",
            border: OutlineInputBorder(),
          ),
          items: List.generate(
            _imageNamesList.length,
            (i) => DropdownMenuItem(value: i, child: Text(_imageNamesList[i])),
          ),
          onChanged: (val) {
            if (val != null) setState(() => _selectedImageIndex = val);
          },
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () {
            if (_images.isNotEmpty) {
              _showImageZoomDialog(_selectedImageIndex);
            }
          },
          child: Container(
            height: 250,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.5),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                Center(
                  child: _images.isNotEmpty
                      ? Image.memory(
                          _images[_selectedImageIndex],
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                        )
                      : const Text("No image available"),
                ),
                if (_images.isNotEmpty)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.zoom_in, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'Tap to zoom',
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Clinical Examination (COE)',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildLesionTypeDropdown(
          "Lesion Type",
          _coeLesionTypes[_selectedImageIndex],
          (val) {
            if (_isUpdating) return;
            _isUpdating = true;

            setState(() {
              _coeLesionTypes[_selectedImageIndex] = val;

              // If lesion type is NULL, set clinical diagnosis to NULL
              if (val.key == _lesionDataManager.nullLesionType.key) {
                _coeClinicalDiagnoses[_selectedImageIndex] =
                    _lesionDataManager.nullClinicalDiagnosis;
              } else {
                final validDiagnoses = _lesionDataManager
                    .getClinicalDiagnosesForLesionType(val);

                final actualDiagnoses = validDiagnoses
                    .where(
                      (d) =>
                          d.key != _lesionDataManager.nullClinicalDiagnosis.key,
                    )
                    .toList();

                if (actualDiagnoses.length == 1) {
                  _coeClinicalDiagnoses[_selectedImageIndex] =
                      actualDiagnoses.first;
                } else {
                  // Check if current diagnosis belongs to new lesion type
                  final currentDiagnosis =
                      _coeClinicalDiagnoses[_selectedImageIndex];
                  if (!_lesionDataManager.diagnosisBelongsToLesionType(
                    currentDiagnosis,
                    val,
                  )) {
                    // Reset to NULL if diagnosis doesn't belong to new lesion type
                    _coeClinicalDiagnoses[_selectedImageIndex] =
                        _lesionDataManager.nullClinicalDiagnosis;
                  }
                }
              }

              _updateBiopsyAgreeWithCOE(_selectedImageIndex);
            });

            _isUpdating = false;
          },
        ),
        const SizedBox(height: 12),
        _buildClinicalDiagnosisDropdown(
          "Clinical Diagnosis",
          _coeClinicalDiagnoses[_selectedImageIndex],
          _coeLesionTypes[_selectedImageIndex],
          (val) {
            if (_isUpdating) return;
            _isUpdating = true;

            setState(() {
              _coeClinicalDiagnoses[_selectedImageIndex] = val;

              // If diagnosis is NOT NULL, update lesion type to match
              if (val.key != _lesionDataManager.nullClinicalDiagnosis.key) {
                final lesionType = _lesionDataManager
                    .findLesionTypeForDiagnosis(val);
                if (lesionType != null) {
                  _coeLesionTypes[_selectedImageIndex] = lesionType;
                }
              }
              // If diagnosis is NULL, don't change lesion type

              _updateBiopsyAgreeWithCOE(_selectedImageIndex);
            });

            _isUpdating = false;
          },
        ),
        const SizedBox(height: 24),
        Text(
          'Biopsy Results',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildLesionTypeDropdown(
          "Lesion Type",
          _biopsyLesionTypes[_selectedImageIndex],
          (val) {
            if (_isUpdating) return;
            _isUpdating = true;

            setState(() {
              _biopsyLesionTypes[_selectedImageIndex] = val;

              // If lesion type is NULL, set clinical diagnosis to NULL
              if (val.key == _lesionDataManager.nullLesionType.key) {
                _biopsyClinicalDiagnoses[_selectedImageIndex] =
                    _lesionDataManager.nullClinicalDiagnosis;
              } else {
                final validDiagnoses = _lesionDataManager
                    .getClinicalDiagnosesForLesionType(val);

                final actualDiagnoses = validDiagnoses
                    .where(
                      (d) =>
                          d.key != _lesionDataManager.nullClinicalDiagnosis.key,
                    )
                    .toList();

                if (actualDiagnoses.length == 1) {
                  _biopsyClinicalDiagnoses[_selectedImageIndex] =
                      actualDiagnoses.first;
                } else {
                  // Check if current diagnosis belongs to new lesion type
                  final currentDiagnosis =
                      _biopsyClinicalDiagnoses[_selectedImageIndex];
                  if (!_lesionDataManager.diagnosisBelongsToLesionType(
                    currentDiagnosis,
                    val,
                  )) {
                    // Reset to NULL if diagnosis doesn't belong to new lesion type
                    _biopsyClinicalDiagnoses[_selectedImageIndex] =
                        _lesionDataManager.nullClinicalDiagnosis;
                  }
                }
              }

              _updateBiopsyAgreeWithCOE(_selectedImageIndex);
            });

            _isUpdating = false;
          },
        ),
        const SizedBox(height: 12),
        _buildClinicalDiagnosisDropdown(
          "Clinical Diagnosis",
          _biopsyClinicalDiagnoses[_selectedImageIndex],
          _biopsyLesionTypes[_selectedImageIndex],
          (val) {
            if (_isUpdating) return;
            _isUpdating = true;

            setState(() {
              _biopsyClinicalDiagnoses[_selectedImageIndex] = val;

              // If diagnosis is NOT NULL, update lesion type to match
              if (val.key != _lesionDataManager.nullClinicalDiagnosis.key) {
                final lesionType = _lesionDataManager
                    .findLesionTypeForDiagnosis(val);
                if (lesionType != null) {
                  _biopsyLesionTypes[_selectedImageIndex] = lesionType;
                }
              }
              // If diagnosis is NULL, don't change lesion type

              _updateBiopsyAgreeWithCOE(_selectedImageIndex);
            });

            _isUpdating = false;
          },
        ),
        const SizedBox(height: 16),
        _buildTextField(
          _biopsyAgreeWithCOEController[_selectedImageIndex],
          "Biopsy agree with COE diagnosis?",
          copiable: true,
        ),
        const SizedBox(height: 24),
        Text(
          'Biopsy Report',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color:
                (_biopsyReportFiles[_selectedImageIndex] != null ||
                    _biopsyReports[_selectedImageIndex]['url'] != 'NULL')
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  (_biopsyReportFiles[_selectedImageIndex] != null ||
                      _biopsyReports[_selectedImageIndex]['url'] != 'NULL')
                  ? Colors.green
                  : Colors.grey,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(
                (_biopsyReportFiles[_selectedImageIndex] != null ||
                        _biopsyReports[_selectedImageIndex]['url'] != 'NULL')
                    ? Icons.check_circle_outline
                    : Icons.upload_file_outlined,
                size: 48,
                color:
                    (_biopsyReportFiles[_selectedImageIndex] != null ||
                        _biopsyReports[_selectedImageIndex]['url'] != 'NULL')
                    ? Colors.green
                    : Colors.grey,
              ),
              const SizedBox(height: 8),
              Text(
                (_biopsyReportFiles[_selectedImageIndex] != null ||
                        _biopsyReports[_selectedImageIndex]['url'] != 'NULL')
                    ? "Biopsy report available"
                    : "No biopsy report uploaded",
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () =>
                    _showBiopsyReportSourceActionSheet(_selectedImageIndex),
                icon: _biopsyReportFiles[_selectedImageIndex] != null
                    ? const Icon(Icons.edit)
                    : (_biopsyReports[_selectedImageIndex]['url'] != 'NULL'
                          ? const Icon(Icons.edit)
                          : const Icon(Icons.upload_file)),
                label: Text(
                  _biopsyReportFiles[_selectedImageIndex] != null
                      ? "Replace"
                      : (_biopsyReports[_selectedImageIndex]['url'] != 'NULL'
                            ? "Replace"
                            : "Upload"),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  await _viewBiopsyReport(_selectedImageIndex);
                },
                icon: const Icon(Icons.remove_red_eye),
                label: const Text("View"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool readOnly = true,
    bool multiline = false,
    bool noExpand = false,
    bool copiable = false,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      minLines: noExpand ? 1 : (multiline ? 4 : 1),
      maxLines: noExpand ? 1 : 4,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: readOnly && copiable
            ? IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: controller.text));
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text("$label copied")));
                },
              )
            : null,
        border: readOnly ? const OutlineInputBorder() : null,
      ),
      validator: (val) {
        if (required && val == null) {
          return "Select $label";
        }
        return null;
      },
    );
  }

  Widget _buildDropdown<T>(
    String label,
    T? value,
    List<T> values,
    void Function(T?) onChanged, {
    bool required = false,
  }) {
    String displayValue(dynamic e) {
      if (e is Enum) return e.name;
      if (e is bool) return e ? "YES" : "NO";
      return e.toString();
    }

    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: values
          .map((e) => DropdownMenuItem(value: e, child: Text(displayValue(e))))
          .toList(),
      onChanged: onChanged,
      validator: (val) {
        if (required && val == null) {
          return "Select $label";
        }
        return null;
      },
    );
  }

  Widget _buildLesionTypeDropdown(
    String label,
    LesionTypeEnum value,
    void Function(LesionTypeEnum) onChanged,
  ) {
    final allLesionTypes = _lesionDataManager.allLesionTypes;

    return DropdownButtonFormField<LesionTypeEnum>(
      value: value,
      decoration: InputDecoration(labelText: label),
      isExpanded: true,
      items: allLesionTypes
          .map(
            (lesionType) => DropdownMenuItem(
              value: lesionType,
              child: Text(lesionType.key),
            ),
          )
          .toList(),
      onChanged: (val) {
        if (val != null) {
          onChanged(val);
        }
      },
    );
  }

  Widget _buildClinicalDiagnosisDropdown(
    String label,
    ClinicalDiagnosisEnum value,
    LesionTypeEnum currentLesionType,
    void Function(ClinicalDiagnosisEnum) onChanged,
  ) {
    final allDiagnoses = _lesionDataManager.allClinicalDiagnoses;
    final validDiagnoses = _lesionDataManager.getClinicalDiagnosesForLesionType(
      currentLesionType,
    );
    final validDiagnosisKeys = validDiagnoses.map((d) => d.key).toSet();

    return DropdownButtonFormField<ClinicalDiagnosisEnum>(
      value: value,
      decoration: InputDecoration(labelText: label),
      isExpanded: true,
      items: allDiagnoses.map((diagnosis) {
        final isValid = validDiagnosisKeys.contains(diagnosis.key);
        return DropdownMenuItem(
          value: diagnosis,
          child: Opacity(
            opacity: isValid ? 1.0 : 0.4,
            child: Text(
              diagnosis.displayText,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        );
      }).toList(),
      onChanged: (val) {
        if (val != null) {
          onChanged(val);
        }
      },
    );
  }

  Future<void> _viewFile(
    Uint8List fileBytes, {
    String fileType = "NULL",
  }) async {
    try {
      switch (fileType.toLowerCase()) {
        case "jpg":
        case "jpeg":
        case "png":
        // case "gif":
        case "webp":
        case "bmp":
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              backgroundColor: Colors.black,
              insetPadding: EdgeInsets.zero,
              child: Stack(
                children: [
                  // Zoomable image
                  InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5.0,
                    panEnabled: true,
                    scaleEnabled: true,
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    child: SizedBox(
                      width: MediaQuery.of(ctx).size.width,
                      height: MediaQuery.of(ctx).size.height,
                      child: Image.memory(fileBytes, fit: BoxFit.contain),
                    ),
                  ),
                  // Close button
                  Positioned(
                    top: 10,
                    right: 10,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 30,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  // Image title
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "File as ${fileType.toLowerCase()}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // Zoom instructions
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Pinch to zoom • Drag to pan',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
          break;

        case "pdf":
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text("File as ${fileType.toLowerCase()}"),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.8,
                child: SfPdfViewer.memory(fileBytes),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close"),
                ),
              ],
            ),
          );
          break;

        case "doc":
        case "docx":
          final tempDir = await getTemporaryDirectory();
          final filePath = "${tempDir.path}/temp.$fileType";
          final file = File(filePath);
          await file.writeAsBytes(fileBytes);
          final result = await OpenFilex.open(filePath);
          if (result.type != ResultType.done) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "No app available to open ${fileType.toUpperCase()} file",
                ),
              ),
            );
          }
          break;

        default:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Cannot preview file, unsupported file type ${fileType.toLowerCase()}",
              ),
            ),
          );
          break;
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to open file: $e")));
    }
  }

  void _updateBiopsyAgreeWithCOE(int index) {
    final coeLesion = _coeLesionTypes[index];
    final biopsyLesion = _biopsyLesionTypes[index];
    final coeDiagnosis = _coeClinicalDiagnoses[index];
    final biopsyDiagnosis = _biopsyClinicalDiagnoses[index];

    _biopsyAgreeWithCOE[index] = BiopsyAgreeWithCOE.NULL;

    final nullLesionKey = _lesionDataManager.nullLesionType.key;
    final nullDiagnosisKey = _lesionDataManager.nullClinicalDiagnosis.key;

    // Compare using sanitized keys
    if (biopsyLesion.key != nullLesionKey && coeLesion.key != nullLesionKey) {
      _biopsyAgreeWithCOE[index] = (biopsyLesion.key == coeLesion.key)
          ? BiopsyAgreeWithCOE.YES
          : BiopsyAgreeWithCOE.NO;
      if (biopsyDiagnosis.key != nullDiagnosisKey &&
          coeDiagnosis.key != nullDiagnosisKey) {
        _biopsyAgreeWithCOE[index] =
            (biopsyLesion.key == coeLesion.key &&
                biopsyDiagnosis.key == coeDiagnosis.key)
            ? BiopsyAgreeWithCOE.YES
            : BiopsyAgreeWithCOE.NO;
      }
    }

    setState(
      () => _biopsyAgreeWithCOEController[index].text =
          _biopsyAgreeWithCOE[index].name,
    );
  }

  Future<void> _showBiopsyReportSourceActionSheet(int index) async {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                subtitle: const Text('Take a photo of the biopsy report'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickBiopsyReportFromCamera(index);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                subtitle: const Text('Select an image from gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickBiopsyReportFromGallery(index);
                },
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: const Text('Files'),
                subtitle: const Text('Browse for PDF, DOC, or image files'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickBiopsyReportFromFiles(index);
                },
              ),
              if (_biopsyReportFiles[index] != null ||
                  _biopsyReports[index]['url'] != 'NULL')
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text(
                    'Remove Biopsy Report',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _biopsyReportFiles[index] = null;
                      _biopsyReports[index] = {
                        "url": "NULL",
                        "iv": "NULL",
                        "fileType": "NULL",
                      };
                    });
                  },
                ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickBiopsyReportFromCamera(int index) async {
    try {
      final XFile? pickedImage = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );

      if (pickedImage != null) {
        final file = File(pickedImage.path);
        setState(() {
          _biopsyReportFiles[index] = file;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to capture image: $e')));
    }
  }

  Future<void> _pickBiopsyReportFromGallery(int index) async {
    try {
      final XFile? pickedImage = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (pickedImage != null) {
        final file = File(pickedImage.path);
        setState(() {
          _biopsyReportFiles[index] = file;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  Future<void> _pickBiopsyReportFromFiles(int index) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          // 'gif',
          'webp',
          'bmp',
          'pdf',
          'doc',
          'docx',
        ],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        setState(() {
          _biopsyReportFiles[index] = file;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to pick file: $e')));
    }
  }

  Future<void> _viewBiopsyReport(int index) async {
    try {
      final local = _biopsyReportFiles[index];
      if (local != null) {
        final bytes = await local.readAsBytes();
        _viewFile(bytes, fileType: local.path.split('.').last.toLowerCase());
        return;
      }

      final remote = _biopsyReports[index];
      final String url = (remote["url"] ?? "NULL") as String;
      final String iv = (remote["iv"] ?? "NULL") as String;
      final String fileType = (remote["fileType"] ?? "NULL") as String;

      if (url == 'NULL' || url.isEmpty || iv == 'NULL' || iv.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No biopsy report available")),
        );
        return;
      }

      final String encryptedB64 = await StorageService.download(url);

      final Uint8List aesKey = _searchResult!['aes'];
      final String decryptedB64 = CryptoUtils.decryptString(
        encryptedB64,
        iv,
        aesKey,
      );

      final Uint8List fileBytes = base64Decode(decryptedB64);
      _viewFile(fileBytes, fileType: fileType);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to open biopsy report: $e")),
      );
    }
  }

  void _showImageZoomDialog(int imageIndex) {
    if (_images.isEmpty || imageIndex >= _images.length) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              // Zoomable image
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 5.0,
                panEnabled: true,
                scaleEnabled: true,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: SizedBox(
                  width: MediaQuery.of(ctx).size.width,
                  height: MediaQuery.of(ctx).size.height,
                  child: Image.memory(_images[imageIndex], fit: BoxFit.contain),
                ),
              ),
              // Close button
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
              // Image title
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _imageNamesList[imageIndex],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              // Zoom instructions
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Pinch to zoom • Drag to pan',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cancelEditing() async {
    await _resetState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Editing cancelled, no changes are submitted."),
      ),
    );
  }

  Future<void> _submitChanges() async {
    if (_searchResult == null) return;
    if (_isLoading) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Submitting Case Changes"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text("The case is being submitted at the moment."),
            ],
          ),
        );
      },
    );

    try {
      final aesKey = _searchResult!['aes'] as Uint8List;
      final caseId = _searchResult!['case_id'] as String;
      final caseData = _searchResult!['case_data'] as CaseRetrieveModel;

      final List<Map<String, dynamic>> finalBiopsyReports = List.generate(
        9,
        (i) => Map<String, dynamic>.from(_biopsyReports[i]),
      );

      for (int i = 0; i < 9; i++) {
        final local = _biopsyReportFiles[i];
        if (local != null) {
          final bytes = await local.readAsBytes();
          final encrypted = CryptoUtils.encryptString(
            base64Encode(bytes),
            aesKey,
          );
          final uploadUrl = await StorageService.upload(
            encrypted: encrypted["ciphertext"],
            fileName: "${caseId}_$i.enc",
            path: "biopsy_reports",
          );
          finalBiopsyReports[i] = {
            "url": uploadUrl,
            "iv": encrypted["iv"] ?? "NULL",
            "fileType": local.path.split('.').last.toLowerCase(),
          };
        }
      }

      final List<Diagnosis> diagnoses = List.generate(
        9,
        (index) => Diagnosis(
          aiLesionType: _aiLesionTypes[index],
          biopsyClinicalDiagnosis: _biopsyClinicalDiagnoses[index],
          biopsyLesionType: _biopsyLesionTypes[index],
          biopsyReport: finalBiopsyReports[index],
          coeClinicalDiagnosis: _coeClinicalDiagnoses[index],
          coeLesionType: _coeLesionTypes[index],
        ),
      );

      final CaseEditModel editCase = CaseEditModel(
        alcohol: _alcohol ?? caseData.alcohol,
        alcoholDuration:
            _alcoholDurationController.text.isNotEmpty &&
                _alcoholDurationUnit != null
            ? _combineDuration(
                _alcoholDurationController.text,
                _alcoholDurationUnit,
              )
            : caseData.alcoholDuration,
        betelQuid: _betelQuid ?? caseData.betelQuid,
        betelQuidDuration:
            _betelQuidDurationController.text.isNotEmpty &&
                _betelQuidDurationUnit != null
            ? _combineDuration(
                _betelQuidDurationController.text,
                _betelQuidDurationUnit,
              )
            : caseData.betelQuidDuration,
        smoking: _smoking ?? caseData.smoking,
        smokingDuration:
            _smokingDurationController.text.isNotEmpty &&
                _smokingDurationUnit != null
            ? _combineDuration(
                _smokingDurationController.text,
                _smokingDurationUnit,
              )
            : caseData.smokingDuration,
        oralHygieneProductsUsed:
            _oralHygieneProductsUsed ?? caseData.oralHygieneProductsUsed,
        oralHygieneProductTypeUsed:
            _oralHygieneProductTypeUsedController.text.isNotEmpty
            ? _oralHygieneProductTypeUsedController.text
            : caseData.oralHygieneProductTypeUsed,
        slsContainingToothpaste:
            _slsContainingToothpaste ?? caseData.slsContainingToothpaste,
        slsContainingToothpasteUsed:
            _slsContainingToothpasteUsedController.text.isNotEmpty
            ? _slsContainingToothpasteUsedController.text
            : caseData.slsContainingToothpasteUsed,
        additionalComments: _additionalCommentsController.text.isNotEmpty
            ? _additionalCommentsController.text
            : caseData.additionalComments,
        diagnoses: diagnoses,
        aesKey: aesKey,
      );

      final editResult = await DbManagerService.editCase(
        caseId: caseId,
        caseData: editCase,
      );

      if (editResult == caseId) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Case updated successfully")),
        );
        await _resetState();
      } else {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Case submitted but server returned different Case ID: $editResult",
            ),
          ),
        );
      }
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error submitting changes: $e")));
    }
  }

  Future<void> _confirmAction({
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Confirm"),
          ),
        ],
      ),
    );

    if (result == true) {
      onConfirm();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Case"), centerTitle: true),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;
          final maxWidth = isWide ? 1200.0 : double.infinity;

          return Stack(
            children: [
              Center(
                child: Container(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    children: [
                      // Search Bar Section
                      Container(
                        padding: EdgeInsets.all(isWide ? 24.0 : 16.0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                enabled: !_isLoading,
                                decoration: InputDecoration(
                                  labelText: "Enter Case ID to Edit",
                                  hintText: "Type case ID here...",
                                  prefixIcon: const Icon(Icons.search),
                                  border: const OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Theme.of(
                                    context,
                                  ).scaffoldBackgroundColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: _isLoading ? null : _searchCase,
                              icon: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.search),
                              label: const Text("Search"),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Content Area
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(isWide ? 24.0 : 16.0),
                          child: Column(
                            children: [
                              if (_errorMessage != null)
                                Card(
                                  elevation: 2,
                                  color: Colors.red.shade50,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.error_outline,
                                          color: Colors.red,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            _errorMessage!,
                                            style: const TextStyle(
                                              color: Colors.red,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (_searchResult != null)
                                _buildCaseForm(_searchResult!),
                            ],
                          ),
                        ),
                      ),

                      // Action Buttons
                      if (_searchResult != null)
                        Container(
                          padding: EdgeInsets.all(isWide ? 24.0 : 16.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 4,
                                offset: const Offset(0, -2),
                              ),
                            ],
                          ),
                          child: isWide
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        _confirmAction(
                                          title: "Cancel Editing",
                                          message:
                                              "Are you sure you want to cancel editing? All changes will be lost.",
                                          onConfirm: _cancelEditing,
                                        );
                                      },
                                      icon: const Icon(Icons.cancel),
                                      label: const Text("Cancel Editing"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.grey,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 16,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        _confirmAction(
                                          title: "Submit Changes",
                                          message:
                                              "Are you sure you want to submit the changes?",
                                          onConfirm: _submitChanges,
                                        );
                                      },
                                      icon: const Icon(Icons.save),
                                      label: const Text("Submit Changes"),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          _confirmAction(
                                            title: "Cancel Editing",
                                            message:
                                                "Are you sure you want to cancel editing? All changes will be lost.",
                                            onConfirm: _cancelEditing,
                                          );
                                        },
                                        icon: const Icon(Icons.cancel),
                                        label: const Text("Cancel"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.grey,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          _confirmAction(
                                            title: "Submit Changes",
                                            message:
                                                "Are you sure you want to submit the changes?",
                                            onConfirm: _submitChanges,
                                          );
                                        },
                                        icon: const Icon(Icons.save),
                                        label: const Text("Submit"),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                    ],
                  ),
                ),
              ),

              // Loading overlay with modal barrier
              if (_isLoading)
                ModalBarrier(
                  dismissible: false,
                  color: Colors.black.withValues(alpha: 0.3),
                ),
              if (_isLoading)
                Center(
                  child: Card(
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            "Loading case data...",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "Decrypting and processing case information.\nThis may take a few seconds.",
                            style: TextStyle(fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
