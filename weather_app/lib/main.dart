import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() {
  runApp(const WeatherApp());
}

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryBlue = Color(0xFF1565C0);
    const background = Color.fromARGB(255, 225, 235, 255);

    return MaterialApp(
      title: 'Personalized Weather Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: background,
        primaryColor: primaryBlue,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          primary: primaryBlue,
          secondary: Colors.blueAccent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 6,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              letterSpacing: 0.3,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primaryBlue, width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: primaryBlue, width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
          labelStyle: const TextStyle(color: Colors.black87),
        ),
      ),
      home: const WeatherHome(),
    );
  }
}

class WeatherHome extends StatefulWidget {
  const WeatherHome({super.key});

  @override
  State<WeatherHome> createState() => _WeatherHomeState();
}

class _WeatherHomeState extends State<WeatherHome> {
  final TextEditingController indexController = TextEditingController(text: '');

  bool loading = false;
  String? errorMessage;
  Map<String, dynamic>? currentWeather;
  String requestUrl = '';
  String lastUpdated = '';
  bool isCached = false;

  static const prefKeyJson = 'cached_weather_json';
  static const prefKeyTime = 'cached_weather_time';
  static const prefKeyReqUrl = 'cached_request_url';

  @override
  void initState() {
    super.initState();
    _loadCached();

    // Automatically update latitude/longitude display
    indexController.addListener(() {
      setState(() {});
    });
  }

