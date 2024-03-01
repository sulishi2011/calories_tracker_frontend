import 'dart:io';
import 'dart:convert';
import 'dart:html' as html;
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart'; 
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'js_interop.dart' as jsInterop; // Import your JS interop file
import 'dart:js_util' as js_util;

void main() {
  runApp(CalorieTrackerApp());
}

class AppConfig {
  static const String backendUrl = 'https://vipassana-ai.com:3000';
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
  late FlutterSoundRecorder _audioRecorder;
  bool _isRecorderInitialized = false;
  bool _isRecording = false;
  List<String> _messages = []; // To store messages for UI display
  String _errorMessage = ''; // Add a variable to hold error messages
  String _caloriesOutput = '';

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initRecorder();
    }
  }

  @override
  void dispose() {
    if (_audioRecorder.isRecording) {
      _audioRecorder.stopRecorder().then((_) => _audioRecorder.closeRecorder());
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initRecorder() async {
    _audioRecorder = FlutterSoundRecorder();

    try {
      await _audioRecorder!.openRecorder();
      _isRecorderInitialized = true;
      _addMessage("Recorder initialized successfully");
    } catch (e) {
      _addMessage("Recorder initialization failed: $e");
    }
  }

 Future<void> startRecordingFromDart() async {
    try {
      if (kIsWeb) {
        print('starting recording on web...');
        // For web, call the JS interop function
        jsInterop.startRecording();
      } else {
        print('Starting recording on mobile...');
        // For mobile, ensure the recorder is initialized and then start recording
        if (!_isRecorderInitialized) {
          await _initRecorder();
        }
        String path = await _getFilePath(); // Implement this method based on your file storage logic
        await _audioRecorder.startRecorder(toFile: path);
      }
      setState(() {
        _isRecording = true;
        _addMessage("Recording started successfully.");
      });
      print('Recording has been started successfully.');
    } catch (e) {
      _addMessage("Error starting recording: $e");
    }
  }

  Future<void> stopRecordingFromDart() async {
    try {
      String? audioUrl;
      if (kIsWeb) {
        print('Stopping recording on web...');
        // For web, stop recording and get the audio URL from JS interop
        final audioUrl = await js_util.promiseToFuture<String>(jsInterop.stopRecording());
        
        print('Dart: Recording stopped, received URL: $audioUrl');
        // Upload the Blob URL recording for web
        if (audioUrl != null) {
          print('Uploading blob URL recording for web...');
          await uploadBlobUrl(audioUrl, "web_recording.webm");
          print('Dart: Upload complete, releasing blob URL...');
          // Optionally, release the Blob URL after successful upload
          jsInterop.releaseBlobUrl(audioUrl);
        }
      } else {
        print('Stopping recording on mobile...');
        // For mobile, stop the recorder and get the file path
        audioUrl = await _audioRecorder.stopRecorder();
        // Upload the file recording for mobile
        if (audioUrl != null) {
          print('Uploading file recording for mobile...');
          await uploadFilePath(audioUrl);
        }
      }
      setState(() {
        _isRecording = false;
        _addMessage("Recording stopped. URL/File: $audioUrl");
      });
      // Optionally, handle the audio URL/file here for playback or upload
    } catch (e) {
      _addMessage("Error stopping recording: $e");
    }
  } 

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await stopRecordingFromDart();
    } else {
      await startRecordingFromDart();
    }
    // No need to toggle _isRecording here as it's already done within start/stop methods
  }

  Future<String?> _startRecordingLogic() async {
    if (kIsWeb) {
      try {
        final stream = await html.window.navigator.mediaDevices?.getUserMedia({'audio': true});
        jsInterop.startRecording();
        return null; // Since the file path isn't immediately available
      } catch (e) {
        print("Error starting recording: $e");
        return null;
      }
    } else {
      // Non-web (mobile) logic to start recording.
      var filePath = 'audioFile.mp3'; // Define the file path for recording.
      await _audioRecorder.startRecorder(
        toFile: filePath,
        codec: Codec.mp3, // Make sure to choose a codec supported by your platform.
      );
      return filePath; // Mobile platforms will typically use a file path.
    }
  }

  Future<String?> _stopRecordingLogic() async {
    if (kIsWeb) {
      try {
        final audioUrl = await jsInterop.stopRecording();
        print("Recording stopped, URL: $audioUrl");
        return audioUrl; // Returning the audio URL for further processing
      } catch (e) {
        print("Error stopping recording: $e");
        return null;
      }
    } else {
      // Non-web (mobile) logic to stop recording.
      return await _audioRecorder.stopRecorder(); // This returns the file path where recording is saved.
    }
  }


  // Simplified message handling
  void _addMessage(String message) {
    setState(() => _messages.add(message));
  }

