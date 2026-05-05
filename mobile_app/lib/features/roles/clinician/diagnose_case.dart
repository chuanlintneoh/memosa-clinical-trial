// Diagnose a case
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mobile_app/core/models/case.dart';
import 'package:mobile_app/core/models/lesion_data.dart';
import 'package:mobile_app/core/services/dbmanager.dart';
import 'package:mobile_app/core/services/storage.dart';
import 'package:mobile_app/core/utils/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DiagnoseCaseScreen extends StatefulWidget {
  final Map<String, dynamic> caseInfo;
  final int caseIndex;

  const DiagnoseCaseScreen({
    super.key,
    required this.caseInfo,
    required this.caseIndex,
  });

  @override
  State<DiagnoseCaseScreen> createState() => _DiagnoseCaseScreenState();
}

class _DiagnoseCaseScreenState extends State<DiagnoseCaseScreen> {
  CaseRetrieveModel? _caseData;
  Map<String, dynamic>? _processedCaseInfo;

  final TextEditingController _caseIdController = TextEditingController();
  final TextEditingController _createdAtController = TextEditingController();
  final TextEditingController _submittedAtController = TextEditingController();
  final TextEditingController _createdByController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();
  final TextEditingController _ethnicityController = TextEditingController();
  final TextEditingController _smokingController = TextEditingController();
  final TextEditingController _smokingDurationController =
      TextEditingController();
  final TextEditingController _betelQuidController = TextEditingController();
  final TextEditingController _betelQuidDurationController =
      TextEditingController();
  final TextEditingController _alcoholController = TextEditingController();
  final TextEditingController _alcoholDurationController =
      TextEditingController();
  final TextEditingController _lesionClinicalPresentationController =
      TextEditingController();
  final TextEditingController _chiefComplaintController =
      TextEditingController();
  final TextEditingController _presentingComplaintHistoryController =
      TextEditingController();
  final TextEditingController _medicationHistoryController =
      TextEditingController();
  final TextEditingController _medicalHistoryController =
      TextEditingController();
  final TextEditingController _slsContainingToothpasteController =
      TextEditingController();
  final TextEditingController _slsContainingToothpasteUsedController =
      TextEditingController();
  final TextEditingController _oralHygieneProductsUsedController =
      TextEditingController();
  final TextEditingController _oralHygieneProductTypeUsedController =
      TextEditingController();
  final TextEditingController _additionalCommentsController =
      TextEditingController();
  List<Uint8List> _images = [];

  final _formKey = GlobalKey<FormState>();
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
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
  late List<LesionTypeEnum> _lesionTypes;
  late List<ClinicalDiagnosisEnum> _clinicalDiagnoses;
  final List<bool> _lowQualityFlags = List.filled(9, false);
  final List<PoorQualityReason?> _lowQualityReasons = List.filled(9, null);
  bool _isUpdating = false; // Prevent circular updates
  final LesionDataManager _lesionDataManager = LesionDataManager();
  bool _isLoading = true; // Track loading state

  @override
  void initState() {
    super.initState();
    _initializeLesionData();
  }