  // --- Derive coordinates from student index ---
  Map<String, double>? _coordsFromIndex(String rawIndex) {
    final digits = rawIndex.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 4) return null;
    final firstTwo = int.parse(digits.substring(0, 2));
    final nextTwo = int.parse(digits.substring(2, 4));
    final lat = 5 + (firstTwo / 10.0);
    final lon = 79 + (nextTwo / 10.0);
    return {'lat': lat, 'lon': lon};
  }

  String _buildRequestUrl(double lat, double lon) =>
      'https://api.open-meteo.com/v1/forecast?latitude=${lat.toStringAsFixed(2)}&longitude=${lon.toStringAsFixed(2)}&current_weather=true';

  // --- Fetch weather data from API ---
  Future<void> fetchWeather() async {
    setState(() {
      loading = true;
      errorMessage = null;
      isCached = false;
    });

    final idx = indexController.text.trim();
    final coords = _coordsFromIndex(idx);
    if (coords == null) {
      setState(() {
        loading = false;
        errorMessage = 'Invalid index (need at least 4 digits).';
      });
      return;
    }

    final lat = coords['lat']!;
    final lon = coords['lon']!;
    final url = _buildRequestUrl(lat, lon);
    setState(() => requestUrl = url);

    //check for internet connection
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.every((result) => result == ConnectivityResult.none)) {
      await _loadCached(
        allowUiUpdate: true,
        fallbackError: 'No internet connection. Showing cached data.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No internet connection. Showing cached data (if available).',
            ),
            backgroundColor: Color.fromARGB(255, 244, 57, 47),
          ),
        );
      }
      return;
    }

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final cw = body['current_weather'];
        if (cw == null) throw Exception('No weather data found');

        final timeNow = DateTime.now().toIso8601String();
        final displayMap = {
          'index': idx,
          'lat': lat,
          'lon': lon,
          'temperature': cw['temperature'],
          'windspeed': cw['windspeed'],
          'weathercode': cw['weathercode'],
          'fetched_at': timeNow,
        };

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(prefKeyJson, json.encode(displayMap));
        await prefs.setString(prefKeyTime, timeNow);
        await prefs.setString(prefKeyReqUrl, url);

        setState(() {
          currentWeather = displayMap;
          lastUpdated = _formatLocalTime(DateTime.parse(timeNow));
          loading = false;
          isCached = false;
        });
      } else {
        throw Exception('HTTP Error ${response.statusCode}');
      }
    } catch (e) {
      await _loadCached(allowUiUpdate: true, fallbackError: e.toString());
    }
  }

  // --- Load cached data ---
  Future<void> _loadCached({
    bool allowUiUpdate = true,
    String? fallbackError,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedJson = prefs.getString(prefKeyJson);
    final cachedTime = prefs.getString(prefKeyTime);
    final cachedReq = prefs.getString(prefKeyReqUrl) ?? '';

    if (cachedJson != null) {
      final map = json.decode(cachedJson);
      if (allowUiUpdate) {
        setState(() {
          currentWeather = Map<String, dynamic>.from(map);
          requestUrl = cachedReq;
          lastUpdated = cachedTime != null
              ? _formatLocalTime(DateTime.parse(cachedTime))
              : '';
          isCached = true;
          loading = false;
          errorMessage = null;
        });
      }
    } else if (allowUiUpdate) {
      setState(() {
        currentWeather = null;
        loading = false;
        errorMessage =
            fallbackError ??
            'No cached data found. Please connect to internet.';
      });
    }
  }

  String _formatLocalTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final coords = _coordsFromIndex(indexController.text.trim());
    final latStr = coords?['lat']?.toStringAsFixed(2) ?? '--';
    final lonStr = coords?['lon']?.toStringAsFixed(2) ?? '--';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Personalized Weather Dashboard',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          children: [
            // === Input Card ===
            Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  children: [
                    TextField(
                      controller: indexController,
                      decoration: const InputDecoration(
                        labelText: 'Student Index',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // --- Coordinates Display ---
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF64B5F6), Color(0xFF1976D2)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Icon(Icons.explore, color: Colors.white),
                              const SizedBox(height: 4),
                              Text(
                                'Latitude',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue.shade100,
                                ),
                              ),
                              Text(
                                latStr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: Colors.white30,
                          ),
                          Column(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Longitude',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue.shade100,
                                ),
                              ),
                              Text(
                                lonStr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            // === Buttons ===
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: loading ? null : fetchWeather,
                    icon: const Icon(Icons.cloud_outlined),
                    label: const Text('Fetch Weather'),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Load cached data',
                  icon: const Icon(Icons.refresh, color: Colors.blue),
                  onPressed: loading ? null : _loadCached,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // === Request URL ===
            if (requestUrl.isNotEmpty)
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: requestUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied Request URL to clipboard'),
                      backgroundColor: Colors.blueAccent,
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade300, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link, color: Colors.blue, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          requestUrl,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.copy, color: Colors.blue, size: 16),
                    ],
                  ),
                ),
              ),
            // === Weather Display ===
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : errorMessage != null && currentWeather == null
                    ? Center(
                        child: Text(
                          errorMessage!,
                          style: const TextStyle(
                            color: Color.fromARGB(255, 220, 53, 30),
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : currentWeather != null
                    ? _buildWeatherCard()
                    : const Center(
                        child: Text(
                          'Tap “Fetch Weather” to begin.',
                          style: TextStyle(color: Colors.black54, fontSize: 14),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherCard() {
    final cw = currentWeather!;
    final idx = cw['index'] ?? indexController.text.trim();
    final lat = (cw['lat'] as num).toDouble();
    final lon = (cw['lon'] as num).toDouble();
    final temp = cw['temperature'];
    final wind = cw['windspeed'];
    final code = cw['weathercode'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Index: $idx',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            if (isCached)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '(cached)',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
          ],
        ),
        const Divider(),
        const SizedBox(height: 10),
        Text(
          'Latitude: ${lat.toStringAsFixed(2)} | Longitude: ${lon.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 15, color: Colors.black87),
        ),
        const SizedBox(height: 14),
        Text(
          '🌡 Temperature: $temp °C',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1565C0),
          ),
        ),
        Text(
          '💨 Wind Speed: $wind m/s',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        Text(
          '⛅ Weather Code: $code',
          style: const TextStyle(fontSize: 16, color: Colors.black54),
        ),
        const Spacer(),
        Text(
          'Last Updated: $lastUpdated',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
