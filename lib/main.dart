import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:io';
import 'dart:convert';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const platform = MethodChannel('com.example.main/platform_channel');
  final ImagePicker _picker = ImagePicker();
  File? _image;
  String _keyPairMessage = "";
  String _verificationResult = "";
  String _signedKey = "";
  String? _selectedOption;
  DateTime? _selectedDate;

  final TextEditingController _aliasPrefixController = TextEditingController();
  final TextEditingController _signatureController = TextEditingController();
  List<String> _dropdownOptions = ['RSA', 'PKCS', 'OAEP'];

  @override
  void initState() {
    super.initState();
    _fetchDropdownOptions();
  }

  Future<void> _handleDropdownChange(String? newValue) async {
    setState(() {
      _selectedOption = newValue;
    });
  }

  Future<void> _fetchDropdownOptions() async {
    try {
      final response = await http.get(Uri.parse('http://example.com/options'));
      if (response.statusCode == 200) {
        final List<String> options = List<String>.from(jsonDecode(response.body));
        setState(() {
          _dropdownOptions = options;
        });
      } else {
        print('Failed to fetch options');
      }
    } catch (e) {
      print('Error fetching options: $e');
    }
  }

  Future<void> _checkAndGenerateKeyPair() async {
    String aliasPrefix = _aliasPrefixController.text;
    if (aliasPrefix.isEmpty) {
      setState(() {
        _keyPairMessage = "Alias prefix cannot be empty.";
      });
      return;
    }

    String message;
    try {
      final String result = await platform.invokeMethod('checkAndGenerateKeyPair', {
        'aliasPrefix': aliasPrefix,
      });
      message = result;

      await _sendMessageToServer(message);
    } on PlatformException catch (e) {
      message = "Failed to check and generate key pair: '${e.message}'.";
    }

    setState(() {
      _keyPairMessage = message;
    });
  }

  Future<void> _sendMessageToServer(String message) async {
    try {
      final response = await http.post(
        Uri.parse('http://192.168.119.67:3000/keypair-success'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          'message': message,
        }),
      );

      if (response.statusCode == 200) {
        print('Message sent to server: $message');
      } else {
        print('Failed to send message to server: ${response.reasonPhrase}');
      }
    } catch (e) {
      print('Error sending message to server: $e');
    }
  }

  Future<void> _getImageFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        setState(() {
          _image = File(image.path);
        });
      }
    } catch (e) {
      setState(() {
      });
    }
  }

  Future<void> _uploadImageToServer() async {
    if (_image == null) {
      setState(() {
      });
      return;
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://192.168.119.67:3000/upload-image'),
      );

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          await _image!.readAsBytes(),
          filename: _image!.path.split('/').last,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        setState(() {
        });
        print("Server response: $responseBody");
      } else {
        setState(() {
        });
        print("Failed to upload image: ${response.reasonPhrase} - $responseBody");
      }
    } catch (e) {
      setState(() {
      });
    }
  }

  Future<void> _requestBiometricAuth() async {
    if (_image == null) {
      setState(() {
      });
      return;
    }

    try {
      await _uploadImageToServer();

      final imageBytes = await _image!.readAsBytes();
      final imageBase64 = base64Encode(imageBytes);

      final String result = await platform.invokeMethod('requestBiometricAuth', {
        'imageBase64': imageBase64,
      });

      setState(() {
        _signedKey = result;
      });
    } on PlatformException {
      setState(() {
      });
    }
  }

  Future<void> _copySignedKey() async {
    try {
      if (_signedKey.isEmpty) {
        setState(() {
        });
        return;
      }

      await Clipboard.setData(ClipboardData(text: _signedKey));

      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData != null && clipboardData.text == _signedKey) {
        setState(() {
        });
      } else {
        setState(() {
        });
      }

      await _sendSignedKeyToServer(_signedKey);
    } on PlatformException {
      setState(() {
      });
    }
  }

  Future<void> _sendSignedKeyToServer(String signedKey) async {
    try {
      final response = await http.post(
        Uri.parse('http://192.168.119.67:3000/signed-key'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          'signedKey': signedKey,
        }),
      );

      if (response.statusCode == 200) {
        print('Signed key sent to server successfully.');
      } else {
        print('Failed to send signed key to server: ${response.reasonPhrase}');
      }
    } catch (e) {
      print('Error sending signed key to server: $e');
    }
  }

  Future<void> _verifySignature() async {
    try {
      final String signedKey = _signatureController.text;

      if (_image == null) {
        setState(() {
          _verificationResult = "No image selected.";
        });
        return;
      }

      final imageBytes = await _image!.readAsBytes();
      final imageBase64 = base64Encode(imageBytes);

      final String verificationResult = await platform.invokeMethod('verifySignature', {
        'signedKeyInput': signedKey,
        'imageBase64': imageBase64,
      });

      setState(() {
        _verificationResult = verificationResult;
      });
    } on PlatformException catch (e) {
      setState(() {
        _verificationResult = "Failed to verify signature: '${e.message}'.";
      });
    }
  }

  Future<void> _selectDate() async {
    DateTime currentDate = DateTime.now();
    DateTime initialDate = _selectedDate ?? currentDate;

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );

    if (pickedDate != null && pickedDate != initialDate) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  @override
  void dispose() {
    _aliasPrefixController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Trust in your Pocket'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                DropdownButton<String>(
                  value: _selectedOption,
                  hint: Text('Select an Option'),
                  items: _dropdownOptions.map((String option) {
                    return DropdownMenuItem<String>(
                      value: option,
                      child: Text(option),
                    );
                  }).toList(),
                  onChanged: _handleDropdownChange,
                ),
                SizedBox(height: 20),
                Text('Selected Option: $_selectedOption'),
                SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _selectedDate != null
                          ? 'Key Expiry Date:'
                          : 'No Expiry Date Selected',
                      style: TextStyle(fontSize: 16),
                    ),
                    SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _selectDate,
                      child: Text(
                        _selectedDate != null
                            ? _selectedDate!.toLocal().toString().split(' ')[0]
                            : 'Select Expiry Date',
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),

                TextField(
                  controller: _aliasPrefixController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Enter Alias Prefix',
                  ),
                ),
                SizedBox(height: 20),

                // Check and Generate Key Pair Button
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: _checkAndGenerateKeyPair,
                      child: Text('Check and Generate Key Pair'),
                    ),
                    Text(_keyPairMessage, style: TextStyle(color: Colors.green)),
                  ],
                ),
                SizedBox(height: 20),

                // Capture Image Button
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: _getImageFromCamera,
                      child: Text('Capture Image'),
                    ),
                  ],
                ),
                SizedBox(height: 20),

                if (_image != null) ...[
                  Image.file(_image!),
                  SizedBox(height: 20),
                ],

                // Biometric Authentication Button
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: _requestBiometricAuth,
                      child: Text('Sign Image with Biometric Authentication'),
                    ),

                  ],
                ),
                SizedBox(height: 20),

                // Display Signed Key
                if (_signedKey.isNotEmpty) ...[
                  Text(
                    'Signed Key: $_signedKey',
                    style: TextStyle(fontSize: 16),
                  ),
                  ElevatedButton(
                    onPressed: _copySignedKey,
                    child: Text('Copy Signed Key to Clipboard'),
                  ),
                  SizedBox(height: 20),
                ],

                // Verify Signature Button
                Column(
                  children: [
                    TextField(
                      controller: _signatureController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Paste Signed Key',
                      ),
                      maxLines: 1,
                    ),
                    ElevatedButton(
                      onPressed: _verifySignature,
                      child: Text('Verify Signature'),
                    ),
                    Text(_verificationResult, style: TextStyle(color: Colors.green)),
                  ],
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
