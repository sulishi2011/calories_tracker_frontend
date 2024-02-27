import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart'; 
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(CalorieTrackerApp());
}

class CalorieTrackerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomePage(),
    );
  }
}

class MealDetail {
  final String mealType;
  final String foodName;
  final String amount;
  final int calories;

  MealDetail({
    required this.mealType,
    required this.foodName,
    required this.amount,
    required this.calories,
  });

  factory MealDetail.fromJson(Map<String, dynamic> json) {
    // We're only calling this if 'total_calories' is NOT in the JSON
    return MealDetail(
      mealType: json['meal_type'] as String? ?? 'Unknown',
      foodName: json['food_name'] as String? ?? 'Unknown',
      amount: json['amount'] as String? ?? 'Unknown',
      calories: json['calories'] as int? ?? 0,
    );
  }
}

class TotalCalories {
  final int totalCalories;

  TotalCalories({
    required this.totalCalories,
  });

  factory TotalCalories.fromJson(Map<String, dynamic> json) {
    // We're only calling this if 'total_calories' IS in the JSON
    return TotalCalories(
      totalCalories: json['total_calories'] as int? ?? 0,
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _controller = TextEditingController();
  String _caloriesOutput = '';
  late FlutterSoundRecorder _audioRecorder;
  bool _isRecorderInitialized = false;
  bool _isRecording = false;
  String _errorMessage = ''; // Add a variable to hold error messages

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  @override
  void dispose() {
    if (_audioRecorder.isRecording) {
      _audioRecorder.stopRecorder();
    }
    _audioRecorder.closeRecorder();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    // Check if the microphone permission is already granted
    var microphonePermissionStatus = await Permission.microphone.status;

    // If not granted, explain why you need it and then request permission
    if (!microphonePermissionStatus.isGranted) {
      // Show a dialog or custom UI to explain why you need this permission
      bool userAgreed = await _showPermissionExplanationDialog();
      if (userAgreed) {
        microphonePermissionStatus = await Permission.microphone.request();
      }

      // Handle the case where the user denies the permission
      if (microphonePermissionStatus != PermissionStatus.granted) {
        setState(() {
          _errorMessage = "Microphone permission is required to record audio.";
        });
        // Optionally, guide the user to the settings app
      }
    }
  }

  Future<bool> _showPermissionExplanationDialog() async {
    // showDialog returns Future<T?> where T is the type of the value that was passed to Navigator.pop
    // when the dialog was closed.
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Microphone Access'),
        content: Text('This app requires microphone access to record audio notes. Please grant this permission to proceed.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Pass false when 'Decline' is tapped.
            child: Text('Decline'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), // Pass true when 'Allow' is tapped.
            child: Text('Allow'),
          ),
        ],
      ),
    ).then((value) => value ?? false); // Ensure a non-nullable bool is returned.
    // Using .then() to provide a default value of false if null is returned.
  }

  Future<void> _initRecorder() async {
    _audioRecorder = FlutterSoundRecorder();

    try {
      await _requestPermissions(); // Ensure permissions are requested
      await _audioRecorder.openRecorder();
      _isRecorderInitialized = true;
      print("Recorder initialized successfully");
    } catch (e) {
      print("Recorder initialization failed: $e");
      setState(() {
        _errorMessage = "Recorder initialization failed: $e"; // Update the error message
      });
    }
  }

  Future<void> _startRecording() async {
    // Directly try to start recording without checking for permissions
    if (!_isRecorderInitialized) {
      print('Recorder not initialized.');
      return;
    }
    try {
      await _audioRecorder.startRecorder(
        toFile: 'audio_record.mp3',
        codec: Codec.mp3,
      );
    } catch (e) {
      try {
        // Fallback to a different codec if MP3 is not supported
        await _audioRecorder.startRecorder(
          toFile: 'audio_record.ogg',
          codec: Codec.ogg,
        );
      } catch (e) {
        print('Failed to start recording with fallback codec: $e');
        // Handle failure
      }
    }
  }


  Future<void> _stopRecording() async {
      print('Trying to stop recording...');
      if (!_isRecorderInitialized || !_isRecording) {
        print('Recorder not initialized or not recording.');
        return;
      }
      try {
        final pathString = await _audioRecorder.stopRecorder();
        print('Stop recorder called');
        if (pathString != null) {
          print('Recording stopped, file path: $pathString');
          final File file = File(pathString);
          // Use the alias `path` for `basename`
          final String fileName = path.basename(pathString); // Adjusted line
          print('File name extracted: $fileName');
          setState(() {
            _isRecording = false;
            _caloriesOutput = "Recording saved to: $pathString";
          });
          print('Calling _uploadFileForNonWeb with file and fileName');

          // Correctly call _uploadFileForNonWeb with both the file and its name
          _uploadFileForNonWeb(file, fileName);
        } else {
          print("Recording path is null.");
        }
      } catch (e) {
        print('Failed to stop recording: $e');
        setState(() {
          _errorMessage = 'Failed to stop recording: $e';
        });
      }
  }

  void _pickFile() async {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.audio);

      if (result != null) {
        PlatformFile platformFile = result.files.first;
        
        if (platformFile.path != null) {
          File file = File(platformFile.path!);
          String fileName = platformFile.name; // Directly use the file name
          _uploadFileForNonWeb(file, fileName); // Correctly calling the method
        } else {
          print('File path is null.');
        }
      } else {
        print('No file selected.');
      }
  }


