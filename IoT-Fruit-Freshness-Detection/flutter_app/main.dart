import 'dart:async';
import 'package:flutter/material.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'dart:convert';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fruit Monitoring App',
      theme: ThemeData(
        primarySwatch: Colors.green,
        scaffoldBackgroundColor: Colors.green[100],
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedRack = 1;
  String fruitType = "Apple"; // Example fruit type (dynamic data later)
  String fruitStatus = "Checking"; // Placeholder status (update with actual data)
  String previousFruitStatus = "Checking";
  String temperature = "Loading";
  String humidity = "Loading";
  String gasLevel = "Loading";
  double displaySeconds = 0;
  Timer? _timer;
  Timer? _logtimer;
  bool isSidebarOpen = false;
  bool isLiveViewEnabled = false; // State variable to track live view status
  String selectedPage = "Home";
  List<Map<String, dynamic>> timeLogData = [];
  List<Map<String, String>> notifications = [];
  final String apiBaseUrl = "http://127.0.0.1:5000"; // Your hosting address
  final Uri liveViewUrl = Uri.parse("http://127.0.0.1:5000/video_feed"); // Your hosting address

  @override
  void initState() {
    super.initState();
    initializeNotifications();
    fetchSensorData(); // Fetch data immediately when the widget is initialized
    fetchTimeLogData();
    startAutoRefresh(); // Start the timer to auto-refresh data
  }
  
  @override
  void dispose() {
    _timer?.cancel(); // Cancel the timer when the widget is disposed
    super.dispose();
  }

  // Start the auto-refresh timer
  void startAutoRefresh() {
    _timer = Timer.periodic(Duration(seconds: 3), (timer) {
      fetchSensorData();
    });

    _logtimer = Timer.periodic(Duration(seconds: 10), (timer) {
      fetchTimeLogData();
    });
  }

  // Format display time as HH:MM:SS
  String getFormattedDisplayTime() {
    int totalSeconds = displaySeconds.toInt(); // Convert double to integer
    final hours = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return "$hours:$minutes:$seconds";
  }
  
  // Fetch sensor data
  Future<void> fetchSensorData() async {
    final sensorResponse = await http.get(Uri.parse('$apiBaseUrl/sensor_data'));
    final elapsedTimeResponse = await http.get(Uri.parse('$apiBaseUrl/elapsed_time')); // Fetch elapsed time
    if (sensorResponse.statusCode == 200 && elapsedTimeResponse.statusCode == 200) {
      final sensorData = jsonDecode(sensorResponse.body);
      final elapsedTimeData = jsonDecode(elapsedTimeResponse.body);
      setState(() {
        temperature = "${sensorData['temperature_c']} °C";
        humidity = "${sensorData['humidity']} %";
        gasLevel = "${sensorData['alcohol']}";
        fruitStatus = "${sensorData['fruit_status']}";
        displaySeconds = elapsedTimeData['elapsed_time']; // Update elapsed time
      });
      checkFruitStatus();
    }
  }

  // Notification Function
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  final StreamController<String?> selectNotificationStream =
      StreamController<String?>.broadcast();
  
  void initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      importance: Importance.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notification_sound'),
      enableVibration: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel)
        .then((_) {
          print('Notification channel created successfully');
        }).catchError((error) {
          print('Failed to create notification channel: $error');
        });

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
      },
    );
  }

  void showNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'high_importance_channel',   // Channel ID
      'High Importance Notifications', // Channel Name
      channelDescription: 'This channel is used for important notifications',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('notification_sound'), // Optional: Custom sound
      enableVibration: true, // Enable vibration
      showWhen: true,
      autoCancel: true,
      playSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond, // Notification ID
      title,
      body,
      platformChannelSpecifics,
    );
  }

  void checkFruitStatus() {
    if (fruitStatus != previousFruitStatus) {
      if ((previousFruitStatus == "fresh_apple" || previousFruitStatus == "empty") && fruitStatus == "rotten_apple") {
        showNotification('Caution', 'Rotten apple is detected');
        addNotification('Rotten apple is detected');
      }

      if ((previousFruitStatus == "fresh_apple" || previousFruitStatus == "rotten_apple") && fruitStatus == "empty") {
        showNotification('Caution', 'The rack is empty');
        addNotification('The rack is empty');
      }
      
      previousFruitStatus = fruitStatus;
    }
  }

  void addNotification(String message) {
    final now = DateTime.now();
    final notification = {
      'message': message,
      'time': '${now.hour}:${now.minute}',
      'date': '${now.day}/${now.month}/${now.year}',
    };
    setState(() {
      notifications.insert(0, notification);

      if (notifications.length > 20) {
        notifications.removeLast();
      }
    });
  }

 // Fetch time log data from Google Sheets
 Future<void> fetchTimeLogData() async {
   try {
     final credentials = auth.ServiceAccountCredentials.fromJson({
       "YOUR_GOOGLE_SHEETS_CREDENTIAL_JSON"
      });

      final client = await auth.clientViaServiceAccount(credentials, ["https://www.googleapis.com/auth/spreadsheets.readonly"]); 
      final sheetsApi = sheets.SheetsApi(client);
      final spreadsheetId = "YOUR_SHEET_ID";
      final range = "YOUR_SHEET_RANGE";

      // Fetch data from the sheet
      final response = await sheetsApi.spreadsheets.values.get(spreadsheetId, range);
      final values = response.values;

      if (values != null) {
        setState(() {
          timeLogData = values.reversed.map((row) {
            return {
              "date": row[0] ?? "N/A",
              "time": row[1] ?? "N/A",
              "condition": row[2] ?? "N/A",
            };
          }).toList();
        });
      }

      // Close the client
      client.close();
    } catch (e) {
      print("Error fetching time log data: $e");
    }
  }

  // Check camera permission
  Future<bool> _checkCameraPermission() async {
    final status = await Permission.camera.status;
    return status == PermissionStatus.granted;
  }

  // Request camera permission
  void _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status == PermissionStatus.granted) {
      setState(() {});
    }
  }
  
  // Main structure
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("GreenShelf IQ"),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: toggleSidebar,
        ),
      ),
      body: Stack(
        children: [
          // Main Content Area
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: selectedPage == "Home"
                ? buildHomePage()
                : selectedPage == "Time Log"
                    ? buildTimeLogPage()
                    : selectedPage == "Notification"
                        ? buildNotificationPage()
                        : buildQRScannerPage(), // Show QR Scanner page if selected
          ),
          // Hovering Sidebar
          buildSidebar(),
        ],
      ),
    );
  }

  // Toggle sidebar open/close
  void toggleSidebar() {
    setState(() {
      isSidebarOpen = !isSidebarOpen;
    });
  }

  // Sidebar with rack selection, navigation options, and QR scanner, hovering over main content
  Widget buildSidebar() {
  return Positioned(
    left: isSidebarOpen ? 0 : -200,
    top: 0,
    bottom: 0,
    child: Container(
      width: 200,
      color: Colors.green[800],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              "Select Rack",
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: DropdownButton<int>(
              value: selectedRack,
              dropdownColor: Colors.green[600],
              style: const TextStyle(color: Colors.white),
              isExpanded: true,
              items: List.generate(10, (index) => index + 1)
                  .map((rackNum) => DropdownMenuItem<int>(
                        value: rackNum,
                        child: Text("Rack $rackNum"),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  selectedRack = value!;
                });
              },
            ),
          ),
          const SizedBox(height: 10),
          const Divider(color: Colors.white),
          buildSidebarButton("Home"),
          buildSidebarButton("Time Log"),
          buildSidebarButton("Notification"),
          buildSidebarButton("QR Scanner"),
          const Spacer(), // Use Spacer to push items to the top and keep the sidebar fixed
        ],
      ),
    ),
  );}

  // Update the buildSidebarButton to have consistent padding
  Widget buildSidebarButton(String page) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: ListTile(
        dense: true,
        title: Text(
          page,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        onTap: () {
          setState(() {
            selectedPage = page;
            isSidebarOpen = false;
          });
        },
        selected: selectedPage == page,
        selectedTileColor: Colors.green[600],
      ),
    );
  }

  // Homepage content with fruit status and sensor readings
  Widget buildHomePage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Fruit Type
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.lightGreen[600],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              "Fruit Type: $fruitType (Rack $selectedRack)",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Fruit Status
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.lightGreen[700],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              "Fruit Status: $fruitStatus",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Display Time Counter
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.green[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              "Display Time: ${getFormattedDisplayTime()}",
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Row with Temperature, Humidity, and Gas Level
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildInfoCard("Temperature", temperature),
            _buildInfoCard("Humidity", humidity),
            _buildInfoCard("Alcohol", gasLevel),
          ],
        ),
        const SizedBox(height: 20),
        
        // Toggle Button for Live View
        ElevatedButton(
          onPressed: () {
            setState(() {
              isLiveViewEnabled = !isLiveViewEnabled; // Toggle live view
            });
          },
          child: Text(isLiveViewEnabled ? "Turn Off Live View" : "Turn On Live View"),
        ),
        const SizedBox(height: 20),
        
        // Live View of the Fruit
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: isLiveViewEnabled
                ? Mjpeg(
                    stream: '$apiBaseUrl/video_feed', // URL of your MJPEG stream
                    isLive: true, // Set to true for live streaming,
                    loading: (context) => CircularProgressIndicator(), // Loading indicator
                    error: (context, error, stackTrace) => Text('Error: $error'), // Error widget
                  ) 
                : Center(
                  child: Text(
                    "Live View is Disabled",
                    style: TextStyle(fontSize: 18, color: Colors.grey[700]),
                  ),
                ),
          ),
        ),
      ],
    );
  }

  // Widget to build Temperature, Humidity, and Gas Level Cards
  Widget _buildInfoCard(String title, String value) {
    return Expanded(
      child: Container(
        height: 100,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.lightGreen[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Time Log page as a 3-column table (Date, Time, Action)
  Widget buildTimeLogPage() {
    final limitedData = timeLogData.take(20).toList();

    return SingleChildScrollView(
      child: DataTable(
        columns: [
          DataColumn(label: Text("Date", style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text("Time", style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text("Condition", style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: limitedData.map((log) {
          return DataRow(cells: [
            DataCell(Text(log["date"])),
            DataCell(Text(log["time"])),
            DataCell(Text(log["condition"]?.toUpperCase())),
          ]);
        }).toList(),
      ),
    );
  }

  // Notification Page
  Widget buildNotificationPage() {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notifications'),
      ),
      body: ListView.builder(
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final notification = notifications[index];
          return ListTile(
            title: Text(notification['message']!),
            subtitle: Text('${notification['date']} ${notification['time']}'),
          );
        },
      ),
    );
  }

  // QR Code Scanner Page
  Widget buildQRScannerPage() {
    return FutureBuilder<bool>(
      future: _checkCameraPermission(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data == true) {
          return Center(
            child: ElevatedButton(
              onPressed: () async {
                try {
                  var result = await BarcodeScanner.scan();
                  if (result.rawContent.isNotEmpty) {
                    int scannedRackNumber = int.parse(result.rawContent);
                    setState(() {
                      selectedRack = scannedRackNumber;
                      selectedPage = "Home";
                      isSidebarOpen = false;
                    });
                  }
                } catch (e) {
                  // Handle errors
                  print("Error scanning QR code: $e");
                }
              },
              child: const Text('Scan QR Code'),
            ),
          );
        } else {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "QR Scanner requires camera access",
                  style: TextStyle(fontSize: 18, color: Color.fromARGB(255, 100, 100, 100)),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    _requestCameraPermission();
                  },
                  child: const Text('Allow Camera Access'),
                ),
              ],
            ),
          );
        }
      },
    );
  }
}