  Future<void> _initializeLesionData() async {
    try {
      await _lesionDataManager.loadData();
      setState(() {
        _lesionTypes = List.filled(9, _lesionDataManager.nullLesionType);
        _clinicalDiagnoses = List.filled(
          9,
          _lesionDataManager.nullClinicalDiagnosis,
        );
      });

      // Decrypt case data if encrypted
      if (!mounted) return;
      final processedData = await _processRawCaseData(widget.caseInfo);

      if (!mounted) return;
      setState(() {
        _processedCaseInfo = processedData;
        _caseData = processedData["case_data"];
      });

      _populateData();
    } catch (e) {
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error loading case: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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

  void _populateData() {
    if (_caseData == null) return;

    _caseIdController.text =
        _processedCaseInfo?["case_id"] ?? widget.caseInfo["case_id"] ?? "";
    _createdAtController.text = _caseData!.createdAt;
    _submittedAtController.text = _caseData!.submittedAt;
    _createdByController.text = _caseData!.createdBy;
    _ageController.text = _caseData!.age;
    _genderController.text = _caseData!.gender;
    _ethnicityController.text = _caseData!.ethnicity;
    _smokingController.text = _caseData!.smoking.toShortString;
    _smokingDurationController.text = _caseData!.smokingDuration;
    _betelQuidController.text = _caseData!.betelQuid.toShortString;
    _betelQuidDurationController.text = _caseData!.betelQuidDuration;
    _alcoholController.text = _caseData!.alcohol.toShortString;
    _alcoholDurationController.text = _caseData!.alcoholDuration;
    _lesionClinicalPresentationController.text =
        _caseData!.lesionClinicalPresentation;
    _chiefComplaintController.text = _caseData!.chiefComplaint;
    _presentingComplaintHistoryController.text =
        _caseData!.presentingComplaintHistory;
    _medicationHistoryController.text = _caseData!.medicationHistory;
    _medicalHistoryController.text = _caseData!.medicalHistory;
    _slsContainingToothpasteController.text = _caseData!.slsContainingToothpaste
        ? "YES"
        : "NO";
    _slsContainingToothpasteUsedController.text =
        _caseData!.slsContainingToothpasteUsed;
    _oralHygieneProductsUsedController.text = _caseData!.oralHygieneProductsUsed
        ? "YES"
        : "NO";
    _oralHygieneProductTypeUsedController.text =
        _caseData!.oralHygieneProductTypeUsed;
    _additionalCommentsController.text = _caseData!.additionalComments;
    _images = _caseData!.images;
  }

  @override
  void dispose() {
    _caseIdController.dispose();
    _createdAtController.dispose();
    _submittedAtController.dispose();
    _createdByController.dispose();
    _ageController.dispose();
    _genderController.dispose();
    _ethnicityController.dispose();
    _smokingController.dispose();
    _smokingDurationController.dispose();
    _betelQuidController.dispose();
    _betelQuidDurationController.dispose();
    _alcoholController.dispose();
    _alcoholDurationController.dispose();
    _lesionClinicalPresentationController.dispose();
    _chiefComplaintController.dispose();
    _presentingComplaintHistoryController.dispose();
    _medicationHistoryController.dispose();
    _medicalHistoryController.dispose();
    _slsContainingToothpasteController.dispose();
    _slsContainingToothpasteUsedController.dispose();
    _oralHygieneProductsUsedController.dispose();
    _oralHygieneProductTypeUsedController.dispose();
    _additionalCommentsController.dispose();
    super.dispose();
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

  Widget _buildDiagnosisForm() {
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
        _buildPatientInfoSection(),
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
                  _buildPatientInfoSection(),
                  _buildHabitsSection(),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                children: [
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
                copiable: true,
                noExpand: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                _createdByController,
                "Created By",
                copiable: true,
                noExpand: true,
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

  Widget _buildPatientInfoSection() {
    return _buildSectionCard(
      title: 'Patient Demographics',
      icon: Icons.person_outline,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTextField(_ageController, "Age", noExpand: true),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                _genderController,
                "Gender",
                noExpand: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                _ethnicityController,
                "Ethnicity",
                noExpand: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHabitsSection() {
    return _buildSectionCard(
      title: 'Habits & Lifestyle',
      icon: Icons.smoking_rooms_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                _smokingController,
                "Smoking",
                noExpand: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                _smokingDurationController,
                "Duration",
                noExpand: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                _betelQuidController,
                "Betel Quid",
                noExpand: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                _betelQuidDurationController,
                "Duration",
                noExpand: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                _alcoholController,
                "Alcohol",
                noExpand: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                _alcoholDurationController,
                "Duration",
                noExpand: true,
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
              child: _buildTextField(
                _slsContainingToothpasteController,
                "SLS Toothpaste",
                noExpand: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 65,
              child: _buildTextField(
                _slsContainingToothpasteUsedController,
                "Type",
                noExpand: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 35,
              child: _buildTextField(
                _oralHygieneProductsUsedController,
                "Other Products",
                noExpand: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 65,
              child: _buildTextField(
                _oralHygieneProductTypeUsedController,
                "Type",
                noExpand: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          _additionalCommentsController,
          "Additional Comments",
          copiable: true,
        ),
      ],
    );
  }

  Widget _buildDiagnosisSection() {
    return _buildSectionCard(
      title: 'Provide Diagnosis',
      icon: Icons.fact_check_outlined,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange, width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Please provide diagnosis for all 9 images. Incomplete images are marked with *',
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
            labelText: "Select Image to Diagnose",
            border: OutlineInputBorder(),
          ),
          items: List.generate(_imageNamesList.length, (i) {
            final incomplete =
                _lesionTypes[i].key == _lesionDataManager.nullLesionType.key ||
                _clinicalDiagnoses[i].key ==
                    _lesionDataManager.nullClinicalDiagnosis.key;

            return DropdownMenuItem(
              value: i,
              child: Row(
                children: [
                  if (incomplete)
                    const Icon(Icons.warning_amber, color: Colors.red, size: 18)
                  else
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 18,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _imageNamesList[i],
                    style: TextStyle(
                      color: incomplete ? Colors.red : null,
                      fontWeight: incomplete
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            );
          }),
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
        const SizedBox(height: 20),
        _buildLesionTypeDropdown(
          "Lesion Type",
          _lesionTypes[_selectedImageIndex],
          (val) {
            if (_isUpdating) return;
            _isUpdating = true;

            setState(() {
              _lesionTypes[_selectedImageIndex] = val;

              // If lesion type is NULL, set clinical diagnosis to NULL
              if (val.key == _lesionDataManager.nullLesionType.key) {
                _clinicalDiagnoses[_selectedImageIndex] =
                    _lesionDataManager.nullClinicalDiagnosis;
              } else {
                final validDiagnoses = _lesionDataManager
                    .getClinicalDiagnosesForLesionType(val);

                final actualDiagnosis = validDiagnoses
                    .where(
                      (d) =>
                          d.key != _lesionDataManager.nullClinicalDiagnosis.key,
                    )
                    .toList();

                if (actualDiagnosis.length == 1) {
                  _clinicalDiagnoses[_selectedImageIndex] =
                      actualDiagnosis.first;
                } else {
                  // Check if current diagnosis belongs to new lesion type
                  final currentDiagnosis =
                      _clinicalDiagnoses[_selectedImageIndex];
                  if (!_lesionDataManager.diagnosisBelongsToLesionType(
                    currentDiagnosis,
                    val,
                  )) {
                    // Reset to NULL if diagnosis doesn't belong to new lesion type
                    _clinicalDiagnoses[_selectedImageIndex] =
                        _lesionDataManager.nullClinicalDiagnosis;
                  }
                }
              }
            });

            _isUpdating = false;
          },
        ),
        const SizedBox(height: 16),
        _buildClinicalDiagnosisDropdown(
          "Clinical Diagnosis",
          _clinicalDiagnoses[_selectedImageIndex],
          _lesionTypes[_selectedImageIndex],
          (val) {
            if (_isUpdating) return;
            _isUpdating = true;

            setState(() {
              _clinicalDiagnoses[_selectedImageIndex] = val;

              // If diagnosis is NOT NULL, update lesion type to match
              if (val.key != _lesionDataManager.nullClinicalDiagnosis.key) {
                final lesionType = _lesionDataManager
                    .findLesionTypeForDiagnosis(val);
                if (lesionType != null) {
                  _lesionTypes[_selectedImageIndex] = lesionType;
                }
              }
              // If diagnosis is NULL, don't change lesion type
            });

            _isUpdating = false;
          },
        ),
        const SizedBox(height: 16),
        Card(
          color: _lowQualityFlags[_selectedImageIndex]
              ? Colors.orange.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.05),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text("Low Quality Image?"),
                subtitle: const Text("Mark if image quality is poor"),
                value: _lowQualityFlags[_selectedImageIndex],
                onChanged: (val) {
                  setState(() {
                    _lowQualityFlags[_selectedImageIndex] = val;
                    // Reset reason if unchecked
                    if (!val) {
                      _lowQualityReasons[_selectedImageIndex] = null;
                    }
                  });
                },
              ),
              if (_lowQualityFlags[_selectedImageIndex])
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: DropdownButtonFormField<PoorQualityReason>(
                    value: _lowQualityReasons[_selectedImageIndex],
                    decoration: const InputDecoration(
                      labelText: "Reason for Low Quality",
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    isExpanded: true,
                    items: PoorQualityReason.values
                        .map(
                          (reason) => DropdownMenuItem(
                            value: reason,
                            child: Text(
                              reason.name
                                  .replaceAll('_', ' ')
                                  .toLowerCase()
                                  .split(' ')
                                  .map(
                                    (word) =>
                                        word[0].toUpperCase() +
                                        word.substring(1),
                                  )
                                  .join(' '),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        _lowQualityReasons[_selectedImageIndex] = val;
                      });
                    },
                    validator: (val) {
                      if (_lowQualityFlags[_selectedImageIndex] &&
                          val == null) {
                        return "Please select a reason for low quality";
                      }
                      return null;
                    },
                  ),
                ),
            ],
          ),
        ),
        FormField<void>(
          initialValue: null,
          validator: (_) {
            final nullLesionKey = _lesionDataManager.nullLesionType.key;
            final nullDiagnosisKey =
                _lesionDataManager.nullClinicalDiagnosis.key;

            final missingLesion = _lesionTypes
                .asMap()
                .entries
                .where((e) => e.value.key == nullLesionKey)
                .map((e) => e.key + 1)
                .toList();
            final missingDiag = _clinicalDiagnoses
                .asMap()
                .entries
                .where((e) => e.value.key == nullDiagnosisKey)
                .map((e) => e.key + 1)
                .toList();

            if (missingLesion.isNotEmpty || missingDiag.isNotEmpty) {
              final parts = <String>[];
              if (missingLesion.isNotEmpty) {
                parts.add('Lesion type missing: ${missingLesion.join(', ')}');
              }
              if (missingDiag.isNotEmpty) {
                parts.add(
                  'Clinical diagnosis missing: ${missingDiag.join(', ')}',
                );
              }
              return parts.join('. ');
            }
            return null;
          },
          builder: (field) {
            return field.hasError
                ? Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              field.errorText!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool readOnly = true,
    bool copiable = false,
    bool multiline = false,
    bool noExpand = false,
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
      validator: (value) {
        if (required && (value == null || value.isEmpty)) {
          return "Enter $label";
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
    bool required = true,
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
      validator: (val) {
        if (val == null || val.key == _lesionDataManager.nullLesionType.key) {
          return "Select $label";
        }
        return null;
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
      validator: (val) {
        if (val == null ||
            val.key == _lesionDataManager.nullClinicalDiagnosis.key) {
          return "Select $label";
        }
        return null;
      },
    );
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

  void _cancelDiagnosis() {
    Navigator.pop(context, {'action': 'cancel', 'index': widget.caseIndex});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Diagnosis cancelled, no changes are submitted."),
      ),
    );
  }

  Future<void> _submitDiagnosis() async {
    if (!_formKey.currentState!.validate()) {
      // Enable autovalidation so errors persist when scrolling
      // Wait for the next frame to avoid ChangeNotifier disposal issues
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _autovalidateMode = AutovalidateMode.always;
          });
        }
      });

      int firstMissingLesion = _lesionTypes.indexWhere(
        (t) => t.key == _lesionDataManager.nullLesionType.key,
      );
      int firstMissingDiag = _clinicalDiagnoses.indexWhere(
        (d) => d.key == _lesionDataManager.nullClinicalDiagnosis.key,
      );

      int firstMissing = -1;
      if (firstMissingLesion != -1 && firstMissingDiag != -1) {
        firstMissing = (firstMissingLesion < firstMissingDiag)
            ? firstMissingLesion
            : firstMissingDiag;
      } else if (firstMissingLesion != -1) {
        firstMissing = firstMissingLesion;
      } else if (firstMissingDiag != -1) {
        firstMissing = firstMissingDiag;
      }

      if (firstMissing != -1) {
        setState(() {
          _selectedImageIndex = firstMissing;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please fill lesion type and clinical diagnosis for all 9 images. Jumped to first missing.',
            ),
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text("Submitting Diagnosis"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text("Your diagnosis is being submitted at the moment."),
            ],
          ),
        );
      },
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final String userId =
          prefs.getString("userId") ??
          FirebaseAuth.instance.currentUser?.uid ??
          "unknown";
      if (userId == "unknown") {
        throw Exception("User ID not found. Please log in and try again.");
      }

      if (widget.caseInfo["case_id"] == null) {
        throw Exception("Case ID is missing. Please refresh and try again.");
      }
      String caseId = widget.caseInfo["case_id"];

      final List<ClinicianDiagnosis> clinicianDiagnoses = List.generate(
        9,
        (index) => ClinicianDiagnosis(
          clinicianID: userId,
          clinicalDiagnosis: _clinicalDiagnoses[index],
          lesionType: _lesionTypes[index],
          lowQuality: _lowQualityFlags[index],
          lowQualityReason: _lowQualityReasons[index],
        ),
      );

      final CaseDiagnosisModel diagnoseCase = CaseDiagnosisModel(
        clinicianDiagnoses: clinicianDiagnoses,
      );

      final result = await DbManagerService.diagnoseCase(
        caseId: caseId,
        diagnoses: diagnoseCase,
      );

      if (result == caseId) {
        Navigator.of(context, rootNavigator: true).pop();
        Navigator.pop(context, {
          'action': 'diagnosed',
          'index': widget.caseIndex,
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Diagnosis submitted successfully.")),
        );
      } else {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Unexpected response from server")),
        );
      }
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to submit diagnosis: $e")));
    }
  }

  bool _areAllDiagnosesComplete() {
    final nullLesionKey = _lesionDataManager.nullLesionType.key;
    final nullDiagnosisKey = _lesionDataManager.nullClinicalDiagnosis.key;

    for (int i = 0; i < 9; i++) {
      if (_lesionTypes[i].key == nullLesionKey ||
          _clinicalDiagnoses[i].key == nullDiagnosisKey) {
        return false;
      }
    }
    return true;
  }

  int? _findNextUndiagnosedImage() {
    final nullLesionKey = _lesionDataManager.nullLesionType.key;
    final nullDiagnosisKey = _lesionDataManager.nullClinicalDiagnosis.key;

    // Start from the next image after current
    for (int i = _selectedImageIndex + 1; i < 9; i++) {
      if (_lesionTypes[i].key == nullLesionKey ||
          _clinicalDiagnoses[i].key == nullDiagnosisKey) {
        return i;
      }
    }

    // Wrap around to check from the beginning
    for (int i = 0; i < _selectedImageIndex; i++) {
      if (_lesionTypes[i].key == nullLesionKey ||
          _clinicalDiagnoses[i].key == nullDiagnosisKey) {
        return i;
      }
    }

    return null;
  }

  void _goToNextUndiagnosedImage() {
    final nextIndex = _findNextUndiagnosedImage();
    if (nextIndex != null) {
      setState(() {
        _selectedImageIndex = nextIndex;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Moved to ${_imageNamesList[nextIndex]}'),
          duration: const Duration(seconds: 1),
        ),
      );
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
      appBar: AppBar(title: const Text("Diagnose Case"), centerTitle: true),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Loading case data..."),
                ],
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                final maxWidth = isWide ? 1200.0 : double.infinity;

                return Center(
                  child: Container(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Form(
                      key: _formKey,
                      autovalidateMode: _autovalidateMode,
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              padding: EdgeInsets.all(isWide ? 24.0 : 16.0),
                              child: _buildDiagnosisForm(),
                            ),
                          ),
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
                                            title: "Cancel Diagnosis",
                                            message:
                                                "Are you sure you want to cancel diagnosis? All progress will be lost.",
                                            onConfirm: _cancelDiagnosis,
                                          );
                                        },
                                        icon: const Icon(Icons.cancel),
                                        label: const Text("Cancel Diagnosis"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.grey,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 16,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      _areAllDiagnosesComplete()
                                          ? ElevatedButton.icon(
                                              onPressed: () {
                                                _confirmAction(
                                                  title: "Submit Diagnosis",
                                                  message:
                                                      "Are you sure you want to submit diagnosis?",
                                                  onConfirm: _submitDiagnosis,
                                                );
                                              },
                                              icon: const Icon(Icons.check),
                                              label: const Text(
                                                "Submit Diagnosis",
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 24,
                                                      vertical: 16,
                                                    ),
                                              ),
                                            )
                                          : ElevatedButton.icon(
                                              onPressed:
                                                  _goToNextUndiagnosedImage,
                                              icon: const Icon(
                                                Icons.arrow_forward,
                                              ),
                                              label: const Text(
                                                "Next Undiagnosed",
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.orange,
                                                padding:
                                                    const EdgeInsets.symmetric(
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
                                              title: "Cancel Diagnosis",
                                              message:
                                                  "Are you sure you want to cancel diagnosis? All progress will be lost.",
                                              onConfirm: _cancelDiagnosis,
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
                                        child: _areAllDiagnosesComplete()
                                            ? ElevatedButton.icon(
                                                onPressed: () {
                                                  _confirmAction(
                                                    title: "Submit Diagnosis",
                                                    message:
                                                        "Are you sure you want to submit diagnosis?",
                                                    onConfirm: _submitDiagnosis,
                                                  );
                                                },
                                                icon: const Icon(Icons.check),
                                                label: const Text("Submit"),
                                              )
                                            : ElevatedButton.icon(
                                                onPressed:
                                                    _goToNextUndiagnosedImage,
                                                icon: const Icon(
                                                  Icons.arrow_forward,
                                                ),
                                                label: const Text("Next"),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.orange,
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
