// lib/settings_page.dart

import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:flutter_image_compress/flutter_image_compress.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final ageController = TextEditingController();
  final heightController = TextEditingController();
  final weightController = TextEditingController();
  final chestController = TextEditingController();
  final addressController = TextEditingController();
  final phoneController = TextEditingController();

  String? _selectedGender;

  final ImagePicker _picker = ImagePicker();

  bool isLoading = false;
  String? _photoUrl;
  File? _localAvatarFile;
  bool _uploadingAvatar = false;

  static const String _cloudName = 'dwtwxcmcn';
  static const String _uploadPreset = 'sports';

  final Color primaryBlue = const Color(0xFF00BFFF);
  final Color darkBg = const Color(0xFF000000);
  final Color cardBg = const Color(0xFF111111);

  @override
  void initState() {
    super.initState();
    loadUserData();
  }

  Future<void> loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!doc.exists) return;

    final data = doc.data()!;

    nameController.text = data['name'] ?? '';
    ageController.text = data['age']?.toString() ?? '';
    heightController.text = data['height']?.toString() ?? '';
    weightController.text = data['weight']?.toString() ?? '';
    chestController.text = data['chest']?.toString() ?? '';
    addressController.text = data['address'] ?? '';
    phoneController.text = data['phone'] ?? '';
    _selectedGender = data['gender'];
    _photoUrl = data['photoUrl'];

    setState(() {});
  }

  Future<void> saveUserData() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => isLoading = true);

    try {
      final payload = <String, dynamic>{
        'name': nameController.text.trim(),
        'address': addressController.text.trim(),
        'phone': phoneController.text.trim(),
        'gender': _selectedGender,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final age = int.tryParse(ageController.text.trim());
      final height = double.tryParse(heightController.text.trim());
      final weight = double.tryParse(weightController.text.trim());
      final chest = double.tryParse(chestController.text.trim());

      if (age != null) payload['age'] = age;
      if (height != null) payload['height'] = height;
      if (weight != null) payload['weight'] = weight;
      if (chest != null) payload['chest'] = chest;
      if (_photoUrl != null) payload['photoUrl'] = _photoUrl;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(payload, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile Updated Successfully")),
        );
      }
    } catch (e) {
      debugPrint("Save error: $e");
    }

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked == null) return;

    File file = File(picked.path);

    final compressed = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      quality: 70,
    );

    if (compressed != null) {
      final tmp = File('${file.parent.path}/tmp_${p.basename(file.path)}');
      await tmp.writeAsBytes(compressed);
      file = tmp;
    }

    setState(() => _localAvatarFile = file);
    await _uploadToCloudinary(file);
  }

  Future<void> _uploadToCloudinary(File file) async {
    setState(() => _uploadingAvatar = true);

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
    );

    final request = http.MultipartRequest('POST', uri);
    request.fields['upload_preset'] = _uploadPreset;
    request.fields['folder'] = 'avatars';

    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();
    final res = await http.Response.fromStream(response);
    final jsonBody = json.decode(res.body);

    final secureUrl = jsonBody['secure_url'];

    final user = FirebaseAuth.instance.currentUser;

    await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
      'photoUrl': secureUrl,
    }, SetOptions(merge: true));

    setState(() {
      _photoUrl = secureUrl;
      _localAvatarFile = null;
      _uploadingAvatar = false;
    });
  }

  Widget buildTextField(
    String label,
    TextEditingController controller,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: TextFormField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: primaryBlue),
          labelText: label,
          labelStyle: TextStyle(color: primaryBlue),
          filled: true,
          fillColor: cardBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        validator: (v) => v == null || v.isEmpty ? "Enter $label" : null,
      ),
    );
  }

  Widget buildGenderDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: DropdownButtonFormField<String>(
        initialValue: _selectedGender,
        dropdownColor: cardBg,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.person_outline, color: primaryBlue),
          labelText: "Gender",
          labelStyle: TextStyle(color: primaryBlue),
          filled: true,
          fillColor: cardBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        items: const [
          DropdownMenuItem(value: "male", child: Text("Male")),
          DropdownMenuItem(value: "female", child: Text("Female")),
        ],
        onChanged: (value) {
          setState(() => _selectedGender = value);
        },
        validator: (value) => value == null ? "Select Gender" : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: darkBg,
        elevation: 0,
        title: const Text("Profile Settings"),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryBlue,
        onPressed: isLoading ? null : saveUserData,
        label: isLoading ? const Text("Saving...") : const Text("Save"),
        icon: const Icon(Icons.check),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 20),

              /// Profile Photo
              Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: primaryBlue,
                    child: CircleAvatar(
                      radius: 55,
                      backgroundImage: _localAvatarFile != null
                          ? FileImage(_localAvatarFile!)
                          : (_photoUrl != null
                                    ? NetworkImage(_photoUrl!)
                                    : null)
                                as ImageProvider?,
                      child: _photoUrl == null && _localAvatarFile == null
                          ? const Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: InkWell(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (_) => Wrap(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.camera_alt),
                                title: const Text("Camera"),
                                onTap: () {
                                  Navigator.pop(context);
                                  _pickAvatar(ImageSource.camera);
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.photo),
                                title: const Text("Gallery"),
                                onTap: () {
                                  Navigator.pop(context);
                                  _pickAvatar(ImageSource.gallery);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: primaryBlue,
                        child: _uploadingAvatar
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.edit,
                                size: 18,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              buildTextField("Full Name", nameController, Icons.person),
              buildTextField("Age", ageController, Icons.cake),

              buildGenderDropdown(),

              buildTextField("Phone", phoneController, Icons.phone),
              buildTextField("Address", addressController, Icons.home),
              buildTextField("Height (cm)", heightController, Icons.height),
              buildTextField(
                "Weight (kg)",
                weightController,
                Icons.monitor_weight,
              ),
              buildTextField("Chest (cm)", chestController, Icons.straighten),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}