// -------

  void _uploadFile(List<int> fileBytes, String fileName) async {
    var uri = Uri.parse('http://192.168.2.34:3000/analyzeFoodIntake');
    var request = http.MultipartRequest('POST', uri)
      ..files.add(http.MultipartFile.fromBytes(
        'audioFile',
        fileBytes,
        filename: fileName,
      ));

    var response = await request.send();

    if (response.statusCode == 200) {
      // Decode the response
      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);
      final jsonResponse = json.decode(responseString);
      
      // Correctly parse the response into MealDetail and TotalCalories
      List<dynamic> mealDetails = [];
      for (var item in jsonResponse['meal_intake']) {
        if (item.containsKey('total_calories')) {
          mealDetails.add(TotalCalories.fromJson(item));
        } else {
          mealDetails.add(MealDetail.fromJson(item));
        }
      }

      // Update UI based on parsed data
      setState(() {
        _caloriesOutput = mealDetails.fold('Meal Details:\n', (prev, element) {
          if (element is MealDetail) {
            return "$prev\nMeal Type: ${element.mealType}, Food: ${element.foodName}, Amount: ${element.amount}, Calories: ${element.calories}";
          } else if (element is TotalCalories) {
            return "$prev\nTotal Calories: ${element.totalCalories}";
          }
          return prev; // Should not reach here
        });
      });
      print('File uploaded and processed successfully');
    } else {
      print('File upload failed');
      setState(() {
        _caloriesOutput = 'Failed to upload file.';
      });
    }
  }

  // Make sure this function expects two arguments: File and fileName
  Future<void> _uploadFileForNonWeb(File file, String fileName) async {
    String backendUrl = 'http://192.168.2.34:3000/analyzeFoodIntake';
    print('Uploading file to: $backendUrl');
    print('File to upload: ${file.path}, File name: $fileName');

    try {
      var request = http.MultipartRequest('POST', Uri.parse(backendUrl))
        ..files.add(await http.MultipartFile.fromPath(
          'audioFile',
          file.path,
          filename: fileName,
        ));

      var response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.toBytes();
        final responseString = String.fromCharCodes(responseData);
        final jsonResponse = json.decode(responseString);
        print('File uploaded successfully: $responseString');
        List<dynamic> mealDetails = jsonResponse['meal_intake'];

        bool hasValidInformation = mealDetails.any((element) {
          return element['food_name'] != "No information provided" && element['calories'] != 0;
        });

        if (!hasValidInformation) {
          // Prompt the user for more accurate input
          setState(() {
            _caloriesOutput = "Please provide more specific details about your meal.";
          });
        } else {
          // Update UI with meal details
          setState(() {
            _caloriesOutput = mealDetails.fold('Meal Details:\n', (previousValue, element) {
              final mealDetail = MealDetail.fromJson(element);
              return "$previousValue\nMeal Type: ${mealDetail.mealType}, Food: ${mealDetail.foodName}, Amount: ${mealDetail.amount}, Calories: ${mealDetail.calories}";
            });
          });
        }

        if (jsonResponse['meal_intake'] != null && jsonResponse['meal_intake'].isNotEmpty) {
          // Check if the meal intake data contains valid information
          // Update UI with the meal details
          setState(() {
            _caloriesOutput = 'Meal Details:\n' + jsonResponse['meal_intake'].map((item) {
              return "Meal Type: ${item['meal_type']}, Food: ${item['food_name']}, Amount: ${item['amount']}, Calories: ${item['calories']}";
            }).join('\n');
            if (jsonResponse['meal_intake'].any((item) => item.containsKey('total_calories'))) {
              _caloriesOutput += '\nTotal Calories: ' + jsonResponse['meal_intake'].firstWhere((item) => item.containsKey('total_calories'))['total_calories'].toString();
            }
          });
        } else {
          // Handle the case where no valid meal information was provided
          setState(() {
            _caloriesOutput = 'No valid meal information provided. Please speak clearly about what you ate.';
          });
        }
      } else {
        print('File upload failed, server responded with status code: ${response.statusCode}');
        setState(() {
          _caloriesOutput = 'Failed to upload file.';
        });
      }
    } catch (e) {
      print('An error occurred while uploading the file: $e');
      setState(() {
        _caloriesOutput = 'An error occurred while uploading the file: $e';
      });
    }
  }


  void submitTranscription(String transcription) async {
    setState(() {
      _caloriesOutput = 'Processing...';
    });
    try {
      List<dynamic> mealDetails = await fetchMealDetails();
      setState(() {
        _caloriesOutput = mealDetails.fold('Meal Details:\n', (previousValue, element) {
          if (element is MealDetail) {
            return "$previousValue\nMeal Type: ${element.mealType}, Food: ${element.foodName}, Amount: ${element.amount}, Calories: ${element.calories}";
          } else if (element is TotalCalories) {
            return "$previousValue\nTotal Calories: ${element.totalCalories}";
          } else {
            return previousValue; // In case of unexpected data types
          }
        });
      });
    } catch (e) {
      print("Error fetching meal details: $e"); // Log the error
      setState(() {
        _caloriesOutput = 'Failed to fetch meal details. Error: $e';
      });
    }
  }


  Future<List<dynamic>> fetchMealDetails() async {
    final response = await http.post(
      Uri.parse('http://192.168.2.34:3000/analyzeTextInput'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'transcription': _controller.text,
      }),
    );

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      List<dynamic> mealDetails = [];

      for (var data in jsonResponse['meal_intake']) {
        if (data.containsKey('total_calories')) {
          mealDetails.add(TotalCalories.fromJson(data));
        } else {
          mealDetails.add(MealDetail.fromJson(data));
        }
      }

      return mealDetails;
    } else {
      throw Exception('Failed to load meal details. Status code: ${response.statusCode}');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Calorie Tracker'),
      ),
      body: Container(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Please say or type what you ate:'),
            SizedBox(height: 10),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'E.g., I ate a banana and a bowl of rice',
              ),
              keyboardType: TextInputType.multiline,
              maxLines: null,
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              child: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
            ),
            ElevatedButton(
              onPressed: _pickFile,
              child: Text('Upload Audio'),
            ),
            ElevatedButton(
              onPressed: () => submitTranscription(_controller.text.trim()),
              child: Text('Submit'),
            ),
            SizedBox(height: 20),
            Text(_caloriesOutput, textAlign: TextAlign.left),

            if (_errorMessage.isNotEmpty) // Conditionally display the error message
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_errorMessage, style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}