// 给手机端用的逻辑

  Future<String> _getFilePath() async {
    final dir = await getApplicationDocumentsDirectory(); // Requires path_provider package
    return "${dir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.mp3";
  }

  Future<bool> _requestPermissions() async {
    final status = await Permission.microphone.request();
    return status == PermissionStatus.granted;
  }

// blob 转为 字节
  Future<void> uploadBlobUrl(String blobUrl, String fileName) async {
    print("Starting to convert blob URL to bytes: $blobUrl");
    try {
      final Uint8List? bytes = await jsInterop.blobUrlToUint8List(blobUrl);
      if (bytes != null) {
        print("Blob converted to bytes successfully, size: ${bytes.length}");
        await uploadFileBytes(bytes, fileName);
        print("upload BlobUrl: Upload successful.");
      } else {
        print("Failed to convert blob URL to bytes. Blob URL: $blobUrl");
        // Consider how to handle this error in your app's context
      }
    } catch (e) {
      print("An error occurred during blob URL upload: $e");
      // Further error handling
    }
  }
  
 //--- 新版上传

  Future<void> pickAndUploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null) {
      print("Running on Web: $kIsWeb");
      // If on web, the path is always null. Use bytes instead.
      if (kIsWeb) {
        print("Accessing bytes property");

        // Iterate over each picked file
        for (var file in result.files) {
          // Ensure the file has bytes since on the web, files do not have a path
          if (file.bytes != null) {
            await uploadFileBytes(file.bytes!, file.name);
          } else {
            // Handle the case where file.bytes is null
            print("No data available for file: ${file.name}");
          }
        }
      } else {
        print("Accessing path property");

        // For non-web platforms, use the file path
        for (var file in result.files) {
          if (file.path != null) {
            await uploadFilePath(file.path!);
          } else {
            // Handle the case where file.path is null, which should not happen on non-web platforms
            print("File path is unavailable for file: ${file.name}");
          }
        }
      }
    }
  }

  Future<void> uploadFileBytes(Uint8List fileBytes, String fileName) async {
    print("Starting to upload file bytes, size: ${fileBytes.length}, fileName: $fileName");
    var url = Uri.parse('${AppConfig.backendUrl}/analyzeFoodIntake');
    print("Uploading to URL: $url");
    var request = http.MultipartRequest('POST', url)
      ..fields['user'] = 'someone'
      ..files.add(http.MultipartFile.fromBytes(
        'audioFile', // Field name for the file
        fileBytes,
        filename: fileName, // Optional: file name
      ));

    var response = await request.send();
    print("Response status code: ${response.statusCode}");

    if (response.statusCode == 200) {
      // Decode the response
      final responseData = await response.stream.toBytes();
      final responseString = String.fromCharCodes(responseData);
      print("Response from server: $responseString");
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
      print("File upload failed, status code: ${response.statusCode}");
      setState(() {
        _caloriesOutput = 'Failed to upload file.';
      });
    }
  }
  
  Future<void> uploadFilePath(String filePath) async {
    var url = Uri.parse('${AppConfig.backendUrl}/analyzeFoodIntake');
    var request = http.MultipartRequest('POST', url)
      ..fields['user'] = 'someone'
      ..files.add(await http.MultipartFile.fromPath(
        'audioFile', // Field name for the file
        filePath,
        filename: path.basename(filePath), // Optional: file name
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
    String backendUrl = '${AppConfig.backendUrl}/analyzeFoodIntake';
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
      Uri.parse('${AppConfig.backendUrl}/analyzeTextInput'),
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
        title: Text('Calorie Tracker v1.0.3'),
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
              onPressed: _toggleRecording,
              child: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
            ),
            ElevatedButton(
              onPressed: pickAndUploadFile,
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
            // Display each message in the _messages list
            for (var message in _messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(message),
            ),
          ],
        ),
      ),
    );
  }
}
